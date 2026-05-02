# Transit Path And Transit Consumers

This document explains the business meaning of transit routing in `garuda`.

Use it when you need to understand:

- what a transit consumer is
- what a transit path is
- why `ipt_server` is treated as a transit provider
- why `transit_watcher.py` exists
- how the `garuda.transit.*` labels map to runtime behavior

This document is specific to FRR transit behavior, so it lives next to the
[`frr_injector`](README.md) package that owns the transit label contract.

## Core Idea

In this project, some workloads receive client or tunnel traffic but should not
make the final egress decision themselves.

Instead, they forward that traffic to `ipt_server`, which acts as the central
transit decision point.

`ipt_server` then applies the project-specific policy:

- DNS interception
- geo-routing
- choice of direct exit via `border`
- choice of tunnel exit via a Linux egress peer such as `wg-edge`

So transit routing is not just "send traffic to the internet". It is "send
traffic to the workload that owns the project's egress policy".

## Definitions

### Transit provider

The transit provider is the workload that advertises "send transit traffic to
me".

In the current reference topology, that workload is `ipt_server`.

It is marked with:

```text
garuda.transit.provider=true
```

This label means:

- the workload advertises a tagged OSPF default route
- the workload is the next transit hop for consumers
- the workload owns the business policy for further routing decisions

Example provider label set (from a Garuda topology main.tf):

```hcl
labels = {
  "garuda.operator-scope"             = "backbone_network"
  "garuda.frr.ospf.enabled"           = "true"
  "garuda.frr.ospf.router_id"         = local.workload_facts.ipt_server.frr_router_id
  "garuda.frr.ospf.interfaces"        = "backbone"
  "garuda.frr.ospf.active_interfaces" = "backbone"
  "garuda.frr.ospf.default_originate" = "true"
  "garuda.frr.ospf.redistribute"      = "kernel"
  "garuda.transit.provider"           = "true"
}
```

### Transit consumer

A transit consumer is a workload that receives traffic on one or more ingress
interfaces and must forward that traffic to the transit provider.

It is marked with:

```text
garuda.transit.interfaces=<csv>
```

This label means:

- traffic entering those interfaces should be transit-steered
- the FRR sidecar should run `transit_watcher.py`
- the sidecar should maintain a transit routing table pointing at the current
  transit provider

In the current reference topology, the consumers are:

- `firezone` with `garuda.transit.interfaces=wg-firezone`
- a RouterOS-facing WireGuard peer with `garuda.transit.interfaces=wg-ros`

Example consumer label sets:

```hcl
firezone = {
  labels = {
    "garuda.frr.ospf.enabled"           = "true"
    "garuda.frr.ospf.router_id"         = "192.0.2.20"
    "garuda.frr.ospf.interfaces"        = "wg-firezone"
    "garuda.frr.ospf.active_interfaces" = ""
    "garuda.frr.ospf.default_originate" = "false"
    "garuda.transit.interfaces"         = "wg-firezone"
  }
}

wg_ros = {
  labels = {
    hub = {
      "garuda.frr.ospf.enabled"           = "true"
      "garuda.frr.ospf.router_id"         = "192.0.2.11"
      "garuda.frr.ospf.interfaces"        = "wg-ros"
      "garuda.frr.ospf.active_interfaces" = "wg-ros"
      "garuda.frr.ospf.default_originate" = "false"
      "garuda.transit.interfaces"         = "wg-ros"
    }
  }
}
```

### Transit path

The transit path is the path from a transit consumer to the transit provider.

In this project, that path is usually:

1. traffic enters a consumer on a client-facing or tunnel-facing interface
2. policy routing in the consumer sends that traffic into the transit table
3. the transit table points to `ipt_server` over `backbone_network`
4. `ipt_server` decides the final egress path

That means the transit path is not the final internet path.

It is the path to the workload that owns the project's egress policy.

## Why The Project Needs This Split

Without the transit concept, every ingress workload would have to duplicate the
same routing policy:

