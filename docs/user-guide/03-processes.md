# 3. Runtime processes

## Deploy and bootstrap

1. Terraform resolves the dependency graph from `depends_on`.
2. For every Linux module, `modules/linux_apply` invokes the relevant
   Ansible playbook against the target host.
3. On the host, `roles/linux_host_prerequisites` runs first (sysctl,
   Docker daemon, packages).
4. `roles/backbone_network` starts the backbone operator container.
   The operator runs with `network_mode: "none"` so it has no
   chicken-and-egg dependency on the networks it is about to create.
5. The operator's `network_manager.ensure_all()` creates
   `backbone_network` and `border_network`, then calls
   `HealthServer.mark_ready()`.
6. `docker compose up --wait` blocks the Ansible task until the health
   endpoint returns 200.
7. Workload modules (VPN tunnels, Firezone, `ipt_server`) deploy in the
   order fixed by `depends_on`.
8. The backbone operator's reconcile loop discovers the new workload
   containers by label and creates FRR sidecars for them. OSPF
   adjacencies form once the sidecars come up.

## OSPF mesh and dynamic routing

Every workload that carries `garuda.frr.ospf.enabled=true` gets an FRR
sidecar attached via `network_mode: container:<target>`. Inside that
shared netns:

- `ospfd` listens on `backbone` and any interface declared in
  `garuda.frr.ospf.interfaces`.
- The router ID is taken from `garuda.frr.ospf.router_id`.
- `default_originate` is set from the label of the same name.

The `frr_injector` renders `frr.conf` from these labels; no
`frr.conf.j2` is maintained per workload.

Details:
[`frr_injector/README.md`](../../roles/backbone_network/files/ospf_injector/frr_injector/README.md).

## Transit routing (dynamic PBR)

Transit routing answers the question "how does a Firezone user's
packet reach the `ipt_server` without hard-coding the `ipt_server`
backbone IP anywhere".

1. The `ipt_server` FRR originates a default route as an External LSA
   with `tag=100` and `forwarding-address=0.0.0.0`.
2. On every transit consumer (a workload whose label
   `garuda.transit.interfaces` is non-empty), the FRR sidecar runs a
   small `transit-watcher.py` loop.
3. The watcher reads `show ip ospf database external json`, finds the
   LSA with the configured tag, looks up the advertising router's
   `ifaceAddress` in `show ip ospf neighbor json`, and writes
   `ip route replace default via <addr> dev backbone table 10000`.
4. `pbrd` programs a rule `iif <transit-iface> lookup 10000` from the
   workload's `pbr-map`.
5. Traffic entering the workload through the transit interface uses
   table 10000; everything else follows the main table.

When the `ipt_server` goes away the External LSA disappears. The
watcher stops refreshing table 10000; stale entries reach the
unreachable nexthop through ARP and the rule falls through to the
main table (Docker GW). This is the documented degraded mode.

Details:
[transit concept](../../roles/backbone_network/files/ospf_injector/frr_injector/transit.md)
and the FRR sidecar
[runtime contract](../../roles/backbone_network/files/frr_sidecar/README.md).

## Failover

### Egress node fails

The tunnel keepalive stops, the OSPF neighbor ages out, and the
External LSA from that egress leaves the LSDB. If another egress
advertises the same route, zebra switches to it and consumers
continue to route through the mesh. If no alternative egress exists,
the transit watcher on each consumer cannot resolve a nexthop and the
default route in table 10000 becomes unreachable, so traffic falls
through to the Docker gateway for local-only outbound.

### `ipt_server` fails

The FRR sidecar attached to `ipt_server` stops, OSPF drops the
adjacency, and the External LSA with `tag=100` disappears. Transit
watchers see no matching LSA and stop refreshing table 10000. Consumer
traffic falls through to the main table (Docker GW). End-user-visible
effect: no more geo-based routing until `ipt_server` comes back.

### Hub fails

RouterOS loses its tunnel peer but its LAN keeps working through
the local uplink (masquerade is always in place on RouterOS). Firezone
users lose service; the current topology has a single hub. Extending
to a multi-hub topology is a deliberate future change.

## Health gates

- The backbone operator runs a stdlib `http.server` on
  `127.0.0.1:8080/health` in the operator container. It returns 503
  until `network_manager.ensure_all()` succeeds, then 200.
- `community.docker.docker_compose_v2` is invoked with `wait: true`,
  which blocks the Ansible run until the container reports healthy.
- `roles/healthcheck` provides a separate post-apply probe suite;
  invoke it through `playbooks/healthcheck_topology.yml`.

## Geo and domain routing

Geo and domain rules live in `test-config/vpn2/locals.tf` as `ipt_routes`.
Each entry has:

- `rules` — matchers: `domain` (regex), `country` (ISO code), `net`
  (CIDR).
- `route` — actions: `gw` (concrete next-hop IP) or `dev` (egress
  interface name).

At runtime the `ipt_server` daemon consumes this list and:

- resolves DNS responses, marks matching flows with `fwmark`,
- programs kernel policy rules so marked packets look up a dedicated
  table and exit through the matching next-hop or device.

Task-level details:
[`ipt_server/tasks` README](../../roles/ipt_server/files/ipt-server/tasks/README.md).

## Destroy

`terraform destroy` (or `test-config/vpn2/destroy.yml`) tears things down in
reverse dependency order. The backbone operator removes its sidecars
on shutdown via the same reconcile loop that created them. Shared
Docker networks are removed last, after all consumers are gone.

## Operator reconcile loop

The backbone operator runs a generic create-replace-remove loop that
polls Docker for containers matching a consumer's discovery filter.
Each consumer (currently only `FRRConsumer`) returns the desired
sidecar state; the loop computes a diff and acts.

Details:
[`sidecar_operator/README.md`](../../roles/backbone_network/files/ospf_injector/sidecar_operator/README.md).

## Next

See [example deployment](04-example-test-config-vpn2.md).
