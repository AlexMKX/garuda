# Overview

Garuda (**G**eo-distributed **A**utonomous **R**outing **U**nderlay for **D**eclarative
**A**ccess) is a declarative platform that composes VPN tunnels, access portals,
egress gateways, RouterOS devices, and FRR speakers into one geo-distributed mesh
with a shared routing plan and automatic failover.

Like its mythological namesake — the swift, world-spanning avian mount of Hindu
mythology — Garuda transports traffic across isolated realms and boundaries.

## How Garuda differs from a classic VPN

| Dimension      | Classic / commercial VPN   | Garuda                                               |
|----------------|----------------------------|------------------------------------------------------|
| Topology       | star (client -> server)    | mesh (N-to-N plus transit routing)                   |
| Routing        | static single default      | OSPF dynamic plus geo and domain PBR                 |
| Egress         | one endpoint               | multiple egress nodes, chosen per-traffic            |
| Failover       | manual re-connect          | OSPF reconvergence plus health gates                 |
| Configuration  | GUI or ad-hoc scripts      | declarative Terraform plus Ansible roles             |
| Extensibility  | fixed feature set          | operator pattern — add your own workload            |
| End-user UX    | manual config distribution | Firezone self-service                                |

## Key use-cases

**Mesh with failover.** Branches, data centers, or individual servers connect
through a mesh of encrypted WireGuard tunnels. OSPF runs on top, so when a tunnel
or a node goes down the remaining peers reconverge without operator action.

**Geo and domain based traffic distribution.** The `ipt_server` daemon watches DNS
and source traffic, marks packets with `fwmark`, and routes them through the egress
node that matches the rule. A `RU` country code or a `.ru` domain can be pinned to
a local egress; everything else exits through a foreign egress.

**End-user access through Firezone.** Firezone runs on the hub and exposes a
self-service UI for creating VPN peers. Users onboard themselves; their traffic
enters the mesh through a dedicated `wg-firezone` interface and is routed by the
same transit machinery as the rest of the mesh.

**Platform for arbitrary VPN workloads.** The backbone operator discovers workloads
by Docker labels and attaches an FRR sidecar to each one that opts in. New workloads
can be added by writing an Ansible role, a thin Terraform wrapper around
`modules/linux_apply`, and a few Docker labels. No operator changes needed.

## What Garuda is not

- Not a desktop VPN client.
- Not a one-click commercial alternative — you bring your own hosts with public IPs.
- Not a point-and-click GUI — everything is code and Terraform state.

## Further reading

- [Architecture](architecture.md) — planes, node roles, module and role boundaries.
- [Routing model](routing-model.md) — OSPF, transit, PBR, and egress pinning.
