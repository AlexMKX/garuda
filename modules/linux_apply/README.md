# linux_apply

Reusable Terraform module that invokes a module-local Ansible wrapper for apply
and destroy using ephemeral payload files.

Why:

- keeps Terraform orchestration generic while workload behavior stays inside Ansible roles
- centralizes payload delivery, source-aware change detection, and destroy-time cleanup in one place

Inputs:

- `host_name`: target inventory host
- `workload_kind`: selector consumed by `modules/linux_apply/files/apply_ansible_workload.yml`
- `payload`: role-native YAML payload
- `connection_data`: SSH/transport/auth parameters (see `variables.tf`).
  Three auth fields are optional and follow the
  [Authentication modes](#authentication-modes) contract:
  `password`, `ssh_private_key_file` (path on disk),
  `ssh_private_key` (raw OpenSSH content, typically sourced from a
  compute module's `ssh_private_key_openssh` output). The two key
  fields are mutually exclusive — Terraform validates this at plan time.
  - `instance_token` (mandatory): opaque invalidation discriminator. Any
    change forces re-execution of the ansible runner for this host. By
    convention populated with the cloud instance id (YC: `instance.id`,
    GCP: `instance.self_link`); semantically the module accepts any string
    that uniquely identifies a substrate generation.
- `extra_hostvars`: optional additional hostvars
- `destroy_payload_override`: optional alternative payload used only at destroy time

Change detection triggers redeploy when any of these change:

- `payload_hash`: hash of the rendered payload
- `role_source_hash`: deterministic hash of the role source tree
- `executor_environment_hash`: hash of shared executor/runtime files
- `ssh_key_fingerprint`: fingerprint of the active SSH key
- `instance_token`: opaque VM-generation discriminator (see `connection_data`)

## Outputs

- `apply_log` — Plain-text per-task ansible log: ISO8601 timestamp, host,
  status (`OK`/`CHANGED`/`SKIP`/`FAIL`/`UNREACHABLE`), task name. One line
  per task. Empty string until the first apply completes; preserved across
  plan-only re-evaluations and overwritten by the next apply.

### Why `instance_token`?

`linux_apply` re-executes ansible only when one of its triggers changes:
inventory variables, ssh key, payload, source files, or `instance_token`.

In a multi-stack setup where the VM is provisioned by a separate
terraform stack (e.g. `infra/`) and the workload is provisioned here
(e.g. `garuda/`), VM recreation does NOT necessarily change the host's
public IP or SSH key — DHCP and key-by-metadata can preserve both. Without
an explicit substrate-generation discriminator, ansible would never
re-run on a freshly recreated VM and the host would come up empty.

The `instance_token` field carries that discriminator. Compute-host
modules emit it from their cloud instance id; multi-stack glue passes
it through unchanged.

## Role contract

The dispatcher strictly requires every `workload_kind` to be an
Ansible role following the contract documented in
[`docs/ansible_role_contract.md`](docs/ansible_role_contract.md).

Supported `workload_lifecycle` values: `provision` (apply) and `destroy`.

## Dispatcher flow

1. Terraform `local-exec` invokes `files/run_linux_apply.sh` with
   `workload_lifecycle=provision` (create-time) or
   `workload_lifecycle=destroy` (destroy-time).
2. The helper runs `ansible-playbook files/apply_ansible_workload.yml`.
3. The playbook asserts strict inputs, decodes the payload, loads the
   role's `meta/linux_apply.yml`, asserts
   `terraform.linux_apply.compatible is true`, then dispatches via
   `include_role tasks_from={{ workload_lifecycle }}`.
4. Ansible validates the role's `argument_specs` for the chosen
   entrypoint before executing it.

## Authentication modes

`connection_data` resolves to an Ansible inventory line and, optionally,
a short-lived materialized key file as follows:

| `password` | `ssh_private_key_file` | `ssh_private_key` | Result                                                                     |
|:----------:|:----------------------:|:-----------------:|----------------------------------------------------------------------------|
| —          | —                      | —                 | system auth (ssh-agent / `~/.ssh/config`); inventory carries no auth attrs |
| ✓          | —                      | —                 | `ansible_password`                                                         |
| —          | ✓                      | —                 | `ansible_ssh_private_key_file=<path>` (path expanded by the module)        |
| —          | —                      | ✓                 | helper writes content to `$tmp_dir/ssh.key`, points Ansible there          |
| ✓          | ✓                      | —                 | both attributes present (Ansible decides)                                  |
| ✓          | —                      | ✓                 | `ansible_password` + materialized key path                                 |
| ✓          | ✓                      | ✓                 | **rejected** on `terraform plan` (key fields are mutually exclusive)       |
| —          | ✓                      | ✓                 | **rejected** on `terraform plan`                                           |

### Raw key usage example

```hcl
module "apply_wg" {
  source        = "…/modules/linux_apply"
  host_name     = "rutestvpn"
  workload_kind = "wireguard"
  payload       = { … }

  connection_data = {
    host            = module.yc_rutestvpn.public_ipv4
    user            = "ubuntu"
    connection      = "ssh"
    network_os      = "linux"
    ssh_private_key = module.yc_rutestvpn.ssh_private_key_openssh
  }
}
```

### Security model

- Raw key material is passed to the helper via the
  `ansible_ssh_private_key_content` environment variable and nothing else.
- The helper writes the key into `$tmp_dir/ssh.key` inside a subshell with
  `umask 077`. No other filesystem write occurs.
- Before `ansible-playbook` is invoked, the helper `unset`s
  `ansible_ssh_private_key_content` so the child process does not inherit
  the raw material in its environment.
- `trap cleanup EXIT` removes `$tmp_dir` in full — including `ssh.key`
  — on any exit path.
- Caller-provided paths in `ssh_private_key_file` live outside `$tmp_dir`
  and are never touched by the helper.
- `terraform plan` output never echoes the raw key: `variable
  "connection_data"` is marked `sensitive = true`, and `triggers_replace`
  fingerprints the key with `sha256(...)` rather than storing it.

## SSH transport reliability defaults

The helper script `files/run_linux_apply.sh` injects sane defaults for
Ansible SSH transport before invoking `ansible-playbook`, so transient
SSH glitches no longer abort an apply with `UNREACHABLE`. Caller env
vars (typically Terragrunt `extra_arguments`) always win — defaults are
applied only when the caller leaves a knob unset.

| Knob | Default | Meaning |
|---|---|---|
| `ANSIBLE_SSH_RETRIES` | `5` | Ansible-level retry budget for SSH connect failures. |
| `ANSIBLE_TIMEOUT` | `30` | Connection timeout in seconds (Ansible-level, default is 10). |
| `ANSIBLE_SSH_ARGS` += `-o ConnectTimeout=30` | — | OpenSSH-level connect timeout. |
| `ANSIBLE_SSH_ARGS` += `-o ServerAliveInterval=15` | — | OpenSSH keepalive cadence. |
| `ANSIBLE_SSH_ARGS` += `-o ServerAliveCountMax=4` | — | Keepalive miss budget (≈60 s before TCP teardown). |

The keepalive flags are appended only when the caller-supplied
`ANSIBLE_SSH_ARGS` does not already pin them, preserving any
host-key/multiplexing policy injected upstream.

To override any default, set the corresponding env var in your
Terragrunt root config (`extra_arguments { env_vars = { ... } }`) or
shell environment before running `terragrunt apply`.
