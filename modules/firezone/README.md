# firezone

Workload-centric Terraform module for one Firezone deployment on one Linux
host. Renders the role payload expected by the shared `linux_apply` executor.

## Why

- keeps Firezone-specific inputs explicit at the environment layer
- avoids leaking generic config maps into Terraform composition code

## Inputs

| Name              | Type                  | Default                | Description                                                                       |
| ----------------- | --------------------- | ---------------------- | --------------------------------------------------------------------------------- |
| `name`            | `string`              | _(required)_           | Stable workload identifier used for generated payload artifacts.                  |
| `host_name`       | `string`              | _(required)_           | Inventory host running the Firezone stack.                                        |
| `firezone_dir`    | `string`              | `/opt/garuda/firezone` | Target directory for the Firezone compose project.                                |
| `server_url`      | `string`              | _(required)_           | Public Firezone server URL advertised to clients.                                 |
| `admin_password`  | `string` (sensitive)  | _(required)_           | Bootstrap password for the Firezone admin account.                                |
| `client_subnet`   | `string`              | _(required)_           | Client address pool routed through Firezone (e.g. `10.0.24.0/24`).                |
| `labels`          | `map(string)`         | `{}`                   | Docker container labels. Consumed by the OSPF sidecar operator.                   |
| `connection_data` | `object` (sensitive)  | _(required)_           | Normalized transport/auth contract for the target Linux host.                     |
| `extra_hostvars`  | `map(any)`            | `{}`                   | Optional additional hostvars merged into module-local Ansible vars.               |
| `nic_attach`      | `list(string)`        | `["backbone"]`         | Transport networks to attach. Allowed: `backbone`, `border`.                      |
| `masquerade`      | `bool`                | `false`                | Firezone built-in egress masquerade. **READ THE WARNING BELOW BEFORE OVERRIDING.** |

## Outputs

- `firezone_dir` — effective Firezone compose directory returned by the workload.

## Behavior

- renders the Firezone role payload expected by the shared executor
- applies and destroys the workload through `modules/linux_apply`
- forwards `masquerade` to the role as `fz_masquerade`, which controls
  `WIREGUARD_IPV4_MASQUERADE` / `WIREGUARD_IPV6_MASQUERADE` env vars consumed
  by the upstream Firezone OSS image

## ⚠ `masquerade` — READ THIS BEFORE OVERRIDING

**The default is `false`. This is the correct value for Garuda topologies.**

When `masquerade=false`, the wg-firezone client subnet is preserved end to end
across backbone, wg-tunnels and border. Downstream services (the ipt_server
pinning portal, OSPF transit, conntrack observability) see the real client
tunnel IP rather than a backbone-side proxy IP. In this mode SNAT is owned
exclusively by the border bridge (`oifname "border" masquerade` rendered by
the wireguard role's `postup.sh`).

**!!! IMPORTANT — STAND-ALONE / NON-GARUDA DEPLOYMENTS !!!**

If you use this module **outside the Garuda stack** — meaning there is no
border bridge with masquerade, no `oifname "border"` SNAT chain on an
adjacent wireguard container, and no upstream NAT gateway you control — you
**MUST** set:

```hcl
module "firezone" {
  # ...
  masquerade = true
}
```

Without it, client traffic leaves the host with a non-routable source from
your `client_subnet` (typically `10.0.24.0/24`) and is silently dropped by
the upstream router. With `masquerade=true` Firezone reverts to its built-in
behaviour: rendering an `oifname <iface> masquerade persistent` rule on every
non-wireguard interface it discovers via `/sys/class/net`, which is what the
upstream OSS image expects when run alone.
