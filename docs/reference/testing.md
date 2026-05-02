# Testing Reference

## Testing layers

| Layer           | Tool                           | What it covers                                        |
|-----------------|--------------------------------|-------------------------------------------------------|
| Module contract | `tofu test` / `terraform test` | Variable validation, output shape, mock provider runs |
| Operator unit   | `pytest`                       | Python operator packages (frr_injector, network_manager, sidecar_operator, ipt_server) |
| Live smoke      | `ansible-playbook z2g.yml`     | End-to-end network reachability after apply           |

## Module tests (tofu test)

Each module that uses mock providers has a `.tftest.hcl` file under `modules/*/tests/`.

```bash
# Run all module contract tests
tofu -chdir=modules/linux_apply test
tofu -chdir=modules/ipt_server test
tofu -chdir=modules/wireguard/tunnel test
tofu -chdir=modules/wireguard/linux test
tofu -chdir=modules/wireguard/routeros test
tofu -chdir=modules/firezone test
tofu -chdir=modules/yc_compute_host test
tofu -chdir=modules/gcp_compute_host test
```

Module tests use mock providers so they do not require cloud credentials or live
infrastructure. They verify:

- Variable validation rules (e.g. `env_slug` format, `pinning_egress` key format,
  `connection_data` mutual exclusion).
- Output shapes (e.g. `wireguard/tunnel` emits `tunnel_name` and `kernel_ifname`).

## Operator unit tests (pytest)

Python packages under `roles/backbone_network/files/ospf_injector/` and
`roles/ipt_server/files/ipt-server/` are tested with pytest.

```bash
pytest tests/
```

Key test files:

| File                                          | Covers                                                  |
|-----------------------------------------------|---------------------------------------------------------|
| `tests/test_frr_injector_contracts.py`        | Label parsing and FRR config rendering                  |
| `tests/test_frr_injector_rendering.py`        | frr.conf output rendering                               |
| `tests/test_sidecar_operator_reconcile.py`    | Create / replace / remove reconcile loop                |
| `tests/test_sidecar_operator_runtime.py`      | Sidecar runtime lifecycle                               |
| `tests/test_network_manager_docker_api.py`    | Docker network creation                                 |
| `tests/test_network_manager_sysctl.py`        | sysctl application                                      |
| `tests/test_ipt_server_route_semantics.py`    | Route type inference (CIDR / country / domain)          |
| `tests/test_ipt_server_delivery_contracts.py` | ipt_server payload contract                             |
| `tests/test_backbone_border_network_contracts.py` | Shared network ownership and masquerade rules       |
| `tests/test_wireguard_env_flat_payload_contract.py` | WireGuard payload shape                           |
| `tests/test_transit_constants.py`             | Transit LSA tag constants                               |

## Live smoke tests

Live smoke tests require a deployed environment. The public reference playbook
path is `examples/mini-site/smoke/z2g.yml` once that playbook is wired. Until
then, `examples/mini-site/smoke/README.md` documents the expected entrypoint.

See [smoke testing runbook](../operations/smoke-testing.md).

## Running all non-live tests

```bash
pytest tests/
tofu -chdir=modules/linux_apply test
tofu -chdir=modules/ipt_server test
tofu -chdir=modules/wireguard/tunnel test
tofu -chdir=modules/wireguard/linux test
tofu -chdir=modules/wireguard/routeros test
tofu -chdir=modules/firezone test
tofu -chdir=modules/yc_compute_host test
tofu -chdir=modules/gcp_compute_host test
```
