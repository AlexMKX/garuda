# Routing Model

## OSPF sidecar model

Garuda does not configure routing on the host directly. Instead, FRR speakers run
as sidecar containers that share the network namespace of their target workload.
Each sidecar has:

- An `ospfd` process listening on `backbone_network` and any additional interfaces
  declared in the workload's `garuda.frr.ospf.interfaces` Docker label.
- A per-workload router ID taken from `garuda.frr.ospf.router_id`.

The backbone operator (`frr_injector`) renders `frr.conf` from these labels.
No per-workload `frr.conf` template is maintained by hand.

## Transit routing

Transit routing answers the question: "how does a Firezone user's packet reach
`ipt_server` without hard-coding the `ipt_server` backbone IP anywhere?"

1. The `ipt_server` FRR sidecar originates a default route as an OSPF External LSA
   with `tag=100` and `forwarding-address=0.0.0.0`.
2. On every transit consumer (a workload with a non-empty
   `garuda.transit.interfaces` label), the FRR sidecar runs a small
   `transit-watcher.py` loop.
3. The watcher reads the OSPF external LSA database, finds the LSA with the
   configured tag, resolves the advertising router's backbone address, and writes
   `ip route replace default via <addr> dev backbone table 10000`.
4. `pbrd` programs a rule `iif <transit-iface> lookup 10000` from the workload's
   PBR map.
5. Traffic entering through the transit interface uses table 10000; everything else
   follows the main table.

When `ipt_server` goes away the External LSA disappears. The watcher stops refreshing
table 10000; stale entries time out and the rule falls through to the main table
(Docker gateway). This is the documented degraded mode.

Details: [transit concept](../../roles/backbone_network/files/ospf_injector/frr_injector/transit.md).

## Geo and domain policy-based routing (PBR)

Policy rules in `ipt_server` describe where categories of traffic should exit the
mesh. Each rule entry has:

- `rules` — a `list(string)` of matchers. Type is inferred by `ipt_server`:
  - CIDR pattern → `net` matcher.
  - ISO 3166-1 alpha-2 code (e.g. `RU`, `DE`) → `country` (geo) matcher.
  - Regular expression (e.g. `.*\.ru`) → `domain` matcher.
- `route` — where to send matching traffic: `{ gw = "<ip>" }` for a concrete
  next-hop or `{ dev = "<interface>" }` for a device.

At runtime `ipt_server`:

1. Intercepts DNS responses and resolves matching IPs for domain/geo rules.
2. Marks matching flows with `fwmark`.
3. Programs kernel policy rules so marked packets look up a dedicated routing table
   and exit through the correct next-hop or device.

Full schema: [`docs/reference/routing-policy.md`](../reference/routing-policy.md).

## Per-source egress pinning

`ipt_server` supports a pinning feature that assigns individual source clients to
a specific egress. When a client performs a pinned lookup, `ipt_server` records the
client's source IP and enforces a consistent egress for subsequent traffic, for up
to `pinning_ttl` seconds.

Configuration:

```hcl
pinning_egress = {
  usa = { gw = "192.0.2.2" }
}
pinning_ttl = 86400
```

Setting `pinning_egress = {}` disables the feature entirely.

## Failover behavior

**Egress node fails.** The WireGuard tunnel keepalive stops, the OSPF neighbor ages
out, and the External LSA from that egress leaves the LSDB. If another egress
advertises the same route, zebra switches to it and consumers continue routing through
the mesh. If no alternative exists, table 10000 becomes unreachable and traffic falls
through to the Docker gateway.

**`ipt_server` fails.** The FRR sidecar stops, OSPF drops the adjacency, and the
External LSA with `tag=100` disappears. Transit watchers stop refreshing table 10000.
Consumer traffic falls through to the main table. Effect: no more geo-based routing
until `ipt_server` recovers.

**Hub fails.** RouterOS loses its tunnel peer but its LAN continues working through
the local uplink. Firezone users lose service; the current topology has a single hub.
Multi-hub is a deliberate future change.

## Further reading

- [Architecture](architecture.md) — planes, node roles, module boundaries.
- [Routing policy reference](../reference/routing-policy.md) — exact `routes` and
  `pinning_egress` schemas.
- [FRR injector runtime](../../roles/backbone_network/files/ospf_injector/frr_injector/README.md)
- [Transit concept detail](../../roles/backbone_network/files/ospf_injector/frr_injector/transit.md)
