# Routing Policy Reference

This page documents the exact `routes` and `pinning_egress` schemas consumed by
`modules/ipt_server`.

## routes

`routes` is an ordered list of policy entries. Each entry groups a list of route
members with a list of match rules.

```hcl
routes = [
  {
    route = [{ gw = "192.0.2.2" }, { dev = "border" }]
    rules = [".*", "0.0.0.0/0"]
  },
  {
    route = [{ dev = "border" }]
    rules = ["RU", ".*\\.ru"]
  },
]
```

### route members

Each `route` entry is a list of `{ gw? | dev? }` objects:

| Field | Type   | Meaning                                            |
|-------|--------|----------------------------------------------------|
| `gw`  | string | Concrete next-hop IP (WireGuard peer address, etc.)|
| `dev` | string | Network interface name (e.g. `border`, `wg-edge`)  |

Exactly one of `gw` or `dev` must be set per member. Members are tried in order;
if the first is unreachable, the next is used (failover within one policy entry).

### rules

`rules` is a `list(string)`. `ipt_server` infers the rule type from the value:

| Pattern                    | Inferred type | Example            |
|----------------------------|--------------|--------------------|
| Valid CIDR                 | `net`        | `203.0.113.0/24`   |
| ISO 3166-1 alpha-2 code    | `country`    | `RU`, `DE`         |
| Anything else              | `domain`     | `.*\.ru`, `.*`     |

A bare `.*` regex matches all domains (catch-all). `0.0.0.0/0` matches all IPv4
CIDRs. Use both together for a true catch-all policy entry.

### Ordering

`routes` is evaluated in order. The first matching entry wins. Put catch-all
entries last.

## pinning_egress

`pinning_egress` assigns individual source clients to a specific egress for the
duration of `pinning_ttl` seconds. Each UI/API visit by a client refreshes the TTL
for that client's source IP.

```hcl
pinning_egress = {
  usa = { gw = "192.0.2.2" }
}
pinning_ttl = 86400
```

### pinning_egress shape

Keys are slug-style identifiers shown to end users:

- Must match `^[a-z0-9_-]+$`.
- `auto` is reserved and must not be used.

Each value is `{ gw = string }` or `{ dev = string }` — exactly one must be set.

### Disabling pinning

```hcl
pinning_egress = {}
```

An empty map disables the pinning subsystem entirely. `pinning_ttl` is ignored
when `pinning_egress` is empty.

### Default TTL

```hcl
pinning_ttl = 86400   # 24 hours
```

## Full variable source

Canonical source: [`modules/ipt_server/variables.tf`](../../modules/ipt_server/variables.tf).

## Related

- [How-to: define routing policy](../how-to/define-routing-policy.md)
- [Routing model concept](../concepts/routing-model.md)