- know who currently provides transit
- know the provider IP
- decide direct exit versus tunnel exit
- react when OSPF reconverges

That would spread policy across multiple independent workloads.

Instead, the project centralizes the business decision in `ipt_server`:

- consumers only need to know how to reach the provider
- `ipt_server` owns the policy for what happens next

This gives a cleaner separation:

- consumer: "this traffic must go to the transit policy node"
- provider: "I decide where this traffic leaves the system"

## Reference Topology

In the reference topology (`examples/mini-site`):

- `firezone` is attached to `backbone_network` (consumer).
- A RouterOS-facing WireGuard peer is attached to `backbone_network` (consumer).
- `ipt_server` is attached to both `backbone_network` and `border_network` (provider).
- Edge WireGuard peers are attached to `backbone_network` and `border_network`.

This matters because:

- consumers sit on `backbone_network`
- the transit provider sits on `backbone_network` so consumers can reach it
- the transit provider also sits on `border_network` so it can choose direct
  egress when policy says so

## Topology Diagram

```mermaid
flowchart LR
    Client1[Firezone Client] --> Firezone[firezone\nconsumer]
    Client2[RouterOS / wg-ros traffic] --> WgRos[wg-ros\nconsumer]

    Firezone -->|transit path over backbone| Ipt[ipt_server\ntransit provider]
    WgRos -->|transit path over backbone| Ipt

    Ipt -->|direct egress| Border[border network]
    Ipt -->|tunnel egress| WgEdge[wg-edge exit node]
    WgEdge --> Internet[Internet / upstream]
    Border --> Internet
```

## Control Plane And Data Plane

The control plane decides who the provider is.
The data plane forwards traffic to that provider.

```mermaid
sequenceDiagram
    participant C as Transit consumer sidecar
    participant O as OSPF LSDB
    participant W as transit_watcher.py
    participant P as ipt_server provider

    O->>W: Tagged default route from provider
    W->>W: Resolve provider backbone IP
    W->>C: Reconcile table 10000 default route
    C->>P: Forward transit traffic over backbone
    P->>P: Apply DNS and geo-routing policy
    P->>Internet: Send traffic via border or wg-edge
```

## What `transit_watcher.py` Actually Does

`transit_watcher.py` does not choose the final exit path.

It only keeps the consumer's runtime forwarding aligned with the current
provider selected by the control plane.

Its job is:

1. read OSPF external LSAs with the configured transit tag
2. resolve the advertising router into a reachable backbone IP
3. reconcile the consumer-side transit routing table
4. add or remove `ip rule` entries for the declared transit interfaces

Business meaning:

- if OSPF reconverges and the provider next hop changes, the consumer should
  still send traffic to the current transit provider without restart
- if no provider is currently reachable, the transit-specific steering should be
  withdrawn rather than pointing to stale state

## What `transit_watcher.py` Does Not Do

`transit_watcher.py` is not responsible for:

- deciding whether traffic should leave via `border` or an egress peer such as `wg-edge`
- implementing DNS interception
- implementing geo-routing policies
- creating Docker networks
- rendering FRR intent from labels

Those responsibilities belong elsewhere:

- final egress decision: [ipt_server](../../../../ipt_server/files/ipt-server/readme.md)
- transit label parsing and env delivery: [FRR injector](README.md)
- consumer-side route and `ip rule` reconcile: [transit watcher](../../frr_sidecar/transit_watcher.py)
- shared network ownership: [Network Manager](../network_manager/README.md)

## Configuration Examples

### Provider example: `ipt_server`

Use `garuda.transit.provider=true` when a workload should advertise itself as the
project's transit decision point.

