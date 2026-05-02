# FRR Injector

`frr_injector` owns discovery, intent parsing, rendering, and reconciliation of
managed FRR sidecars for backbone-scoped workloads.

## Problem It Solves

Backbone workloads need FRR sidecars for OSPF participation and transit-related
routing behavior, but those sidecars must be derived from live Docker state.

The package exists to answer four questions consistently:

1. which containers are eligible for a managed FRR sidecar
2. what FRR intent they declared through labels
3. what sidecar should exist for that workload right now
4. whether an existing sidecar must be created, replaced, or removed

Without `frr_injector`, FRR sidecar lifecycle and FRR config ownership would be
split across templates, ad-hoc scripts, and container-local state.

## What It Does

`frr_injector` is the FRR-specific consumer plugged into the generic
`sidecar_operator` runtime.

Its responsibilities are:

- match backbone-attached containers in the correct operator scope
- parse FRR OSPF labels into `OspfConfig`
- parse transit labels into `TransitConfig`
- render `frr.conf`, `daemons`, and `vtysh.conf`
- build desired sidecar specs with the correct labels and env payloads
- validate target interface declarations against live container interfaces
- participate in create/replace/remove reconciliation through the shared
  sidecar operator loop

It does not own shared Docker transport networks. That bootstrap concern belongs
to `network_manager`.

## Runtime Contract

### Eligibility

A workload is considered by `FRRConsumer.matches_target()` only if all of these
are true:

- `garuda.operator-scope` matches the configured operator scope
- the container is not already a managed sidecar
- the container is attached to `backbone_network`
- the backbone attachment has a valid IPv4 address
- the container is not the operator itself

After that, FRR label validation decides whether a sidecar should actually be
rendered.

### Intent model

`frr_injector` uses two label-driven models.

`OspfConfig` owns `garuda.frr.ospf.*` and `garuda.frr.extra_b64`:

- compact mode for structured OSPF intent
- raw mode for advanced FRR bodies via `garuda.frr.extra_b64`

`TransitConfig` owns `garuda.transit.*`:

- `garuda.transit.provider=true` marks a workload as the transit provider
- `garuda.transit.interfaces=<csv>` marks a workload as a transit consumer and
  declares ingress interfaces that should be steered into the transit table

These models are the single source of truth for label parsing and validation.

### Rendering contract

`FRRConsumer.build_desired_sidecar()` is the production rendering path.

It produces:

- `FRR_CONF_B64`
- `DAEMONS_B64`
- `VTYSH_CONF_B64`
- `BACKBONE_IP`
- transit watcher env when transit consumer/provider labels require it

Transit routing is split intentionally:

- FRR config renders the control-plane intent
- `transit_watcher.py` in the sidecar owns consumer kernel route and `ip rule`
  reconciliation at runtime

### Reconciliation boundary

The package participates in the generic sidecar reconcile loop but owns FRR-
specific decisions. In practice that means:

- `discovery.py` filters eligible targets and derives minimal desired metadata
- `reconcile.py` computes create/replace/remove actions
- `runtime.py` executes those actions and re-renders env from the live target
  container just before create/replace

This keeps labels and runtime state aligned with the actual container that
exists now, not with stale metadata from a previous pass.

## Who Uses It

`frr_injector` is used by the operator entrypoint in
`roles/backbone_network/files/ospf_injector/frr_injector/main.py`.

The startup sequence is:

1. load `InjectorConfig`
2. ensure shared networks through `network_manager`
3. mark operator health ready
4. create `SidecarOperator`
5. register `FRRConsumer`
6. run the reconcile loop

So `frr_injector` is the FRR-specific part of the operator, while
`sidecar_operator` provides the generic reconcile framework.

## Relationship To Other Docs

- [OSPF injector package overview](../README.md)
- [Transit path and transit consumer concept](transit.md)
- [FRR injector refactor design](../../../../../docs/superpowers/specs/2026-04-06-frr-injector-refactor-design.md)
- [Operator network manager design](../../../../../docs/superpowers/specs/2026-04-08-operator-network-manager-design.md)
- [FRR sidecar runtime contract](../../frr_sidecar/README.md)

## Key Code Entry Points

- [FRR consumer](consumer.py)
- [FRR injector entrypoint](main.py)
- [Transit label model](transit_config.py)
- [OSPF label model](ospf_config.py)

Those documents explain the broader architecture and change history. This README
documents the current responsibility and runtime contract of the `frr_injector`
package.

## Transit routing

A *transit provider* is a workload with external (internet) egress that
advertises a default route into the backbone OSPF domain marked with a
route tag. *Transit consumers* route selected client-facing traffic to
the provider via Linux policy-based routing (PBR), managed by the
watcher process that runs inside every FRR sidecar.

### Provider identification

Label on the target container: `garuda.transit.provider=true`.

`FRRConsumer.build_desired_sidecar` sets `transit_provider=True` on the
`OspfConfig` instance, which causes the Jinja OSPF template to render:

```frr
route-map TRANSIT-DEFAULT-TAG permit 10
 set tag 201

router ospf
 ...
 default-information originate always metric 10 metric-type 2 route-map TRANSIT-DEFAULT-TAG
```

`TRANSIT_TAG`, `TRANSIT_ROUTE_MAP`, `TRANSIT_METRIC`, and
`TRANSIT_METRIC_TYPE` are defined once in `frr_injector/config.py` and
propagated to the Jinja env as globals; provider and consumer sides
share this SSOT.

### Consumer identification

Label on the target container:
`garuda.transit.interfaces=<comma,separated,iface,list>`.

For a consumer, the injector emits two environment variables into the
sidecar:

- `PBR_TRANSIT_TAG` (the tag to match in OSPF External LSAs)
- `PBR_TRANSIT_INTERFACES` (the ingress interfaces whose traffic routes
  via the transit table)

`transit_watcher.py` (in the sidecar) then polls FRR:

1. `show ip ospf database external json` — find LSAs with matching tag.
2. `show ip ospf neighbor json` — resolve each advertising router to
   its backbone interface address (the nexthop).
3. Reconciles kernel state via pyroute2:
   - Default route in routing table 201 pointing at the resolved
     nexthop(s).
   - `ip rule iif <listed interface> lookup 201` for each configured
     interface.

The watcher runs on a polling interval (default 5s, configurable via
`POLL_INTERVAL`) and is tolerant of transient FRR unavailability during
startup.

### Mutual exclusion

A workload cannot be both provider and consumer simultaneously. This is
enforced by `TransitConfig._validate_mutual_exclusion` in
`frr_injector/transit_config.py`: if both `garuda.transit.provider` and
`garuda.transit.interfaces` are present on the same container, sidecar
construction aborts for that target.

### FRR does not render PBR

`render_frr_conf` intentionally does not render any `pbr-map` / `set
table` block. FRR 10.6 does not support `set table` in `pbr-map`, so
transit PBR routing is delegated entirely to `transit_watcher.py` via
pyroute2. See the background in `transit.md` for the full design
history.
