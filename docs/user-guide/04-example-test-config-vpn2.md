# 4. Three-node example: `test-config/vpn2`

`test-config/vpn2` is a real, deployable topology. It is also the canonical
example for the three Garuda node roles. While the platform is transport-agnostic, this reference implementation explicitly uses WireGuard for tunnels and Firezone for end-user access.

| Node         | Role           | Inventory name          | Responsibilities                                |
|--------------|----------------|-------------------------|-------------------------------------------------|
| `rutestvpn`  | hub            | `rutestvpn-xxl-cx`      | Firezone, `ipt_server`, backbone operator       |
| `outer_pt`   | egress         | `outer-pt-vpn-xxl-cx`   | UK uplink, terminates `wg_uk`                   |
| `routeros`   | server-client  | `r-h-xxl-cx`            | RouterOS branch behind `wg_tik`                 |

## Topology

```
    +-------------------------+       +--------------------------+
    |  outer_pt (EGRESS)      |       |  routeros (SERVER-CLIENT)|
    |  Linux * 203.0.113.12  |       |  RouterOS * 192.168.88.1 |
    |  uplink: ens4 (UK net)  |       |  LAN behind ether1       |
    +-----------+-------------+       +------------+-------------+
                |  wg_uk tunnel                    |  wg_tik tunnel
                |  (10.9.19.0/24)                  |  (10.9.20.0/24)
                |                                  |
          +-----+----------------------------------+-----+
          |  rutestvpn (HUB)                              |
          |  Linux * 203.0.113.10 / vpn.example.com   |
          |                                               |
          |  Workloads:                                   |
          |   * firezone      (user access, OIDC)         |
          |   * ipt_server    (transit egress + geo PBR)  |
          |   * backbone operator                         |
          |                                               |
          |  Firezone clients: 10.0.24.0/24 (WG peers)    |
          +-----------------------------------------------+
```

## File map

- `test-config/vpn2/locals.tf` — canonical topology facts
  (`host_facts`, `tunnel_facts`, `workload_facts`, `ipt_routes`).
- `test-config/vpn2/main.tf` — module wiring and provider bootstrap.
- `test-config/vpn2/outputs.tf` — root outputs and test-only outputs.
- `test-config/vpn2/reconcile_routeros.yml` — developer helper for RouterOS
  DHCP table drift.
- `test-config/vpn2/healthcheck.yml` — post-apply probe suite entry point.
- `test-config/vpn2/destroy.yml` — orderly teardown.
- `test-config/vpn2/smoke/z2g.yml` — final end-to-end smoke playbook
  referenced by `AGENTS.md`.
- `test-config/vpn2/checklist.md` — manual verification checklist.

## `locals.tf` walkthrough

`locals.tf` is organised in three layers.

### Host facts

`host_facts` describes each physical node the stack runs on — its
management address, SSH user, uplink interface name, and optional
public WireGuard endpoint. The three nodes map exactly onto the role
table above. See `test-config/vpn2/locals.tf:5-53`.

### Tunnel facts

`tunnel_facts` describes WireGuard tunnels by name. `wg_uk` connects
`rutestvpn` (hub) to `outer_pt` (egress); `wg_tik` connects
`rutestvpn` (hub) to the RouterOS server-client. Labels under each
peer drive FRR behaviour — for example, `outer_pt` gets
`garuda.frr.ospf.default_originate = "true"` because it is the egress
that originates the default route. See `test-config/vpn2/locals.tf:66-119`.

### Workload facts

`workload_facts` describes non-tunnel workloads on the hub:

- `firezone` — directory, admin password, client subnet, and the OSPF
  labels attached to the container so the backbone operator builds an
  FRR sidecar for it.
- `ipt_server` — directory, router ID, and the set of client CIDRs it
  serves as transit provider.

See `test-config/vpn2/locals.tf:121-146`.

### `ipt_routes`

`ipt_routes` is the geo and domain policy list consumed by
`ipt_server`. In the example:

- A catch-all plus a large list of AWS Germany ranges route through
  `outer_pt` (UK egress).
- `country = "RU"` and `domain = ".*\\.ru"` route through the local
  `border` device, keeping Russian traffic local.

See `test-config/vpn2/locals.tf:180-219`.

## `main.tf` walkthrough

### Host prerequisites

`module.linux_host_prerequisites_rutestvpn` and
`module.linux_host_prerequisites_outer` set Docker log rotation and
sysctl (`ip_forward`, `rp_filter` per interface). These must run
before any workload is deployed. See `test-config/vpn2/main.tf:8-53`.

### WireGuard

