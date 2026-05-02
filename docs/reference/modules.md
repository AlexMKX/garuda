# Module Index

This page lists Garuda's Terraform/OpenTofu modules and links to their component
READMEs. Full variable tables live in the module source or its README.

## Compute modules

These modules provision cloud VMs and output `connection_data`. They require
`env_slug` because they create resources in shared cloud namespaces.

| Module               | Cloud     | `env_slug` | README                                               |
|----------------------|-----------|-----------|------------------------------------------------------|
| `yc_compute_host`    | Yandex Cloud | **required** | [README](../../modules/yc_compute_host/README.md) |
| `gcp_compute_host`   | GCP       | **required** | [README](../../modules/gcp_compute_host/README.md) |

## Infrastructure modules

| Module                       | Purpose                                              | README                                                      |
|------------------------------|------------------------------------------------------|-------------------------------------------------------------|
| `linux_host_prerequisites`   | sysctl, Docker daemon config, host prep              | [README](../../modules/linux_host_prerequisites/README.md)  |
| `backbone_network`           | Backbone operator plus shared Docker networks        | [README](../../modules/backbone_network/README.md)          |
| `linux_apply`                | Shared Ansible executor (used by all Linux workloads)| [README](../../modules/linux_apply/README.md)               |

## WireGuard modules

`wireguard/tunnel` requires `env_slug` because it produces `tunnel_name` consumed
by RouterOS (shared namespace). `wireguard/linux` and `wireguard/routeros` do not
declare `env_slug`; they receive the scoped names from `wireguard/tunnel` outputs.

| Module                  | Purpose                                                   | `env_slug`   | README                                               |
|-------------------------|-----------------------------------------------------------|-------------|------------------------------------------------------|
| `wireguard/tunnel`      | Key generation and per-peer config for a tunnel pair      | **required** | [README](../../modules/wireguard/tunnel/README.md)   |
| `wireguard/linux`       | Deploy a WireGuard peer on a Linux host                   | not used     | [README](../../modules/wireguard/linux/README.md)    |
| `wireguard/routeros`    | RouterOS WireGuard tunnel, endpoint bypass, OSPF          | not used     | [README](../../modules/wireguard/routeros/README.md) |

### WireGuard naming split

`wireguard/tunnel` emits two name fields per peer:

| Output field      | Value                                      | Consumer                   |
|-------------------|--------------------------------------------|----------------------------|
| `tunnel_name`     | `"${env_slug}-${name-hyphenated}"`         | `wireguard/routeros`       |
| `kernel_ifname`   | `"${name-hyphenated}"` (max 15 chars)      | `wireguard/linux`          |

## Workload modules

| Module          | Purpose                                        | README                                           |
|-----------------|------------------------------------------------|--------------------------------------------------|
| `firezone`      | Firezone compose stack on the hub              | [README](../../modules/firezone/README.md)       |
| `firezone_oidc` | Terraform-native Firezone OIDC provider        | inline in `modules/firezone_oidc/`               |
| `ipt_server`    | Policy routing and DNS intercept daemon        | [README](../../modules/ipt_server/README.md)     |

## Required `env_slug` summary

| Module               | `env_slug` required | What it scopes                                                |
|----------------------|---------------------|---------------------------------------------------------------|
| `yc_compute_host`    | yes                 | Instance name, hostname (per-VPC FQDN), security group, disks |
| `gcp_compute_host`   | yes                 | Instance name, hostname (per-project FQDN), firewall, disks   |
| `wireguard/tunnel`   | yes                 | `tunnel_name` output (RouterOS resource naming)               |
| `wireguard/routeros` | no                  | Receives scoped `tunnel_name` from `wireguard/tunnel`         |
| all others           | no                  | Host-local namespace, scoped by `host_name`                   |

## Related

- [connection_data contract](connection-data.md)
- [Module execution model](module-execution-model.md)
- [Architecture — env_slug mental model](../concepts/architecture.md#multi-stack-isolation-and-envslug)
