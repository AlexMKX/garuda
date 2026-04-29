# sidecar_operator

Generic lifecycle manager for Docker sidecar containers attached to workload targets.

## Overview

`sidecar_operator` is a reusable Python package that runs a continuous reconcile loop
over a set of sidecar containers. It discovers existing managed sidecars via Docker
labels, asks registered consumers what the desired state should be, computes a diff
(create / replace / remove), and applies the diff through the Docker SDK.

The package has no opinion about what the sidecar does — that is the consumer's
responsibility. Consumers implement the `SidecarOperatorConsumer` protocol and register
themselves with a `SidecarOperator` instance at startup.

## Architecture

```
SidecarOperator (runtime.py)
├── reconcile loop  ─────────────────────> ReconcilePlan (reconcile.py)
│   ├── list_managed_sidecars (docker_api.py)   # actual state from Docker labels
│   └── consumer.desired_sidecars()             # desired state from each consumer
├── event polling   ─────────────────────> wakes reconcile on Docker container events
└── signal handling ─────────────────────> SIGTERM / SIGINT / SIGHUP
```

### Modules

| Module | Responsibility |
|---|---|
| `models.py` | Shared data models: `DesiredSidecarSpec`, `ActualSidecarRef`, `SharedNamespaces`, `SidecarStopContext` |
| `reconcile.py` | `build_reconcile_plan` — pure diff computation, no side effects |
| `consumer_api.py` | `SidecarOperatorConsumer` Protocol — the interface consumers must implement |
| `docker_api.py` | Docker SDK helpers: discover, create, remove managed sidecars |
| `config.py` | `OperatorConfig` — runtime configuration (scope, interval, Docker socket) |
| `runtime.py` | `SidecarOperator` — main loop, signal handlers, hook orchestration |

## Consumer contract

A consumer must implement `SidecarOperatorConsumer` (see `consumer_api.py`):

- `consumer_name` — unique string identifying the consumer (used in labels and sidecar names).
- `matches_target(container)` — filter: return `True` for containers this consumer manages.
- `build_desired_sidecar(target, docker)` — produce a `DesiredSidecarSpec` for a target,
  or `None` to skip it.
- `on_reconcile(action, docker)` — called after create/replace; used for post-create
  configuration (e.g. writing config files into the sidecar).
- `before_sidecar_stopped(ctx, docker)` — advisory hook called before removal; always
  runs even on error, but removal proceeds unconditionally afterwards.

## Label contract

All managed sidecars carry these Docker labels:

| Label | Value |
|---|---|
| `garuda.managed-by` | `sidecar-operator` |
| `garuda.operator-scope` | operator scope (e.g. `backbone_network`) |
| `garuda.sidecar-consumer` | consumer name |
| `garuda.target-container` | target container name |
| `garuda.target-container-id` | target container ID at creation time |

## Usage

```python
from sidecar_operator import SidecarOperator, OperatorConfig

config = OperatorConfig(operator_scope="backbone_network", reconcile_interval=10.0)
operator = SidecarOperator(config=config)
operator.register(MyConsumer())
operator.run()  # blocks; handles SIGTERM/SIGINT/SIGHUP
```

## Testing

Tests live in `tests/` at the repository root (established project convention).
See `tests/test_sidecar_operator_reconcile.py` and
`tests/test_sidecar_operator_runtime.py`.

To run:

```bash
pytest tests/test_sidecar_operator_reconcile.py tests/test_sidecar_operator_runtime.py -v
```
