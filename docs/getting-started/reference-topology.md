# Reference Topology Walkthrough

The `examples/mini-site/` directory inside this repository is the canonical
sanitized reference topology. It demonstrates a three-node Garuda deployment:

| Node       | Role          | Responsibilities                                        |
|------------|---------------|---------------------------------------------------------|
| hub        | hub           | Firezone, `ipt_server`, backbone operator               |
| usa (edge) | egress        | foreign-geography uplink, terminates Linux WG tunnel    |
| routeros   | server-client | RouterOS branch device behind a WireGuard tunnel        |

This is a template for operators to adapt — not production credentials or real
cloud IDs. See `examples/mini-site/inputs.tfvars.yaml.example` for the variable
shape.

## Unit structure

```
examples/mini-site/
  infra/           # Provisions compute, DNS, and RouterOS bootstrap facts
  garuda/          # Deploys workloads (consumes infra outputs)
  smoke/           # End-to-end verification
  inputs.tfvars.yaml.example
```

## infra/ unit

The `infra/` unit provisions cloud compute and DNS and exports the facts that
`garuda/` needs:

| Output                  | Type                     | Consumer                             |
|-------------------------|--------------------------|--------------------------------------|
| `connection_data_hub`   | `connection_data` object | `linux_apply` on hub workloads       |
| `connection_data_edges` | map of `connection_data` | `linux_apply` on edge workloads      |
| `cloudflare_hub`        | DNS record object        | hub DNS facts                        |
| `cloudflare_edges`      | map of DNS records       | edge DNS facts                       |
| `routeros`              | RouterOS bootstrap object | `wireguard/routeros` module          |

## garuda/ unit

The `garuda/` unit deploys all workloads in dependency order:

1. `linux_host_prerequisites` on hub and each edge.
2. `backbone_network` on hub and each edge.
3. WireGuard tunnels:
   - `wireguard/tunnel` (key generation, per-peer config).
   - `wireguard/linux` on each Linux side.
   - `wireguard/routeros` for the hub-to-RouterOS path.
4. Hub workloads: `firezone`, `ipt_server`.

Edge workload modules are created with `for_each` over the `edges` map. Each
iteration deploys one WireGuard Linux peer. The hub-to-RouterOS path is a single
explicit module, not an iteration.

Linux workload modules depend only on the same-host backbone module:

```hcl
module "wireguard_linux_usa" {
  source     = "../../modules/wireguard/linux"
  # inputs ...
  depends_on = [module.backbone_network["usa"]]
}
```

This is the required pattern — cross-host `depends_on` must not be used.

## Key variable concepts

**`edges` map.** Each key becomes one egress peer. Adding a new edge means
adding a key to the `edges` map; the `for_each` creates all required resources
automatically.

**`env_slug`.** Mandatory for `yc_compute_host`, `gcp_compute_host`,
`wireguard/tunnel`, and `wireguard/routeros`. Scopes all cloud and RouterOS
resource names so multiple stacks can share the same substrate. Two stacks must
use different slugs.

**`instance_token`.** Populated by the compute module from the cloud instance
identity. Do not set it manually. `linux_apply` uses changes to this token to
detect VM recreation and force Ansible re-apply. See
[connection_data contract](../reference/connection-data.md).

## Routing policy

The hub's `ipt_server` module accepts a `routes` list that defines geo/domain/CIDR
policy. The example in `inputs.tfvars.yaml.example` starts with an empty
`ipt_routes_germany_nets` list. Populate it with rules to route specific traffic
through the USA edge or keep it local.

Full schema: [routing policy reference](../reference/routing-policy.md).

## Further reading

- [First deploy](first-deploy.md) — step-by-step commands.
- [Architecture](../concepts/architecture.md) — planes and node roles.
- [Module execution model](../reference/module-execution-model.md)
- [Add a Linux egress](../how-to/add-linux-egress.md)
