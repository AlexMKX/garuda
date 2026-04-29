# wireguard/tunnel

Canonical WireGuard tunnel data: per-peer keypairs, preshared key, and
normalized peer config emitted via the `peers` output. The module owns
no deployment logic; consumers (`wireguard/linux`, `wireguard/routeros`)
deploy the tunnel onto their respective endpoint kinds.

## Inputs

| Name | Required | Description |
|---|---|---|
| `name` | yes | Stable tunnel slug (e.g. `hub_edge`). Underscores are replaced by hyphens before use. |
| `subnet` | yes | CIDR subnet for the tunnel transport (e.g. `192.0.2.0/28`). |
| `peers` | yes | Map of exactly two peers keyed by caller-chosen key (e.g. `hub`/`edge`). Each peer carries `address`, `listen_port`, optional `endpoint_host`. |
| `env_slug` | yes | Environment slug embedded into `tunnel_name`. 2–24 chars, lowercase alnum and hyphens. |

## Outputs

`peers` (sensitive) — map keyed by peer key. Each entry contains:

| Field | Purpose |
|---|---|
| `tunnel_name` | `${env_slug}-${name-hyphenated}`. Used by `wireguard/routeros` for ALL its resource names so two stacks sharing a RouterOS device do not collide. |
| `kernel_ifname` | `${name-hyphenated}`. Used by `wireguard/linux` as the literal Linux kernel interface name. Bounded by IFNAMSIZ=15. NOT env-scoped — Linux interface namespace is per-host. |
| `subnet`, `address`, `listen_port`, `endpoint_host` | Pass-through from `var.peers` plus shared `var.subnet`. |
| `private_key`, `public_key`, `preshared_key` | Generated keypair material. |

## Why two name fields?

Linux's `IFNAMSIZ` caps interface names at 15 characters. Adding
`env_slug` to a typical tunnel name (e.g. `prod-hub-edge` = 14 chars
is fine, but `staging-01-hub-edge` = 19 chars) overflows that. Linux per-host interface namespace, however,
does not need env-scoping — `host_name` already keeps stacks separate
on the Ansible side. RouterOS, on the other hand, has a per-device
namespace that several stacks may share, where env scope IS needed.
