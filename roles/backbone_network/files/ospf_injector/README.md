# OSPF Injector Operator

This directory contains the operator package that manages shared backbone
transport prerequisites and FRR sidecars for backbone-scoped workloads.

This README is intentionally overview-only. Detailed runtime contracts live in
the package-local README files closer to the code that implements them.

## Package Map

### `network_manager/`

Owns shared Docker transport networks and bridge-owned host sysctl state.

Use this package when you need to understand:

- who creates `backbone_network` and `border_network`
- who validates existing Docker network contract
- who applies `proxy_arp` on the host bridge

Detailed doc:

- [Network Manager runtime contract](network_manager/README.md)

### `frr_injector/`

Owns FRR-specific target matching, label parsing, rendering, and sidecar
reconciliation logic.

Use this package when you need to understand:

- which workloads get FRR sidecars
- how FRR intent is parsed from labels
- how `frr.conf` and sidecar env payloads are rendered
- how create/replace/remove decisions are executed for FRR sidecars

Detailed doc:

- [FRR Injector runtime contract](frr_injector/README.md)

### `sidecar_operator/`

Owns the generic sidecar reconcile framework used by `frr_injector`.

Use this package when you need to understand:

- the generic create/replace/remove loop
- consumer registration and shared lifecycle hooks
- the Docker-label-based managed sidecar ownership model

Detailed doc:

- [Sidecar Operator runtime contract](sidecar_operator/README.md)

## Startup Flow

At runtime the operator starts in this order:

1. load `InjectorConfig`
2. start the local health endpoint in not-ready state
3. run `network_manager` bootstrap for shared transport networks
4. mark the health endpoint ready
5. start the generic `sidecar_operator` loop with `FRRConsumer` registered

That ordering matters:

- `network_manager` owns host-scoped transport prerequisites
- `frr_injector` owns FRR sidecar lifecycle after those prerequisites exist

## Ownership Boundaries

- shared Docker networks and bridge sysctl: `network_manager`
- FRR intent, rendering, and FRR sidecar reconcile: `frr_injector`
- generic sidecar framework behavior: `sidecar_operator`
- consumer kernel transit route/ip-rule reconcile inside the sidecar:
  [FRR sidecar runtime contract](../frr_sidecar/README.md)

## Related Design Docs

- [FRR injector refactor design](../../../../docs/superpowers/specs/2026-04-06-frr-injector-refactor-design.md)
- [Operator network manager design](../../../../docs/superpowers/specs/2026-04-08-operator-network-manager-design.md)
- [Dynamic PBR transit watcher design](../../../../docs/superpowers/specs/2026-04-06-dynamic-pbr-transit-watcher-design.md)

Read those documents for design history. Read the package-local README files for
the current operational contract.

## Label naming convention

- **Top-level operator labels** use kebab-case: `garuda.managed-by`, `garuda.operator-scope`,
  `garuda.sidecar-consumer`, `garuda.target-container`, `garuda.sidecar-revision`.
- **Nested config namespaces** use dots: `garuda.frr.ospf.enabled`, `garuda.transit.provider`.

The split is intentional: kebab for flat operator identifiers, dots for hierarchical config.
