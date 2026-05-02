# Architecture

## Planes

```
+-----------------------------------------------------------+
|  Control plane (declarative)                              |
|    Terragrunt / OpenTofu modules -> Ansible roles         |
+-----------------------------------------------------------+
|  Orchestration plane (runtime operators)                  |
|    backbone operator: network_manager / frr_injector /    |
|                       sidecar_operator                    |
+-----------------------------------------------------------+
|  Data plane (workloads)                                   |
|    VPN tunnels * Access portals * ipt_server *            |
|    FRR sidecars * RouterOS                                |
+-----------------------------------------------------------+
```

The **control plane** decides what should exist. The **orchestration plane**
watches Docker on each host and reconciles actual state toward the desired state.
The **data plane** carries traffic.

## Node roles

**Hub.** A Linux host that terminates many VPN tunnels at once and runs the central
workloads: Firezone (user access portal), `ipt_server` (policy routing and DNS
intercept), and the backbone operator.

**Egress.** A Linux host with a public IP in a target geography. It accepts a VPN
tunnel from the hub and lets the mesh exit through its uplink.

**Server-client.** Any node that joins the mesh as a consumer rather than a
terminator: a RouterOS device serving a LAN, a Linux subnet, or an end user
onboarded through Firezone.

## Shared transport networks

Every Linux host in the mesh has two Docker bridge networks created and owned by
the backbone operator:

- **`backbone_network`** — control-plane mesh. OSPF adjacencies and
  inter-container control traffic ride here. No SNAT; source IPs are preserved.
- **`border_network`** — egress underlay with Docker masquerade to the host uplink.
  Border is the only place SNAT happens. Workloads attached to `border`
  (`ipt_server`, WireGuard egress peers) install `oifname "border" masquerade` in
  their own postrouting chain; nothing else masquerades. This keeps source-IP
  transparency end-to-end.

Runtime contract: [`network_manager/README.md`](../../roles/backbone_network/files/ospf_injector/network_manager/README.md).

## Terraform modules

| Module                             | Role                                                   |
|------------------------------------|--------------------------------------------------------|
| `modules/linux_host_prerequisites` | sysctl, Docker daemon config, host prep                |
| `modules/backbone_network`         | backbone operator plus shared Docker networks          |
| `modules/wireguard/tunnel`         | key generation and per-peer config for a tunnel pair   |
| `modules/wireguard/linux`          | deploy a WireGuard peer on a Linux host                |
| `modules/wireguard/routeros`       | RouterOS WireGuard tunnel, endpoint bypass, and OSPF   |
| `modules/firezone`                 | Firezone compose stack on the hub                      |
| `modules/firezone_oidc`            | Terraform-native Firezone OIDC provider                |
| `modules/ipt_server`               | policy routing and DNS intercept daemon                |
| `modules/linux_apply`              | shared Ansible executor used by all Linux workload modules |
| `modules/yc_compute_host`          | provision a VM in Yandex Cloud                         |
| `modules/gcp_compute_host`         | provision a VM in Google Cloud                         |

Full variable contracts: [`docs/reference/modules.md`](../reference/modules.md).

## Ansible roles

| Role                             | Purpose                                                       |
|----------------------------------|---------------------------------------------------------------|
| `roles/backbone_network`         | run the backbone operator (network_manager and FRR injector)  |
| `roles/wireguard`                | WireGuard tunnel container and routes                         |
| `roles/firezone`                 | Firezone compose stack, credentials, Caddy reverse proxy      |
| `roles/firezone_oidc`            | Firezone OIDC bootstrap support used with the Terraform-native module |
| `roles/ipt_server`               | ipt_server container and its FRR sidecar companion            |
| `roles/linux_host_prerequisites` | sysctl, Docker daemon, base packages                          |
| `roles/healthcheck`              | post-apply probe suite                                        |

## Backbone operator

The operator lives in
[`roles/backbone_network/files/ospf_injector`](../../roles/backbone_network/files/ospf_injector/README.md)
and is split into three subpackages:

- **`network_manager/`** — creates and validates shared Docker networks and applies
  host-side sysctl through `nsenter`.
- **`frr_injector/`** — matches workloads by Docker labels, renders `frr.conf` plus
  the sidecar environment payload, and reconciles FRR sidecars.
- **`sidecar_operator/`** — provides the generic create-replace-remove reconcile loop.

## FRR sidecars

An FRR speaker runs as a sidecar container sharing the network namespace
(`network_mode: container:<target>`) of its target workload. OSPF and the transit
watcher live in the same netns as the workload without modifying the workload image.

Runtime contract: [`frr_sidecar/README.md`](../../roles/backbone_network/files/frr_sidecar/README.md).

## Multi-stack isolation and `env_slug`

Garuda allows several stacks (separate environments, tenants, dev/prod) to share
underlying substrate — a single cloud VPC or a single physical RouterOS device.
Modules whose resources live in shared namespaces require a mandatory `env_slug`
to prevent hostname, FQDN, and RouterOS resource collisions.

| Module               | What `env_slug` scopes                                             |
|----------------------|--------------------------------------------------------------------|
| `yc_compute_host`    | Instance name, VM hostname (per-VPC FQDN), security group, disks  |
| `gcp_compute_host`   | Instance name, VM hostname (per-project FQDN), firewall, disks    |
| `wireguard/tunnel`   | `tunnel_name` output (consumed by RouterOS naming)                |

`wireguard/routeros` does not declare `env_slug` directly. It receives the
env-prefixed `tunnel_name` from `wireguard/tunnel` and uses that value for all
RouterOS resource names.

Modules creating only host-local resources do not declare `env_slug` — their
namespace is already scoped by `host_name`. This includes `wireguard/linux`,
`ipt_server`, `firezone`, `backbone_network`, `linux_apply`, and
`linux_host_prerequisites`.

`env_slug` is mandatory: 2–24 chars, lowercase alphanumerics and hyphens. Two stacks
must pick different slugs to coexist on shared substrate.

### WireGuard tunnel naming split

`wireguard/tunnel` emits two name fields per peer:

- `tunnel_name = "${env_slug}-${name-hyphenated}"` — env-prefixed, used by
  `wireguard/routeros` for all RouterOS resource names.
- `kernel_ifname = ${name-hyphenated}` — raw (no env prefix), used by
  `wireguard/linux` as the literal Linux kernel interface name. Bounded by
  `IFNAMSIZ=15`. Not env-scoped because Linux interface namespaces are per-host.

## Further reading

- [Routing model](routing-model.md) — OSPF, transit PBR, and egress pinning concepts.
- [Module execution model](../reference/module-execution-model.md) — the full
  compute → `linux_apply` → role → Docker chain.
- [Module index](../reference/modules.md) — exact variable contracts.
