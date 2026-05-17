# k3s validation root (Google Cloud)

Minimal end-to-end provisioning unit: one VM, one caller-owned data
disk, k3s installed on first boot via cloud-init, API bound to
`127.0.0.1:6443`. Mirror of `modules/k3s_cloud_init/tests/yc`.

## Apply

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars
tofu init -upgrade
tofu apply
```

## Verify

```bash
ansible-playbook modules/k3s_cloud_init/tests/smoke/k3s_z2g.yml \
  -e z2g_terraform_dir=modules/k3s_cloud_init/tests/gcp
```

## Outputs

| Output                    | Description                                                       |
|---------------------------|-------------------------------------------------------------------|
| `connection_data`         | SSH connection bundle (sensitive).                                |
| `host_public_ipv4`        | Public IPv4.                                                      |
| `ansible_smoke_inventory` | Inventory snippet for `smoke/k3s_z2g.yml` (sensitive).            |