```hcl
module "ipt_server_hub" {
  source = "../../modules/ipt_server"

  name           = "ipt_server"
  host_name      = "hub"
  ipt_server_dir = "/opt/garuda/ipt_server"
  nic_attach     = ["backbone", "border"]
  connection_data = var.connection_data_hub
  routes         = var.routes

  labels = {
    "garuda.operator-scope"             = var.base_domain
    "garuda.frr.ospf.enabled"           = "true"
    "garuda.frr.ospf.router_id"         = "192.0.2.30"
    "garuda.frr.ospf.interfaces"        = "backbone"
    "garuda.frr.ospf.active_interfaces" = "backbone"
    "garuda.frr.ospf.default_originate" = "true"
    "garuda.frr.ospf.redistribute"      = "kernel"
    "garuda.transit.provider"           = "true"
  }

  depends_on = [module.backbone_network["hub"]]
}
```

Why:

- `ipt_server` must be reachable from all transit consumers over `backbone`
- it must also be able to exit via `border` or tunnel out via an egress peer
- it advertises the tagged OSPF default that consumers track

### Consumer example: `firezone`

Use `garuda.transit.interfaces=wg-firezone` when traffic entering `wg-firezone`
must be handed to the transit provider.

```hcl
module "firezone_hub" {
  source = "../../modules/firezone"

  host_name       = "hub"
  connection_data = var.connection_data_hub

  labels = {
    "garuda.frr.ospf.enabled"           = "true"
    "garuda.frr.ospf.router_id"         = "192.0.2.20"
    "garuda.frr.ospf.interfaces"        = "wg-firezone"
    "garuda.frr.ospf.active_interfaces" = ""
    "garuda.frr.ospf.default_originate" = "false"
    "garuda.transit.interfaces"         = "wg-firezone"
    "garuda.operator-scope"             = var.base_domain
  }

  depends_on = [module.backbone_network["hub"]]
}
```

Why:

- Firezone receives client traffic on `wg-firezone`
- that traffic should not be locally egressed by Firezone
- it should be handed to `ipt_server`, which owns DNS and geo-routing policy

### Consumer example: RouterOS-facing WireGuard peer

Use `garuda.transit.interfaces=wg-ros` when traffic entering the
RouterOS tunnel must be handed to the transit provider.

```hcl
module "wireguard_linux_ros_hub" {
  # ...
  labels = {
    "garuda.frr.ospf.enabled"           = "true"
    "garuda.frr.ospf.router_id"         = "192.0.2.11"
    "garuda.frr.ospf.interfaces"        = "wg-ros"
    "garuda.frr.ospf.active_interfaces" = "wg-ros"
    "garuda.frr.ospf.default_originate" = "false"
    "garuda.transit.interfaces"         = "wg-ros"
    "garuda.operator-scope"             = "example.net"
  }
}
```

Why:

- The RouterOS-facing tunnel is an ingress point for branch LAN traffic.
- It should forward transit traffic to `ipt_server` instead of owning duplicate
  egress policy locally.

## Runtime Verification

The expected runtime contract:

- consumer sidecar has an `ip rule` for the ingress interface.
- consumer sidecar has a `table 10000` default route via the provider's backbone IP.
- provider sidecar advertises a tagged type-5 OSPF external default LSA.

Verify:

```bash
# Consumer ip rule
docker exec <consumer-sidecar> ip rule show | grep 10000

# Consumer transit route
docker exec <consumer-sidecar> ip route show table 10000

# Provider OSPF external LSA
docker exec <provider-sidecar> vtysh -c 'show ip ospf database external'
```

See [troubleshooting](../../../../../docs/operations/troubleshooting.md) for more diagnostic commands.

## Summary

- transit consumer = ingress workload that forwards marked traffic to the
  transit provider
- transit provider = workload that owns project-specific egress policy
- transit path = consumer-to-provider path over `backbone_network`
- `ipt_server` is the current transit provider in the reference topology
- `firezone` and the RouterOS-facing WireGuard peer are current transit consumers
- `transit_watcher.py` keeps consumer runtime routing aligned with the current
  provider chosen by OSPF

## Key Code Entry Points

- [Transit label model](transit_config.py)
- [FRR consumer](consumer.py)
- [Transit watcher runtime](../../frr_sidecar/transit_watcher.py)
- [Reference topology](../../../../../docs/getting-started/reference-topology.md)
- [Module index](../../../../../docs/reference/modules.md)
