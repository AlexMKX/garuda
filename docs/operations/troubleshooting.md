# Troubleshooting

## Quick symptom table

| Symptom                                          | First command                                                          |
|--------------------------------------------------|------------------------------------------------------------------------|
| Backbone operator does not become ready          | `docker logs garuda-backbone-operator` on the host                     |
| OSPF neighbor does not come up                   | `docker exec <sidecar> vtysh -c 'show ip ospf neighbor'`               |
| Transit route missing on a consumer              | `docker exec <consumer> ip route show table 10000`                     |
| WireGuard tunnel is down                         | `docker exec <wg-container> wg show`                                   |
| Firezone returns 401 during `terraform apply`    | Two-pass apply — see [deploy guide](deploy-update-destroy.md#firezone-oidc-two-pass-apply) |
| Firezone API or OIDC not responding              | `docker logs <firezone-container>`, check `fz_admin` credentials       |
| RouterOS cannot reach WireGuard tunnel endpoint  | Re-apply the `garuda/` unit — see [RouterOS DHCP drift](#routeros-dhcp-drift) |
| `ipt_server` geo/domain routing not working      | `docker logs -f <ipt_server-container>`; check `routes` config         |
| `ipt_server` pinning not engaging                | Check `pinning_egress` is non-empty; verify client source IP routing   |
| Docker Compose service unhealthy                 | `docker compose -f <dir>/docker-compose.yml ps`, `docker logs <svc>`  |
| Ansible re-apply not triggered after role change | Check `terraform plan`; `linux_apply` should show resource replacement |
| SSH connection refused                           | Check host sysctl (`ip_forward`), Docker daemon, and `linux_host_prerequisites` |

## Backbone operator

```bash
# Operator logs
docker logs garuda-backbone-operator

# Health check
curl http://127.0.0.1:8080/health

# List managed sidecars
docker ps --filter label=garuda.managed-by=ospf-injector
```

## OSPF and transit routing

```bash
# Neighbor state on any FRR sidecar
docker exec <sidecar-container> vtysh -c 'show ip ospf neighbor'

# OSPF external LSA database (check for ipt_server tag=100)
docker exec <sidecar-container> vtysh -c 'show ip ospf database external'

# Transit route table on a consumer
docker exec <consumer-container> ip route show table 10000

# FRR sidecar logs
docker logs <sidecar-container>
```

## WireGuard

```bash
# WireGuard interface state
docker exec <wg-container> wg show

# Check peer handshake time
docker exec <wg-container> wg show <ifname> latest-handshakes
```

## ipt_server

```bash
# Follow logs
docker logs -f <ipt_server-container>

# Check nftables marks
docker exec <ipt_server-container> nft list ruleset
```

## Firezone

```bash
# Firezone compose logs
docker compose -f /opt/garuda/firezone/docker-compose.yml logs -f

# API health
curl -s http://localhost:<firezone-port>/api/health
```

## RouterOS DHCP drift

RouterOS's DHCP client can rewrite `default-route-tables`, breaking the WireGuard
endpoint bypass route. The public repository does not currently ship a standalone
reconcile playbook; re-apply the `garuda/` unit so the RouterOS module refreshes
the bypass resources:

```bash
cd examples/mini-site/garuda
terragrunt apply
```

## Observability notes

- Docker log driver is `json-file`, `max-file=5`, `max-size=100m`, set by
  `roles/linux_host_prerequisites`.
- FRR state: use `vtysh -c '...'` inside the sidecar container.
- `ipt_server` logs to stdout.
- Backbone operator health: `127.0.0.1:8080/health` on the operator container.
