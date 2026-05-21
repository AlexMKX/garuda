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

## Operator prerequisites

This unit's Terragrunt wrapper invokes `garuda-tunnel` through `uvx` in a
`before_hook` to open an SSH local-forward to each edge k3s apiserver
and fetch its kubeconfig in the same SSH session. The only operator
prerequisite is `uv` on `$PATH`:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

The hook pins `garuda-tunnel` to
`git+https://github.com/AlexMKX/garuda-tunnel.git@main`. `uvx` caches
the install in `~/.cache/uv/` and only re-resolves when the `main` HEAD
moves. To freeze, replace `@main` with `@<sha>` or `@<tag>` in the
consumer `terragrunt.hcl`.

## Commands

```bash
# Plan
terragrunt plan

# Apply
terragrunt apply

# Destroy
terragrunt destroy
```

The before-step that spawns `garuda-tunnel` passes
`daemon.auto_stop_idle_seconds = 300`, so a daemon that nobody connects
to for five minutes SIGTERMs itself. Orphan recovery is automatic —
no manual `pkill` needed even if Terragrunt is killed mid-apply, parse-
only commands (`output`, `hclvalidate`) leave the tunnel up, or a
SIGINT skips the `after_hook`. Stale marker files in `$TMPDIR` are
harmless once the daemon exits; the next invocation allocates a fresh
`mktemp -u` name.

## Notes

- Edge workload modules are deployed with `for_each` over the `edges` map.
- Linux workload modules depend only on the same-host backbone module.
- See [module execution model](../../../docs/reference/module-execution-model.md)
  for the compute -> `linux_apply` -> role -> Docker chain.
- See [routing policy reference](../../../docs/reference/routing-policy.md)
  for `routes` and `pinning_egress` schemas.
