# k3s validation root (Yandex Cloud)

Minimal end-to-end provisioning unit: one VM, one caller-owned data
disk, k3s installed on first boot via cloud-init, API bound to
`127.0.0.1:6443`. Used as the live gate target for `modules/k3s_cloud_init`.

## Apply

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars
tofu init -upgrade
tofu apply
```

## Verify

After apply, run the smoke playbook from the repo root:

```bash
ansible-playbook modules/k3s_cloud_init/tests/smoke/k3s_z2g.yml \
  -e z2g_terraform_dir=modules/k3s_cloud_init/tests/yc
```

The playbook waits for `k3s.service` to become active, asserts the API
binds strictly to `127.0.0.1:6443`, and asserts a single Ready node
with no pods stuck in a non-Running phase.

## Outputs

| Output                    | Description                                                       |
|---------------------------|-------------------------------------------------------------------|
| `connection_data`         | SSH connection bundle (sensitive).                                |
| `host_public_ipv4`        | Public IPv4.                                                      |
| `ansible_smoke_inventory` | Inventory snippet consumed by `smoke/k3s_z2g.yml` (sensitive).    |

## What this root does NOT do

- Does not fetch kubeconfig to the operator workstation. Use
  `garuda-tunnel` + `ssh garuda@host cat /etc/rancher/k3s/k3s.yaml`.
- Does not join an agent or build a multi-node cluster. Single server only.
- Does not deploy any workloads.
