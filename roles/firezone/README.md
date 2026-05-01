Firezone
=========

The role to deploy [Firezone](https://firezone.dev) onto Ubuntu.

The conntrack-log container is used to get logs of clients communications.

Requirements
------------

Controller node should have `netaddr` pip package installed.

For target node the only requirement is to have Docker installed.

Role Variables
--------------

| Variable              | Required | Default                              | Comments                                              |
|-----------------------|----------|--------------------------------------|-------------------------------------------------------|
| fz_server_url         | yes      | https://{{ ansible_host }}           | The URL where Firezone site will be accessible.       |
| fz_admin              | no       | fz-admin@localhost                   | The admin email.                                      |
| fz_admin_password     | no       | random 12-char base64 string         | Admin password; rendered into `.env` and may rotate on apply. |
| fz_wireguard_port     | no       | 51620                                | The WireGuard UDP port.                               |
| fz_firezone_dir       | no       | /opt/garuda/firezone                 | Location of Firezone configuration and data. Defaults under /opt/garuda so the data disk persists state across VM recreates. |
| fz_firezone_https     | no       | true                                 | Whether Firezone listens on HTTPS.                    |
| fz_client_subnet      | no       | 10.11.0.0/24                         | The WireGuard client subnet.                          |
| fz_mgmt_subnet        | no       | (unset)                              | Management subnet for access control.                 |
| firezone_labels       | no       | {}                                   | Docker container labels applied to the Firezone workload service. |
| fz_host_networking    | no       | false                                | Use host network namespace instead of bridge.         |
| fz_postgres_bind      | no       | 127.0.0.1                            | Postgres bind address (host networking mode only).    |
| fz_postgres_port      | no       | 5432                                 | Postgres port.                                        |
| fz_firezone_image     | no       | local/firezone:0.7.30-nftedgefix     | Docker image to use for the Firezone container.       |
| fz_nic_attach         | no       | `["backbone"]`                       | Transport networks the Firezone container is attached to. Allowed: `backbone`, `border`. |
| fz_masquerade         | no       | `false`                              | Firezone built-in egress masquerade. **READ THE WARNING BELOW BEFORE OVERRIDING.** |

This role is **deploy/bootstrap only**. OIDC and API configuration are handled by a
separate role (`roles/firezone_oidc`).

⚠ `fz_masquerade` — READ THIS BEFORE OVERRIDING
-----------------------------------------------

**The default is `false`. This is the correct value for Garuda topologies.**

When `fz_masquerade=false`, the wg-firezone client subnet is preserved end to
end across backbone, wg-tunnels and border. Downstream services (the
`ipt_server` pinning portal, OSPF transit, conntrack observability) see the
real client tunnel IP rather than a backbone-side proxy IP. In this mode SNAT
is owned exclusively by the border bridge (`oifname "border" masquerade`
rendered by the `wireguard` role's `postup.sh`).

**!!! IMPORTANT — STAND-ALONE / NON-GARUDA DEPLOYMENTS !!!**

If you use this role **outside the Garuda stack** — meaning there is no
border bridge with masquerade, no `oifname "border"` SNAT chain on an
adjacent wireguard container, and no upstream NAT gateway you control — you
**MUST** set `fz_masquerade: true` (or supply it via `fz_config.fz_masquerade`).

Without it, client traffic leaves the host with a non-routable source from
your `fz_client_subnet` (default `10.11.0.0/24`) and is silently dropped by
the upstream router. With `fz_masquerade=true` Firezone reverts to its
built-in behaviour: rendering an `oifname <iface> masquerade persistent`
rule on every non-wireguard interface it discovers via `/sys/class/net`,
which is what the upstream OSS image expects when run alone.

Credentials and Lifecycle
-------------------------

The role manages four **persistent** artifacts that survive `destroy` and `cleanup`:

- `credentials.env` — persistent secret file containing database-coupled and
  runtime-cryptography secrets. Created on first apply with `force: no`; never
  overwritten by subsequent applies.

- `postgres-data/` — PostgreSQL database state.

- `firezone-data/` — Firezone runtime state mounted at `/var/firezone`. Contains the
  WireGuard private key and other Firezone runtime material. If
  `/var/firezone/private_key` already exists when Firezone starts, it is reused.

- `caddy-data/` — Caddy ACME and certificate storage mounted at `/data`. Preserving
  this directory avoids Let's Encrypt re-issuance on destroy/re-apply.

The following artifacts are **regenerable** and are removed on cleanup/destroy:

- `.env` — runtime configuration file. Rewritten on every apply.
  `DEFAULT_ADMIN_PASSWORD` is rendered here and may rotate on apply.

- `docker-compose.yml` and other role-managed files.

Compose loads both files: `firezone` uses `.env` first then `credentials.env`;
`postgres` uses `credentials.env` directly.

**hard cutover:** the supported directory layout uses `firezone-data/` and `caddy-data/`.
The old `firezone/` and `caddy/` directories are not auto-migrated by the role.
A legacy `credentials.env` missing `POSTGRES_PASSWORD` will also fail visibly at
compose startup.

Dependencies
------------
None.

Example Playbook
----------------

```yaml
- name: Install Firezone
  hosts: firezone_host
  roles:
    - firezone
  vars:
    fz_server_url: http://your_firezone_host.tld
```

Testing
-------

There is a sample environment for testing the playbook in `testing` directory.
Provide an inventory that defines the `testing` host group, then run:

```bash
ansible-playbook roles/firezone/testing/playbooks/play.yml \
  -i path/to/inventory.yml
```
