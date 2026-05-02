# mini-site / garuda

This Terragrunt unit deploys Garuda workloads. It depends on `infra/` outputs.

## Responsibilities

- Deploy hub workloads: backbone network, Firezone, `ipt_server`.
- Deploy edge WireGuard tunnels (Linux peer) for each entry in `edges` map.
- Deploy hub-to-RouterOS WireGuard tunnel (single path).
- Configure routing policy via `routes` and `pinning_egress`.

## Inputs consumed from infra/

| Input                  | Source          |
|------------------------|-----------------|
| `connection_data_hub`  | `infra/` output |
| `connection_data_edges`| `infra/` output |
| `cloudflare_hub`       | `infra/` output |
| `cloudflare_edges`     | `infra/` output |
| `routeros`             | `infra/` output |

## Commands

```bash
# Plan
terragrunt plan

# Apply
terragrunt apply

# Destroy
terragrunt destroy
```

## Notes

- Edge workload modules are deployed with `for_each` over the `edges` map.
- Linux workload modules depend only on the same-host backbone module.
- See [module execution model](../../../docs/reference/module-execution-model.md)
  for the compute -> `linux_apply` -> role -> Docker chain.
- See [routing policy reference](../../../docs/reference/routing-policy.md)
  for `routes` and `pinning_egress` schemas.
