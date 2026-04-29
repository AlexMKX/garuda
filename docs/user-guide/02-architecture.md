# 2. Architecture

## Layered view

```
+-----------------------------------------------------------+
|  Control plane (declarative)                              |
|    Terraform (dev/vpn2) -> Ansible roles -> local-exec    |
+-----------------------------------------------------------+
|  Orchestration plane (runtime operators)                  |
|    backbone operator: network_manager / frr_injector /    |
|                       sidecar_operator                    |
+-----------------------------------------------------------+
|  Data plane (workloads)                                   |
|    VPN tunnels * Access Portals * ipt_server *            |
|    FRR sidecars * RouterOS                                |
+-----------------------------------------------------------+
```

The control plane decides what should exist. The orchestration plane
watches Docker on each host and reconciles actual state toward the
desired state. The data plane carries traffic.

## Node roles

Garuda recognises three conceptual node roles. A single host can play
more than one role, but this split makes the topology easier to reason
about.

### Hub

A Linux host that terminates many VPN tunnels at once and hosts
the central workloads: user access portals (like `firezone`), `ipt_server` (policy
routing and DNS intercept), and the backbone operator. In `dev/vpn2`
this is `rutestvpn`.

### Egress

A Linux host with a public IP in a target geography. It accepts a
VPN tunnel from the hub and lets the mesh exit through its
uplink. In `dev/vpn2` this is `outer_pt` (UK uplink).

### Server-client

Any node that joins the mesh as a consumer rather than as a terminator.
It can be:

- a RouterOS device serving a LAN behind it,
- a Linux subnet or server reaching the mesh from its own side,
- an end user onboarded through Firezone.

In `dev/vpn2` a RouterOS device plays this role.

## Shared transport networks

Every Linux host that participates in the mesh has two Docker bridge
networks created and owned by the backbone operator:

- `backbone_network` (172.30.0.0/24 in the example) — control plane
  mesh. OSPF adjacencies and inter-container control traffic ride on
  this bridge.
- `border_network` (172.29.0.0/24 in the example) — egress underlay
  with Docker masquerade to the host uplink.

Runtime contract:
[`roles/backbone_network/files/ospf_injector/network_manager/README.md`](../../roles/backbone_network/files/ospf_injector/network_manager/README.md).

## Terraform modules

| Module                              | Role                                                  | Details                                                                |
|-------------------------------------|-------------------------------------------------------|------------------------------------------------------------------------|
| `modules/linux_host_prerequisites`  | sysctl, Docker daemon config, host prep               | [README](../../modules/linux_host_prerequisites/README.md)             |
| `modules/backbone_network`          | backbone operator plus shared Docker networks         | [README](../../modules/backbone_network/README.md)                     |
| `modules/wireguard/tunnel`          | pure-data: keys and per-peer config for a tunnel pair | inline in `modules/wireguard/tunnel/`                                  |
| `modules/wireguard/linux`           | deploy a WireGuard peer on a Linux host               | inline in `modules/wireguard/linux/`                                   |
| `modules/wireguard/routeros`        | RouterOS WireGuard tunnel, per-tunnel endpoint bypass, and per-tunnel OSPF | [README](../../modules/wireguard/routeros/README.md) |
| `modules/firezone`                  | Firezone compose stack on the hub                     | [README](../../modules/firezone/README.md)                             |
| `modules/firezone_oidc`             | Terraform-native Firezone OIDC provider               | inline in `modules/firezone_oidc/`                                     |
| `modules/ipt_server`                | policy routing and DNS intercept daemon               | [README](../../modules/ipt_server/README.md)                           |
| `modules/linux_apply`               | shared Ansible executor used by all Linux modules     | [README](../../modules/linux_apply/README.md)                          |
| `modules/yc_compute_host`           | provision a VM in Yandex Cloud                        | inline in `modules/yc_compute_host/`                                   |

## Ansible roles

| Role                              | Purpose                                                         |
|-----------------------------------|-----------------------------------------------------------------|
| `roles/backbone_network`          | run the backbone operator (network_manager and FRR injector)    |
| `roles/wireguard`                 | WireGuard tunnel container and routes                           |
| `roles/firezone`                  | Firezone compose stack, credentials, Caddy reverse proxy        |
| `roles/firezone_oidc`             | legacy OIDC role, superseded by the Terraform-native module     |
| `roles/ipt_server`                | ipt_server container and its FRR sidecar companion              |
| `roles/linux_host_prerequisites`  | sysctl, Docker daemon, base packages                            |
| `roles/healthcheck`               | post-apply probe suite                                          |

