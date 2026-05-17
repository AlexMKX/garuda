# modules/k3s_cloud_init/tests/smoke

Ansible smoke playbook for the k3s validation roots
(`modules/k3s_cloud_init/tests/{yc,gcp}`).

## What it checks

1. `systemctl is-active k3s` becomes `active` within 5 minutes of `tofu apply`.
2. `ss -tlnp 'sport = :6443'` shows the k3s API bound strictly to
   `127.0.0.1:6443` (never `0.0.0.0:6443`).
3. `kubectl get nodes -o json` reports exactly one node in `Ready` state.
4. `kubectl get pods -A` reports no pods stuck in a non-Running phase.

The playbook runs `kubectl` locally on each VM using the in-VM
kubeconfig at `/etc/rancher/k3s/k3s.yaml`. It does not open
`garuda-tunnel` and does not invoke `kubectl` from the operator
workstation. Operator-side connection is a separate, manual step.

## Usage

```bash
ansible-playbook modules/k3s_cloud_init/tests/smoke/k3s_z2g.yml \
  -e z2g_terraform_dir=modules/k3s_cloud_init/tests/yc
```

To run against the GCP root:

```bash
ansible-playbook modules/k3s_cloud_init/tests/smoke/k3s_z2g.yml \
  -e z2g_terraform_dir=modules/k3s_cloud_init/tests/gcp
```

## Phase tags

Run a single phase:

```bash
ansible-playbook modules/k3s_cloud_init/tests/smoke/k3s_z2g.yml \
  -e z2g_terraform_dir=modules/k3s_cloud_init/tests/yc \
  --tags phase_2
```

## Implementation notes

- Inventory is bootstrapped from `tofu output -json ansible_smoke_inventory`
  in `z2g_terraform_dir`. The static inventory file is materialised at
  `modules/k3s_cloud_init/tests/smoke/.k3s_z2g_inventory` and host SSH keys at
  `.k3s_z2g_<host>.key`. Both are created with mode `0600`; the host
  key files contain sensitive material — do not commit them
  (`.gitignore` is updated in this PR).
- The `become: true` per task is required: `systemctl`, `ss -tlnp`, and
  `kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml` all need root.
- The playbook is idempotent and read-only on the VMs.
