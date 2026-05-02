# How to Define a Routing Policy

This guide shows how to edit `routes` and `pinning_egress` on `modules/ipt_server`
to change where categories of traffic exit the mesh.

For the full schema, see [routing policy reference](../reference/routing-policy.md).

## Add a country rule

Route all traffic matching country `DE` through the USA edge:

```hcl
module "ipt_server_hub" {
  source = "../../modules/ipt_server"
  # ...
  routes = [
    {
      route = [{ gw = "192.0.2.2" }]   # usa edge WireGuard peer address
      rules = ["DE", ".*\\.de"]
    },
    {
      route = [{ dev = "border" }]      # local uplink
      rules = [".*", "0.0.0.0/0"]
    },
  ]
}
```

The first entry catches traffic for German domains and IPs and sends it through
the USA edge. The catch-all entry routes everything else locally. Rules are
evaluated in order; put specific rules before catch-all.

## Add a CIDR rule

Route a specific IP range through an egress:

```hcl
routes = [
  {
    route = [{ gw = "192.0.2.2" }]
    rules = ["203.0.113.0/24"]
  },
  # ... other rules ...
]
```

## Enable per-source egress pinning

Pinning assigns individual source clients to a specific egress for `pinning_ttl`
seconds. Add the egress to `pinning_egress`:

```hcl
pinning_egress = {
  usa = { gw = "192.0.2.2" }
}
pinning_ttl = 86400  # 24 hours
```

Key must match `^[a-z0-9_-]+$`. Value is `{ gw = "<ip>" }` or `{ dev = "<iface>" }`.

## Disable pinning

```hcl
pinning_egress = {}
```

## Apply the change

```bash
cd examples/mini-site/garuda
terragrunt apply
```

`ipt_server` will re-deploy with the new policy. Existing connections may briefly
use the old egress until conntrack entries expire.

## Further reading

- [Routing policy reference](../reference/routing-policy.md)
- [Routing model concept](../concepts/routing-model.md)
