firezone_oidc
=============

Configures OIDC providers on an already-deployed Firezone instance.

**This role must run after `roles/firezone` has completed successfully.**
It does not deploy Firezone itself and will fail if Firezone is not running.

## Usage

This role is dispatched by `modules/firezone_oidc` via `modules/linux_apply`.
Do not invoke it directly in a playbook unless you are bypassing Terraform.

Security Model
--------------

- **Requires Firezone to already be running.** The role connects to the Firezone
  API immediately; it will fail if the Firezone container is not up.
- **Mints its own short-lived API token.** The role runs `bin/create-api-token`
  inside the Firezone container, uses the token to PATCH `/v0/configuration`,
  then deletes the token in an `always:` block. No token is held in TF state.
- **Token is held in Ansible memory only.** All JWT facts use `no_log: true`
  and are cleared at role exit.
- **`client_secret` rotation does not auto-trigger a PATCH.** The Firezone API
  returns masked client secrets, so idempotency comparison cannot detect a
  secret change. After rotating a `client_secret` value, force reconciliation
  by triggering `terraform taint` on `module.firezone_oidc.module.apply.terraform_data.runtime`
  or by making any other payload/role change that causes Terraform to plan a replacement.

Requirements
------------

- Firezone must be deployed and running (via `roles/firezone`).
- The Firezone API must be reachable on the target host at the internal port 13000
  (resolved automatically from the container bridge IP, or overridden via
  `firezone_oidc_api_url`).
- The role is invoked with a `firezone_oidc_config` dict (published as a top-level
  play variable by `modules/linux_apply`'s wrapper playbook). The config dict is
  unpacked by `defaults/main.yml` into the individual role variables below.

Role Variables
--------------

The following variables are set via `defaults/main.yml` from the `firezone_oidc_config`
payload dict. They can also be set directly for non-Terraform invocations.

| Variable                      | Required | Default             | Description                                                                          |
|-------------------------------|----------|---------------------|--------------------------------------------------------------------------------------|
| firezone_oidc_server_url      | **yes**  | (none)              | URL of the running Firezone instance. Must match fz_server_url. Required on both provision and destroy. |
| firezone_oidc_providers       | **yes*** | (none)              | Map of provider name to provider config (see below). *Empty on destroy.             |
| firezone_oidc_dir             | no       | /opt/garuda/firezone | Firezone install directory. Must match fz_firezone_dir.                            |
| firezone_oidc_api_url         | no       | (auto-resolved)     | Override internal API base URL (advanced; not normally needed).                      |

### Provider config shape

Each entry in `firezone_oidc_providers` is keyed by a short provider name
(used as the OIDC provider ID) with the following fields:

| Field                   | Required | Description                                              |
|-------------------------|----------|----------------------------------------------------------|
| client_id               | **yes**  | OAuth2 client ID.                                        |
| client_secret           | **yes**  | OAuth2 client secret.                                    |
| label                   | no       | Human-readable label shown on the Firezone login page.   |
| discovery_document_uri  | no       | OIDC discovery document URL. Defaults to provider standard. |
| redirect_uri            | no       | OAuth2 callback URL. Defaults to Firezone standard path. |
| response_type           | no       | OAuth2 response type. Default: `code`.                   |
| scope                   | no       | Space-separated OIDC scopes. Default: `openid email profile`. |
| auto_create_users       | no       | Auto-create Firezone accounts for new OIDC users. Default: `true`. Set to `false` to require pre-provisioned accounts. |

Testing
-------

A manual test playbook is available in `roles/firezone_oidc/testing/`. It
deploys Firezone via `roles/firezone` on a `testing` inventory group, then
runs this role. Supply an inventory defining `testing` hosts and run:

```bash
ansible-playbook roles/firezone_oidc/testing/playbooks/play.yml \
  -i path/to/inventory.yml
```

Dependencies
------------

None declared. Must be applied after `roles/firezone` in the same play or a subsequent play.
