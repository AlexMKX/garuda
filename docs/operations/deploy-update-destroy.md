# Deploy / Update / Destroy

## First-time deploy

1. Complete [prerequisites](../getting-started/prerequisites.md).
2. Prepare inputs (copy `inputs.tfvars.yaml.example`, fill in values).
3. Set `GARUDA_IMAGE_SOURCE=pull` unless you are developing local Docker images.
4. Apply `infra/` first, then `garuda/`.

```bash
cd examples/mini-site/infra
terragrunt plan
terragrunt apply

cd ../garuda
terragrunt plan
terragrunt apply
```

### Firezone OIDC two-pass apply

On the first apply, Firezone starts without an OIDC provider. After the first
apply completes, Firezone creates the OIDC client ID. Run apply a second time to
register the OIDC provider:

```bash
cd examples/mini-site/garuda
terragrunt apply
```

After the first full apply, subsequent applies are single-pass.

## Update

### Terraform module change

Edit module inputs or source, then apply:

```bash
cd examples/mini-site/garuda
terragrunt plan
terragrunt apply
```

Terraform detects changes and re-applies only affected modules.

### Ansible role change

`modules/linux_apply` hashes role sources. If role files under `roles/` change,
the hash drifts and Terraform replaces its `terraform_data.runtime` resource,
which re-invokes the playbook on the host. Just run `terragrunt apply`.

### RouterOS change

Edit the relevant `wireguard/routeros` module inputs and apply:

```bash
cd examples/mini-site/garuda
terragrunt apply
```

### RouterOS DHCP drift reconcile

RouterOS's DHCP client can occasionally rewrite `default-route-tables` in a way
that breaks the WireGuard endpoint bypass route. The public repository does not
currently ship a standalone reconcile playbook; re-apply the `garuda/` unit so
the RouterOS module refreshes the bypass resources:

```bash
cd examples/mini-site/garuda
terragrunt apply
```

## Destroy

Destroy in reverse unit order:

```bash
cd examples/mini-site/garuda
terragrunt destroy

cd examples/mini-site/infra
terragrunt destroy
```

The backbone operator removes its own FRR sidecars on shutdown as part of the
reconcile loop. Shared Docker networks are removed last, after all consumers
are gone.

## Post-apply health check

Run the smoke entrypoint once `examples/mini-site/smoke/z2g.yml` is wired. The
public repository does not currently ship a separate topology health-check
playbook wrapper.

## Further reading

- [Smoke testing](smoke-testing.md)
- [Troubleshooting](troubleshooting.md)
- [First deploy guide](../getting-started/first-deploy.md)
