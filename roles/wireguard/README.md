# Ansible Role: wireguard

Deploy a WireGuard tunnel endpoint as a Docker Compose container on a Linux host.
This role is invoked by `modules/wireguard/linux` through `modules/linux_apply`.

## Entrypoints

The role exposes exactly two entrypoints defined in
[`meta/argument_specs.yml`](meta/argument_specs.yml):

| Entrypoint  | Purpose                                        |
|-------------|------------------------------------------------|
| `provision` | Apply WireGuard tunnel runtime config on host  |
| `destroy`   | Remove a WireGuard tunnel from a Linux host    |

`linux_apply` dispatches via `include_role tasks_from={{ workload_lifecycle }}`.
Do not call `tasks_from: generate_config`, `tasks_from: apply_config`, or set
`wireguard_mode` — those are obsolete and not present in this role.

## provision entrypoint variables

| Variable                    | Required | Description                                                     |
|-----------------------------|----------|-----------------------------------------------------------------|
| `wireguard_interface_name`  | yes      | Linux kernel WireGuard interface name (`kernel_ifname`)         |
| `wireguard_address`         | yes      | WireGuard IP address for this peer (e.g. `192.0.2.1/28`)       |
| `wireguard_private_key`     | yes      | WireGuard private key (sensitive)                               |
| `wireguard_table`           | yes      | WireGuard routing table mode (`off`, `auto`, or table number)   |
| `wireguard_peer_public_key` | yes      | Remote peer's WireGuard public key                              |
| `wireguard_peer_allowed_ips`| yes      | List of AllowedIPs for the remote peer                          |
| `wireguard_image`           | yes      | WireGuard Docker image to use                                   |
| `wireguard_tunnel_name`     | no       | Tunnel directory name; defaults to `wireguard_interface_name`   |
| `wireguard_mesh_root`       | no       | Base directory for tunnel config files (default: `/opt/garuda/wg_tunnels`) |
| `wireguard_ops_root`        | no       | Build context root (default: `/opt/garuda/ops`)                 |

## destroy entrypoint variables

| Variable                   | Required | Description                                              |
|----------------------------|----------|----------------------------------------------------------|
| `wireguard_interface_name` | no       | Interface name (used to locate the compose project)      |
| `wireguard_tunnel_name`    | no       | Tunnel directory name                                    |
| `wireguard_mesh_root`      | no       | Base directory (default: `/opt/garuda/wg_tunnels`)       |
| `wireguard_ops_root`       | no       | Build context root (default: `/opt/garuda/ops`)          |

## NAT model — border-only

The deployed container's `postup.sh` installs **exactly one** masquerade rule:
`oifname "border" masquerade`, gated on the presence of `border` in `WG_NIC_ATTACH`.

- No `oifname "<wg-iface>" masquerade`.
- No `oifname "backbone" masquerade`.

Backbone is internal mesh and is never masqueraded. The WireGuard tunnel itself is
never masqueraded so end-to-end source IPs are preserved across the mesh. This is
required by the `ipt_server` pinning portal (which must see the real client tunnel
IP) and by OSPF transit consumers.

Containers without `border` in their attachments install no NAT and no PBR —
only the unconditional MSS clamp. This is the correct configuration for
transit-only leaves (e.g. a RouterOS-facing tunnel) whose traffic is forwarded to
the egress workload by `ipt_server` geo-PBR.

The container also sets `net.ipv4.conf.all.rp_filter=2` (loose) via Docker
`sysctls`. Strict RPF would drop transit packets in a Garuda topology where all
hosts share the same backbone /24.

## Interface naming

The role uses `wireguard_interface_name` (`kernel_ifname` from `wireguard/tunnel`
output) as the Linux kernel interface name. This is bounded by `IFNAMSIZ=15` and
is not env-prefixed — Linux interface namespaces are per-host.

RouterOS-facing naming uses `tunnel_name` (env-prefixed), which is handled by
`modules/wireguard/routeros`, not this role.

## Requirements

- Ansible >= 2.15
- Docker / Docker Compose on target hosts
- `community.docker` collection

## Related

- [`modules/wireguard/linux`](../../modules/wireguard/linux/README.md) — Terraform wrapper.
- [`modules/wireguard/tunnel`](../../modules/wireguard/tunnel/README.md) — Key generation and naming.
- [`modules/wireguard/routeros`](../../modules/wireguard/routeros/README.md) — RouterOS side.
