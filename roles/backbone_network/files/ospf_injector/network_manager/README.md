# Network Manager

`network_manager` owns shared Docker transport networks that must exist before
the rest of the operator-managed workloads can start.

## Problem It Solves

The shared transport networks are host-scoped infrastructure, but Docker Compose
validates `external: true` networks before it starts any service. If network
creation is left to a consumer stack, the system falls into a bootstrap
deadlock: workloads need the network to start, but the component that would
create the network never gets a chance to run.

`network_manager` fixes that ownership boundary.

It makes one component responsible for:

- creating the shared Docker bridge networks when they are absent
- validating existing networks against the expected contract
- applying bridge-owned host sysctl state such as `proxy_arp`

## What It Does

`NetworkManager.ensure_all()` receives a normalized list of `ManagedNetwork`
specs and reconciles them one by one.

For each network it:

1. checks whether the Docker network already exists
2. creates it if it is missing
3. validates driver, subnet, and bridge-name contract if it already exists
4. applies host-side `proxy_arp` when the network spec declares it

This module is deliberately small. It does not manage containers, sidecars, FRR
configuration, or generic host sysctl beyond the network-owned bridge setting.

## Runtime Contract

### Input model

The runtime consumes `ManagedNetwork` objects with these fields:

- `name` — Docker network name
- `cidr` — expected Docker IPAM subnet
- `bridge_name` — optional host bridge interface name
- `proxy_arp` — optional bridge-level host sysctl value (`0`, `1`, or `None`)

Defaults are owned by `network_manager.models.DEFAULT_MANAGED_NETWORKS`:

- `backbone_network`
- `border_network`

Operator-level overrides are merged in `InjectorConfig`, so runtime code always
receives an already-normalized network list.

### Validation and fail-fast behavior

If a managed network already exists, `network_manager` does not silently mutate
or recreate it. Instead, it validates the observed Docker state and fails fast
on contract mismatch.

Examples of fatal mismatch:

- wrong Docker driver
- wrong subnet
- wrong or missing `com.docker.network.bridge.name` when `bridge_name` is owned

This is intentional. A shared transport network is foundational infrastructure,
so silently accepting the wrong network would corrupt every dependent workload.

### Host sysctl ownership

When `proxy_arp` is declared, `HostSysctlRunner` enters the host network
namespace through `nsenter --net=/proc/1/ns/net` and writes directly to the
bridge procfs path.

This is needed because the operator runs with `network_mode: none` and still has
to tune a host bridge created by Docker.

## Who Uses It

`network_manager` is not a standalone daemon. It is a bootstrap component used
by `frr_injector.main` before the sidecar reconciliation loop starts.

Sequence:

1. operator health endpoint starts in not-ready state
2. `NetworkManager.ensure_all(config.networks)` ensures shared networks
3. health flips to ready
4. the sidecar operator loop starts reconciling FRR sidecars

That ordering is the key contract: shared networks must exist before any
downstream workload compose stack or sidecar reconcile depends on them.

## Relationship To Other Docs

- [Operator network manager design](../../../../../docs/superpowers/specs/2026-04-08-operator-network-manager-design.md)
- [OSPF injector package overview](../README.md)

## Key Code Entry Points

- [Network manager runtime](runtime.py)
- [Managed network model](models.py)
- [Docker network API helpers](docker_api.py)
- [Host sysctl runner](sysctl.py)

Those documents explain the design history. This README documents what
`network_manager` owns in the current runtime.
