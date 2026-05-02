# First Deploy

This guide walks through deploying the `examples/mini-site` reference topology
for the first time. The example currently documents the expected layout and
inputs; add the Terragrunt/OpenTofu files for your environment before running
`terragrunt` commands.

## Before you start

Complete all items in [prerequisites](prerequisites.md):

- Terragrunt, OpenTofu, Ansible, and SOPS installed.
- Cloud provider credentials configured.
- SSH key generated and ready.
- `GARUDA_IMAGE_SOURCE` set (`pull` for clients, `build` for developers).

## Step 1: Prepare inputs

Copy and fill in the variable template:

```bash
cp examples/mini-site/inputs.tfvars.yaml.example examples/mini-site/inputs.tfvars.yaml
```

Replace every placeholder value:

- `base_domain` — your actual domain.
- `edges.*.hub_cidr` / `edges.*.peer_cidr` — your WireGuard address ranges.
- `routeros.management_host` — your RouterOS device IP.
- `operator_ssh_keys` — your real SSH public key.

Do not commit `inputs.tfvars.yaml` to version control if it contains real values.
Use SOPS encryption for production inputs.

## Step 2: Apply infra

```bash
cd examples/mini-site/infra
terragrunt plan
terragrunt apply
```

Expected: compute VMs are running, DNS records are created, infra outputs are
available for the garuda unit.

## Step 3: Apply garuda

```bash
cd examples/mini-site/garuda
terragrunt plan
terragrunt apply
```

**Note on Firezone OIDC (two-pass apply).** On the first apply, Firezone starts
without an OIDC provider. After the first apply completes, Firezone creates the
OIDC client ID. Run `terragrunt apply` a second time to register the OIDC
provider with the Firezone API. This is a known bootstrap constraint.

Expected: all workloads are running on hub and edge hosts. Backbone OSPF
adjacencies are up. WireGuard tunnels are active.

## Step 4: Run smoke tests

```bash
cd examples/mini-site/smoke
ansible-playbook z2g.yml
```

The `smoke/` directory describes the expected entrypoint. Wire `z2g.yml` before
using this for live verification. See
[smoke testing runbook](../operations/smoke-testing.md).

## Update

To update workloads after a code change:

```bash
cd examples/mini-site/garuda
terragrunt apply
```

Terraform detects changes and re-applies only affected modules. `linux_apply`
re-runs Ansible for any module whose inputs changed.

## Destroy

Destroy in reverse order:

```bash
cd examples/mini-site/garuda
terragrunt destroy

cd examples/mini-site/infra
terragrunt destroy
```

## Further reading

- [Deploy / update / destroy runbook](../operations/deploy-update-destroy.md)
- [Troubleshooting](../operations/troubleshooting.md)
- [Reference topology](reference-topology.md)
