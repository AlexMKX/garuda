# How to Add a Linux Egress

This guide shows how to add a new Linux egress peer to an existing Garuda deployment
by extending the `edges` map.

## Prerequisites

- A Linux VM with a public IP in the target geography.
- SSH access credentials for the new VM.
- The VM is reachable from the hub.

## Step 1: Add the edge to your inputs

In your `inputs.tfvars.yaml`, add a new key under `edges`:

```yaml
edges:
  usa:
    fqdn_prefix: usa
    hub_cidr: 192.0.2.1/28
    peer_cidr: 192.0.2.2/28
    listen_port: 51820
    ospf_router_id_hub: 192.0.2.10
    ospf_router_id_peer: 192.0.2.11
  eur:                          # new edge
    fqdn_prefix: eur
    hub_cidr: 192.0.2.17/28
    peer_cidr: 192.0.2.18/28
    listen_port: 51820
    ospf_router_id_hub: 192.0.2.26
    ospf_router_id_peer: 192.0.2.27
```

Choose tunnel CIDRs that do not overlap with existing edges, `backbone_network`
(typically `172.30.0.0/24`), or `border_network` (typically `172.29.0.0/24`).

Choose unique OSPF router IDs for the new edge's hub-side and peer-side FRR speakers.

## Step 2: Add infra for the new VM

In your `infra/` unit, provision a compute module for the new edge. Use the same
`env_slug` as the rest of the stack:

```hcl
module "yc_compute_host_eur" {
  source   = "../../modules/yc_compute_host"
  env_slug = var.env_slug
  name     = "eur"
  # ... cloud-specific inputs ...
}
```

## Step 3: Apply infra

```bash
cd examples/mini-site/infra
terragrunt apply
```

## Step 4: Apply garuda

The `garuda/` unit's `for_each` over `edges` automatically creates:

- `wireguard/tunnel` for the new edge (key generation, per-peer config).
- `wireguard/linux` on the hub side.
- `wireguard/linux` on the edge side.
- backbone and prerequisites on the new edge host.

```bash
cd examples/mini-site/garuda
terragrunt apply
```

## Step 5: Add a routing rule for the new edge

In your `ipt_server` module, add a rule to route traffic through the new edge:

```hcl
routes = [
  {
    route = [{ gw = "192.0.2.18" }]   # eur edge peer address
    rules = ["DE", ".*\\.de"]
  },
  # ... existing rules ...
]
```

Apply garuda again to update `ipt_server`.

## Notes

- Each `edges` key must be unique within the stack.
- Do not reuse an existing edge key with a different CIDR — Terraform will destroy
  and recreate the tunnel, causing a brief outage.
- OSPF router IDs must be globally unique within the mesh.

## Further reading

- [Reference topology](../getting-started/reference-topology.md)
- [Define routing policy](define-routing-policy.md)
- [Module index](../reference/modules.md)
