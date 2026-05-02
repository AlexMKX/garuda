# Label Taxonomy

Garuda uses Docker container labels to carry both operator ownership markers and
FRR/PBR intent. The backbone operator (`frr_injector`) reads these labels to
discover workloads and reconcile FRR sidecars.

## Naming conventions

- **Top-level operator labels** use kebab-case:
  `garuda.managed-by`, `garuda.operator-scope`, `garuda.sidecar-consumer`,
  `garuda.target-container`, `garuda.sidecar-revision`.
- **Nested config namespaces** use dots:
  `garuda.frr.ospf.enabled`, `garuda.transit.provider`,
  `garuda.frr.ospf.interfaces`.

## Label reference

### Operator ownership

| Label                     | Values              | Purpose                                                        |
|---------------------------|---------------------|----------------------------------------------------------------|
| `garuda.managed-by`       | `ospf-injector`     | Marks a container as managed by the backbone operator          |
| `garuda.operator-scope`   | string              | Operator instance scope (prevents cross-stack interference)    |
| `garuda.sidecar-consumer` | `frr`               | Declares the container wants an FRR sidecar                    |
| `garuda.target-container` | container name      | Name of the workload container the sidecar attaches to         |
| `garuda.sidecar-revision` | hash/revision       | Forces sidecar replacement when FRR config changes             |

### OSPF configuration

| Label                             | Values            | Purpose                                                        |
|-----------------------------------|-------------------|----------------------------------------------------------------|
| `garuda.frr.ospf.enabled`         | `"true"`          | Enable OSPF on this workload                                   |
| `garuda.frr.ospf.router_id`       | IPv4 address      | Unique OSPF router ID for this workload                        |
| `garuda.frr.ospf.interfaces`      | comma-separated   | Additional interfaces beyond `backbone` to announce OSPF on   |
| `garuda.frr.ospf.active_interfaces` | comma-separated | Subset of interfaces where OSPF is active; empty means passive |
| `garuda.frr.ospf.default_originate` | `"true"`        | Originate a default route as OSPF External LSA                 |
| `garuda.frr.ospf.redistribute`    | comma-separated   | FRR redistribution sources, for example `kernel`               |

### Transit routing

| Label                        | Values      | Purpose                                                             |
|------------------------------|-------------|---------------------------------------------------------------------|
| `garuda.transit.provider`    | `"true"`    | Marks this workload as a transit route provider (`ipt_server`)      |
| `garuda.transit.interfaces`  | comma-sep   | Interfaces that use the dynamically learned transit default route   |

### Backbone attachment

| Label                  | Values  | Purpose                                              |
|------------------------|---------|------------------------------------------------------|
| `garuda.backbone-ipv4` | IPv4    | Backbone network IP of this container                |

## Minimal label sets by workload type

### WireGuard Linux egress peer

```yaml
garuda.frr.ospf.enabled: "true"
garuda.frr.ospf.router_id: "192.0.2.11"
garuda.frr.ospf.interfaces: "wg-edge"
garuda.frr.ospf.default_originate: "true"
```

### Firezone (transit consumer)

```yaml
garuda.frr.ospf.enabled: "true"
garuda.frr.ospf.router_id: "192.0.2.20"
garuda.frr.ospf.interfaces: "wg-firezone"
garuda.transit.interfaces: "wg-firezone"
```

### ipt_server (transit provider)

```yaml
garuda.frr.ospf.enabled: "true"
garuda.frr.ospf.router_id: "192.0.2.30"
garuda.frr.ospf.interfaces: "backbone"
garuda.frr.ospf.active_interfaces: "backbone"
garuda.frr.ospf.default_originate: "true"
garuda.frr.ospf.redistribute: "kernel"
garuda.transit.provider: "true"
```

The `ipt_server` role also merges its role-owned invariants at render time. The
caller must supply at least `garuda.frr.ospf.router_id`; include the full set
above when documenting or testing the rendered runtime labels.

### Custom workload (backbone only, no OSPF)

```yaml
garuda.managed-by: "ospf-injector"
garuda.operator-scope: "example.net"
```

## Full label contract

For the complete label parsing and rendering specification, see the backbone
operator documentation:

- [OSPF injector README](../../roles/backbone_network/files/ospf_injector/README.md)
- [FRR injector runtime contract](../../roles/backbone_network/files/ospf_injector/frr_injector/README.md)
