# mini-site / smoke

This directory is the end-to-end verification entrypoint for the mini-site
reference example. Run smoke tests after both `infra/` and `garuda/` are healthy.

## Prerequisites

- Both `infra/` and `garuda/` terragrunt apply completed successfully.
- SSH access to hub and edge hosts (via `connection_data` credentials).
- RouterOS management access (via `routeros.management_host`).
- `ansible` installed and inventory pointing at the deployed hosts.

## Running smoke tests

```bash
ansible-playbook z2g.yml
```

## What z2g.yml verifies

A complete `z2g.yml` playbook for this example environment is not yet included
in this repository. The playbook should verify:

- WireGuard tunnel connectivity (hub-to-edge, hub-to-RouterOS).
- OSPF neighbor adjacency and transit route propagation.
- `ipt_server` routing: geo rules, domain rules, pinning egress.
- Firezone VPN client reachability.
- Docker Compose workload health.

Wire `z2g.yml` into this directory before using this example for live
verification. See [smoke testing runbook](../../../docs/operations/smoke-testing.md).
