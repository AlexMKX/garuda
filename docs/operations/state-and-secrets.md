# State and Secrets

This page describes the state and secrets model for Garuda deployments. It uses
placeholder values only — do not paste real bucket names, age keys, SOPS
recipients, or cloud IDs here.

## Terraform state

Garuda uses remote state backends for production deployments. Terragrunt
configures the backend for each unit.

Common backend choices:

- **Object storage** (e.g. S3-compatible) — store state files remotely with
  locking. Use a dedicated bucket per environment.
- **Local** — development only; not safe for shared team use.

State files contain sensitive data including SSH private keys and WireGuard
private keys (marked `sensitive = true`). Apply appropriate bucket access
controls and encryption at rest.

## Secrets management

Production deployments encrypt `inputs.tfvars.yaml` with SOPS + age:

```bash
# Encrypt
sops --encrypt inputs.tfvars.yaml > inputs.tfvars.enc.yaml

# Decrypt for apply (Terragrunt handles this automatically with sops provider)
sops --decrypt inputs.tfvars.enc.yaml
```

Keep the SOPS age key outside version control. Store it in a secret manager or a
protected operator workstation.

## What is sensitive

The following values must never appear in plain text in version control:

- SSH private keys (`ssh_private_key` in `connection_data`).
- WireGuard private keys and preshared keys (Terraform marks them `sensitive`).
- Firezone admin password and OIDC client secret.
- Cloud provider credentials and service account keys.
- SOPS age private key.

## What is safe to commit

- Sanitized `inputs.tfvars.yaml.example` with placeholder domains, RFC 5737
  addresses, and example SSH public keys.
- SOPS-encrypted `inputs.tfvars.yaml` (ciphertext only).
- Terraform module source code with no embedded secrets.

## Further reading

- [Prerequisites](../getting-started/prerequisites.md)
- [Reference topology](../getting-started/reference-topology.md)
