# wireguard/linux

Deploys a WireGuard tunnel endpoint onto a Linux host via the
`wireguard` Ansible role, using `linux_apply` as the execution bridge.

## Interface naming

The Linux WireGuard kernel interface name is taken from
`config.kernel_ifname` (raw, no env_slug). This is bounded by Linux
`IFNAMSIZ=15` and lives in a per-host namespace so does not need
env-scoping.

Use `wireguard/tunnel` as the source for `config` — it emits both
`tunnel_name` (env-prefixed, for RouterOS naming) and
`kernel_ifname` (raw, for Linux). Pass the same `peers["..."]` object
through to this module unchanged.

## Inputs

| Name | Required | Description |
|---|---|---|
| `host_name` | yes | Ansible inventory hostname for the target Linux host. |
| `config` | yes | Canonical tunnel config for this endpoint (from `wireguard/tunnel` output). Must include `kernel_ifname`. |
| `peer` | yes | Canonical tunnel config for the remote endpoint (from `wireguard/tunnel` output). |
| `allowed_nets` | yes | Additional AllowedIPs routed through the tunnel beyond the peer /32. |
| `table` | yes | WireGuard routing table mode (`off`, `auto`, or a table number). |
| `connection_data` | yes | SSH/transport connection contract for the target host. |
| `labels` | no | Docker container labels for workload discovery. |
| `nic_attach` | no | Transport networks to attach (`backbone`, `border`). Default: `["backbone"]`. |
| `persistent_keepalive` | no | PersistentKeepalive seconds. |
| `post_up` | no | WireGuard PostUp command. |
| `pre_down` | no | WireGuard PreDown command. |
| `extra_hostvars` | no | Additional hostvars merged into the ansible host variables. |