`module.wireguard_tunnel_wg_uk` is pure data — it generates keys and
per-peer blocks. `module.wireguard_linux_wg_uk_rutestvpn` and
`..._outer_pt` deploy the tunnel on each side as a Docker container;
`nic_attach = ["backbone", "border"]` attaches it to both shared
networks. `wg_tik` follows the same pattern, with the RouterOS side
handled by `module.wireguard_routeros_wg_tik`. See
`test-config/vpn2/main.tf:57-114` and `test-config/vpn2/main.tf:144-196`.

### RouterOS bootstrap

Two top-level `routeros_*` resources create the `LAN` interface list
and set DNS servers. `module.wg_bypass_routeros` installs the
bypass that keeps the WireGuard endpoint IP reachable through the
DHCP-provided default route, so the tunnel can come up even if the
RouterOS default route is later repointed. See
`test-config/vpn2/main.tf:116-140`.

### Backbone on both Linux nodes

`module.backbone_network_main` (hub) and
`module.backbone_network_outer` (egress) each deploy a backbone
operator with the same shared subnets: `172.30.0.0/24` for
`backbone_network` and `172.29.0.0/24` for `border_network`. See
`test-config/vpn2/main.tf:198-226`.

### Hub workloads

- `module.firezone_main` runs Firezone on the hub, passing
  `admin_password`, `client_subnet`, and the OSPF labels from
  `workload_facts.firezone`.
- `module.ipt_server_main` runs `ipt_server` on the hub with
  `nic_attach = ["backbone", "border"]` and labels marking it as an
  OSPF speaker and a transit provider
  (`garuda.transit.provider = "true"`).

See `test-config/vpn2/main.tf:228-275`.

### RouterOS routing

`module.routing_routeros` configures OSPF inside RouterOS and adds
static routes for the tunnel subnets. A single
`routeros_ip_firewall_nat` resource masquerades VPN traffic leaving
through the RouterOS uplink so that LAN devices can reply. See
`test-config/vpn2/main.tf:277-307`.

## Dependency graph

```
linux_host_prerequisites_{rutestvpn,outer}
        |
        v
backbone_network_{main,outer}
        |
        +---> wireguard_linux_wg_uk_{rutestvpn,outer}
        +---> wireguard_linux_wg_tik_rutestvpn
        |               |
        |               v
        |        wg_bypass_routeros, wireguard_routeros_wg_tik
        |               |
        |               v
        |        routing_routeros
        |
        +---> firezone_main
        +---> ipt_server_main (also depends on both wg linux modules)
```

## Runtime narrative

After `terraform apply`:

1. sysctl and Docker are ready on both Linux hosts.
2. Backbone operators start on both Linux hosts, create shared
   networks, and pass their health checks.
3. WireGuard tunnels come up on each side.
4. Firezone and `ipt_server` start; the backbone operator discovers
   them by label and creates FRR sidecars.
5. OSPF adjacencies form across `wg_uk` and `wg_tik` and across the
   workload FRR sidecars on the hub.
6. `ipt_server` originates the External LSA with `tag=100`; transit
   watchers on Firezone and `wg_tik` consumer sidecars program table
   10000 accordingly.
7. RouterOS OSPF learns the routes and the branch LAN gets access to
   the mesh.
8. Firezone users connect through the hub; their traffic is routed by
   `ipt_server` to either `outer_pt` (UK) or the local border per
   `ipt_routes`.

## Adapting to your own infrastructure

Replace in `test-config/vpn2`:

- `host_facts.*.management_host` and `inventory_name`.
- `wireguard_public_endpoint.host` / `.ip` / `.port` for any node with
  a public WireGuard listener.
- Tunnel subnets in `tunnel_facts.*.subnet_cidr` — they must not
  overlap with `backbone_network` (172.30.0.0/24) or
  `border_network` (172.29.0.0/24).
- OSPF `router_id` values — unique per FRR speaker.
- `ipt_routes` for your policy.
- Secrets (admin password, OIDC credentials) — move out of
  `locals.tf` into `terraform.tfvars` or a secret store.

## Related reading

- Firezone module: [`modules/firezone/README.md`](../../modules/firezone/README.md)
- `ipt_server` module: [`modules/ipt_server/README.md`](../../modules/ipt_server/README.md)
- Transit behaviour:
  [`frr_injector/transit.md`](../../roles/backbone_network/files/ospf_injector/frr_injector/transit.md)
- Shared networks:
  [`network_manager/README.md`](../../roles/backbone_network/files/ospf_injector/network_manager/README.md)
- Verification checklist: [`test-config/vpn2/checklist.md`](../../test-config/vpn2/checklist.md)
