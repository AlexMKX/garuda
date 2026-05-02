# Mini-Site Reference Example

This directory is the public sanitized reference topology for Garuda. It contains
a template that operators can copy and adapt — not production credentials or real
cloud IDs.

The directory currently contains documentation and sanitized inputs only. Add the
Terragrunt/OpenTofu files for your environment before running the commands below.

## Units

Deploy in order:

1. **`infra/`** — Provisions compute, DNS, and RouterOS bootstrap resources.
   Exports: `connection_data_hub`, `connection_data_edges`, `cloudflare_hub`,
   `cloudflare_edges`, `routeros`.

2. **`garuda/`** — Consumes `infra/` outputs and deploys hub workloads, edge
   WireGuard tunnels, RouterOS tunnel, Firezone, and `ipt_server`.

3. **`smoke/`** — End-to-end verification after apply. Run after both units are
   healthy.

## Quick start

```bash
cd examples/mini-site/infra
terragrunt apply

cd ../garuda
terragrunt apply

cd ../smoke
ansible-playbook z2g.yml
```

The `smoke/` directory describes the expected `z2g.yml` entrypoint. Wire the
playbook before using this example for live verification.

## Adapting for real deployments

1. Copy `inputs.tfvars.yaml.example` to `inputs.tfvars.yaml` (or your SOPS-encrypted
   equivalent) and replace every placeholder value.
2. Replace `example.net` with your actual base domain.
3. Replace RFC 5737 CIDRs (`192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`)
   with your actual WireGuard address ranges.
4. Add real cloud provider credentials and SSH keys.

Do not commit real secrets to version control.

## Further reading

- [Reference topology walkthrough](../../docs/getting-started/reference-topology.md)
- [First deploy guide](../../docs/getting-started/first-deploy.md)
- [Module index](../../docs/reference/modules.md)
