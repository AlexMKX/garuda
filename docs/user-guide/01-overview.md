# 1. What Garuda is and why it exists

## Definition

Garuda (**G**eo-distributed **A**utonomous **R**outing **U**nderlay for **D**eclarative **A**ccess) is a declarative platform that composes several VPN building
blocks — VPN tunnels, access portals (like Firezone), egress gateways, RouterOS
devices, FRR speakers — into one geo-distributed mesh with a single
routing plan and automatic failover. 

Like its mythological namesake — the swift, world-spanning avian mount of Hindu mythology — Garuda transports traffic across isolated realms and boundaries.

While its reference topology uses WireGuard and Firezone, they are just implementations. Garuda is an orchestrator that
ties these pieces together, instruments them with an operator that
watches Docker labels, and exposes a Terraform-shaped interface for
day-two operations.

## How Garuda differs from a classic VPN

| Dimension        | Classic / commercial VPN   | Garuda                                               |
|------------------|----------------------------|------------------------------------------------------|
| Topology         | star (client -> server)    | mesh (N-to-N plus transit routing)                   |
| Routing          | static single default      | OSPF dynamic plus geo and domain PBR                 |
| Egress           | one endpoint               | multiple egress nodes, chosen per-traffic            |
| Failover         | manual re-connect          | OSPF reconvergence plus health gates                 |
| Configuration    | GUI or ad-hoc scripts      | declarative Terraform plus Ansible roles             |
| Extensibility    | fixed feature set          | operator pattern — add your own workload            |
| End-user UX      | manual config distribution | Firezone self-service                                |

## Key use-cases

### Mesh with failover

Branches, data centers, or individual servers connect through a mesh
of encrypted VPN tunnels. OSPF runs on top, so when a tunnel or a node
goes down the remaining peers reconverge without operator action.

### Geo and domain based traffic distribution

The `ipt_server` daemon on the hub watches DNS and source traffic,
marks packets with `fwmark`, and routes them through the egress node
that matches the rule. A `RU` country or a `.ru` domain can be pinned
to a local egress; everything else can exit through a foreign egress.

### End-user access through Firezone

Firezone runs on the hub and exposes a self-service UI for creating
VPN peers. Users onboard themselves; their traffic enters the
mesh through a dedicated `wg-firezone` interface and is routed by the
same transit machinery as the rest of the mesh.

### Platform for arbitrary VPN workloads

The backbone operator discovers workloads by Docker labels and
attaches an FRR sidecar to each one that opts in. New workloads
(another VPN terminator, another egress gateway, a site bridge) can
be added by writing an Ansible role, a thin Terraform wrapper around
`modules/linux_apply`, and a few labels. No operator changes needed.

## Key architectural properties

- Declarative pipeline: Terraform drives `linux_apply`, which drives
  Ansible roles, which drive Docker compose stacks.
- Label-driven operator pattern: FRR configs and sidecars are
  generated from Docker labels; no `frr.conf` is edited by hand.
- Fail-fast bootstrap with health gates: the backbone operator
  refuses to mark itself ready until shared networks exist and host
  sysctl is correct.
- Dynamic transit routing: egress selection is learned through OSPF
  External LSA tags and applied via a runtime watcher inside each
  consumer's FRR sidecar.

## What Garuda is NOT

- Not a desktop VPN client.
- Not a one-click commercial alternative — you bring your own hosts
  with public IPs.
- Not a point-and-click GUI — everything is code and Terraform state.

## Next

See [component architecture](02-architecture.md).
