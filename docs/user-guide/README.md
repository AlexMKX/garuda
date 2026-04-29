# Garuda user guide

This directory answers, in order of increasing detail:

1. [What Garuda is and how it differs from a classic VPN](01-overview.md)
2. [Which components make up the platform](02-architecture.md)
3. [Which processes run at runtime (failover, OSPF, transit, health gates)](03-processes.md)
4. [A worked three-node example based on `dev/vpn2/`](04-example-dev-vpn2.md)
5. [Operational flows: deploy, verify, update, destroy, troubleshoot](05-operations.md)

Detailed runtime contracts live next to the code they describe.
Pages here link to them rather than restate them.

Key component entry points:

- Backbone operator: [`roles/backbone_network/files/ospf_injector/README.md`](../../roles/backbone_network/files/ospf_injector/README.md)
- FRR sidecar: [`roles/backbone_network/files/frr_sidecar/README.md`](../../roles/backbone_network/files/frr_sidecar/README.md)
- `ipt_server` task layer: [`roles/ipt_server/files/ipt-server/tasks/README.md`](../../roles/ipt_server/files/ipt-server/tasks/README.md)
- Terraform modules: `modules/<name>/README.md`