## Backbone operator

The operator is packaged in
[`roles/backbone_network/files/ospf_injector`](../../roles/backbone_network/files/ospf_injector/README.md)
and is split into three subpackages:

- [`network_manager/`](../../roles/backbone_network/files/ospf_injector/network_manager/README.md)
  creates and validates shared Docker networks and applies host-side
  sysctl through `nsenter`.
- [`frr_injector/`](../../roles/backbone_network/files/ospf_injector/frr_injector/README.md)
  matches workloads by Docker labels, parses FRR intent, renders
  `frr.conf` plus the sidecar environment payload, and reconciles FRR
  sidecars.
- [`sidecar_operator/`](../../roles/backbone_network/files/ospf_injector/sidecar_operator/README.md)
  provides the generic create-replace-remove reconcile loop that
  `frr_injector` plugs into.

For how transit routing is configured from FRR intent, see
[transit concept](../../roles/backbone_network/files/ospf_injector/frr_injector/transit.md).

## FRR sidecars

An FRR speaker is run as a sidecar container that shares the network
namespace (`network_mode: container:<target>`) of its target workload.
This puts OSPF and the transit watcher in the same netns as the
workload without modifying the workload's image.

Runtime contract:
[`roles/backbone_network/files/frr_sidecar/README.md`](../../roles/backbone_network/files/frr_sidecar/README.md).

## ipt_server task layer

`ipt_server` is not a single daemon; it is a set of reconciling tasks
(interfaces cache, route apply, DNS intercept, gateway watcher,
bounded DNS route apply, OSPF failover). Each task has its own
documented contract.

Runtime contract:
[`roles/ipt_server/files/ipt-server/tasks/README.md`](../../roles/ipt_server/files/ipt-server/tasks/README.md).

## Label namespace

Labels carry both ownership markers and FRR intent:

- Kebab-case for operator identifiers:
  `garuda.managed-by`, `garuda.operator-scope`,
  `garuda.sidecar-consumer`, `garuda.target-container`,
  `garuda.backbone-ipv4`, `garuda.sidecar-revision`.
- Dotted paths for hierarchical config:
  `garuda.frr.ospf.enabled`, `garuda.frr.ospf.router_id`,
  `garuda.frr.ospf.interfaces`, `garuda.transit.provider`,
  `garuda.transit.interfaces`.

Full convention:
[`ospf_injector/README.md` — Label naming convention](../../roles/backbone_network/files/ospf_injector/README.md#label-naming-convention).

## Multi-stack isolation and `env_slug`

Garuda is designed to allow several stacks (separate environments,
tenants, dev/prod, etc.) to share underlying substrate — a single
Yandex Cloud VPC, a single GCP project, or a single physical RouterOS
device. To prevent shared-namespace collisions, modules whose
resources live in those shared namespaces accept a mandatory
`env_slug`:

| Module | What `env_slug` scopes |
|---|---|
| `yc_compute_host` | Instance name, VM hostname (per-VPC FQDN), security group, disks, addresses |
| `gcp_compute_host` | Instance name, VM hostname (per-project FQDN), firewall, addresses, disks |
| `wireguard/tunnel` | `tunnel_name` output consumed by RouterOS naming |
| `wireguard/routeros` | All RouterOS resource names (interface, OSPF, bypass table, firewall, scheduler, script) |

Modules creating only host-local resources do not declare `env_slug` —
their namespace is already scoped by `host_name`. This includes
`wireguard/linux`, `ipt_server`, `firezone`, `firezone_oidc`,
`backbone_network`, `linux_apply`, `linux_host_prerequisites`.

`env_slug` is mandatory: 2–24 chars, lowercase alphanumerics and
hyphens. Two stacks must pick different slugs to coexist on a shared
substrate.

### WireGuard tunnel naming split

`wireguard/tunnel` emits two name fields per peer:

- `tunnel_name = "${env_slug}-${name-hyphenated}"` — env-prefixed, used
  by `wireguard/routeros` for all RouterOS resource names so two stacks
  sharing a device do not collide.
- `kernel_ifname = ${name-hyphenated}` — raw (no env prefix), used by
  `wireguard/linux` as the literal Linux kernel interface name.
  Bounded by `IFNAMSIZ=15`. Not env-scoped because Linux interface
  namespaces are per-host — `host_name` already separates stacks.

## Next

See [runtime processes](03-processes.md).
