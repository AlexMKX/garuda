# Smoke Testing

Smoke tests verify end-to-end network reachability after apply. They are separate
from module contract tests (which use mock providers) and operator unit tests
(which use pytest).

## In-repo example smoke

The in-repo reference topology has a smoke entrypoint at:

```
examples/mini-site/smoke/z2g.yml
```

The `smoke/` directory describes the expected `z2g.yml` entrypoint and its
prerequisites. Wire the playbook before using this for live verification.

```bash
cd examples/mini-site/smoke
ansible-playbook z2g.yml
```

## What smoke tests verify

A complete smoke playbook should verify:

- WireGuard tunnel connectivity (hub-to-edge, hub-to-RouterOS).
- OSPF neighbor adjacency on all FRR sidecars.
- Transit route propagation (table 10000 populated on Firezone and RouterOS consumers).
- `ipt_server` routing: geo rule (country match), domain rule (regex match),
  CIDR rule, and pinning egress if enabled.
- Firezone VPN client reachability and API response.
- Docker Compose workload health (all services healthy).
- RouterOS LAN reachability through the WireGuard tunnel.

## Current status

`examples/mini-site/smoke/z2g.yml` is the public path for the reference smoke
playbook, but the file is not wired yet. Use the checklist above as the contract
for the playbook before relying on this example for live verification.

## Running individual checks manually

```bash
# OSPF neighbor state on a sidecar
docker exec <sidecar-container> vtysh -c 'show ip ospf neighbor'

# Transit route table
docker exec <consumer-container> ip route show table 10000

# Backbone operator health
curl http://127.0.0.1:8080/health

# ipt_server logs (replace with the actual container name from docker ps)
docker logs -f garuda_ipt
```

## Further reading

- [Troubleshooting](troubleshooting.md)
- [Testing reference](../reference/testing.md)
- [Deploy / update / destroy](deploy-update-destroy.md)
