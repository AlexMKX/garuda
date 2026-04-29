# `linux_apply` role contract

This document is the authoritative reference for authors of Ansible roles
invoked through `modules/linux_apply` ("workload roles"). The contract is
enforced by `tests/test_linux_apply_role_contract.py`.

Design spec: `docs/superpowers/specs/2026-04-21-linux-apply-role-contract-design.md`.

## What is a workload role

A workload role is a role that is invoked by the Terraform
`modules/linux_apply` module's dispatcher playbook
(`modules/linux_apply/files/apply_ansible_workload.yml`) to apply a unit
of state to a Linux host. Utility roles (`common`, `ensure_docker_image`,
`geerlingguy.docker`, `healthcheck`) are not workload roles — they are
`include_role` targets called from within other roles and are invisible
to the dispatcher.

## Hard requirements

A workload role must supply these four files and must not supply a fifth:

| Path | Purpose |
|------|---------|
| `roles/<name>/tasks/provision.yml` | Tasks executed on create/apply. |
| `roles/<name>/tasks/destroy.yml` | Tasks executed on destroy. May be a single `debug` task if destroy is an intentional no-op. |
| `roles/<name>/meta/main.yml` | Standard Ansible galaxy_info + dependencies. |
| `roles/<name>/meta/linux_apply.yml` | Must contain `terraform.linux_apply.compatible: true`. Separate from `meta/main.yml` because Ansible 2.15+ validates `meta/main.yml` against `RoleMetadata._validate_attributes()` and rejects unknown top-level keys. |
| `roles/<name>/meta/argument_specs.yml` | Must declare both `provision:` and `destroy:` entrypoints under `argument_specs:`. |

Prohibited:

- `roles/<name>/tasks/main.yml` — there is no default entrypoint.
- Any reference to `workload_lifecycle` inside `tasks/` — the entrypoint file **is** the lifecycle decision.
- Any `when: workload_lifecycle ...` guard, any `set_fact` normalization of `workload_lifecycle`.
- `present` / `absent` lifecycle vocabulary.
- `| default(...)` fallbacks for `workload_lifecycle`.

## Dispatcher flow

When Terraform applies or destroys a `linux_apply` resource, the
dispatcher playbook on the target host does the following:

1. Assert `workload_lifecycle` is defined and one of `['provision', 'destroy']`.
2. Decode `workload_payload_b64` (base64-encoded JSON from Terraform) and publish each key as a top-level Ansible variable.
3. `include_vars` to load `roles/{{ workload_kind }}/meta/linux_apply.yml` into `_role_meta`.
4. Assert `_role_meta.terraform.linux_apply.compatible is true`.
5. `include_role: name={{ workload_kind }} tasks_from={{ workload_lifecycle }}`.

At step 5, Ansible itself validates that the entrypoint file exists and
validates the role's `argument_specs` for the chosen entrypoint. A
missing entrypoint, a missing required variable, or a type mismatch
fails fast with a clear error.

## `meta/linux_apply.yml` template

```yaml
---
# linux_apply dispatcher compat flag.
# Stored here (not in meta/main.yml) because Ansible 2.15+ validates
# meta/main.yml against RoleMetadata._validate_attributes() and rejects
# unknown top-level keys.
terraform:
  linux_apply:
    compatible: true
```

## `meta/argument_specs.yml` template

```yaml
---
argument_specs:
  provision:
    short_description: <what happens on create/apply>
    options:
      some_required_var:
        type: str
        required: true
      some_optional_var:
        type: str
        required: false
        default: default_value
  destroy:
    short_description: <what happens on destroy>
    options:
      some_required_var:
        type: str
        required: true
```

For roles whose destroy is a no-op, `destroy.options:` may be `{}`.

## No-op destroy pattern

If your role has no persistent state to tear down — for example, a
role that only manipulates an external service which is itself destroyed
by a different role — declare a single-task `destroy.yml`:

```yaml
---
- name: <role> destroy is a no-op
  ansible.builtin.debug:
    msg: "<role> destroy is intentionally a no-op (<reason>)."
```

This makes the no-op visible in logs and prevents it from becoming a
silent skip.

## Internal `include_tasks`

`provision.yml` and `destroy.yml` may `include_tasks` sub-files for
internal decomposition. That is role-local structure and not part of
the external contract. Example:

```yaml
# roles/wireguard/tasks/provision.yml
- ansible.builtin.include_tasks: _render_compose.yml
- ansible.builtin.include_tasks: _converge.yml
```

## Adding a new workload role

1. Scaffold the five required files.
2. Append the role name to the `WORKLOAD_ROLES` tuple in
   `tests/test_linux_apply_role_contract.py`.
3. Run `pytest tests/test_linux_apply_role_contract.py`. The tests
   guide you to completeness.

## FAQ

**Q: My role depends on state established by another role.**
Declare the dependency in `meta/main.yml:dependencies:` with a
utility role (`common`, etc.). Workload-to-workload dependencies
must be expressed at the Terraform level, not inside Ansible.

**Q: Provision needs a large state machine, not just one linear flow.**
Put the machine inside `provision.yml`'s `include_tasks` chain. The
external contract stays binary: `provision` or `destroy`.

**Q: I want a `cleanup` lifecycle distinct from `destroy`.**
No. The dispatcher only supports `provision` and `destroy`. If your
role has an additional operation, express it as a separate
`workload_kind` (= a separate role).

## Helper environment contract (authentication)

`modules/linux_apply/files/run_linux_apply.sh` receives all connection
data via environment variables set by the Terraform `local-exec`
provisioner. The authentication-related inputs are:

| Env var                             | Source                                       | Notes                                             |
|-------------------------------------|----------------------------------------------|---------------------------------------------------|
| `ansible_password`                  | `var.connection_data.password`               | Empty string when unset.                          |
| `ansible_ssh_private_key_file`      | `pathexpand(var.connection_data.ssh_private_key_file)` | Empty string when unset.              |
| `ansible_ssh_private_key_content`   | `var.connection_data.ssh_private_key` (raw)  | Empty string when unset. Mutually exclusive with `ansible_ssh_private_key_file` — Terraform validation rejects both-set on plan; the helper's defensive check rejects it at runtime with exit code 2. |

### Helper cleanup ownership boundary

The helper creates `$tmp_dir` via `mktemp -d` and registers
`trap 'rm -rf "$tmp_dir"' EXIT` before doing any work. Anything the
helper writes — inventory, extra-vars payloads, the materialized
`ssh.key` when `ansible_ssh_private_key_content` is set — lives inside
`$tmp_dir` and is cleaned up automatically.

Paths supplied by the caller through `ansible_ssh_private_key_file` live
outside `$tmp_dir` by construction. The helper reads from them (indirectly,
via Ansible) but never writes to them and never removes them.
