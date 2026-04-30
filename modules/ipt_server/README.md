# ipt_server

Workload-centric Terraform module for the IPT policy gateway stack on one Linux host.

Why:

- `ipt_server` is the preferred transit/policy gateway for all client payload traffic
- owns FRR in its own namespace for OSPF participation in the backbone routing domain
- DNS interception and geo-routing live here, not distributed across ingress stacks

Inputs:

- `name` — stable workload identifier used for generated payload artifacts
- `host_name` — inventory host running the IPT stack
- `ipt_server_dir` — target directory for the IPT compose project
- `interfaces` (default `["backbone"]`) — network interfaces for PBR/input handling
- `routes` — ordered routing policy entries (list of `{route: [{gw?, dev?}], rules: [{net?, domain?, country?}]}`)
- `clean_conntrack` (default `true`) — clean conntrack state for managed flows
- `domain_route_ttl` (default `300`) — TTL in seconds for domain-derived routing entries
- `nic_attach` (default `[]`) — additional transport networks beyond backbone (which is mandatory and added by the role). Supported additional value: 'border'
- `connection_data` — normalized transport/auth contract for the target Linux host, passed to `linux_apply` unchanged
- `extra_hostvars` (default `{}`) — optional additional hostvars merged into module-local ansible_host variables
- `labels` (mandatory, non-empty) — Docker container labels; must include `garuda.frr.ospf.router_id`. Caller-supplied values override role-side garuda invariants in `combine`
- `pinning_egress` (default `{}`) — optional egress catalog for per-source-IP pinning; empty map disables the feature entirely
- `pinning_ttl` (default `86400`) — pin TTL in seconds; refreshed on each API/UI visit

Behavior:

- renders the IPT role payload expected by the shared executor
- applies and destroys the workload through `modules/linux_apply`
- FRR runs in the `ipt_server` network namespace via `network_mode: service:garuda_ipt`
- connects to `backbone_network` as `external: true`
- dataplane subnet `172.31.0.0/24` is hardcoded in the compose template (enforced by `tests/test_ipt_server_delivery_contracts.py`); it is not a module input

## Egress pinning

```hcl
module "ipt_server" {
  source = "..."
  pinning_egress = {
    hub = { gw = "192.0.2.1" }
    usa = { dev = "border" }
  }
  pinning_ttl = 86400  # default; can be omitted
}
```

`pinning_egress` is `map(object({ gw = optional(string), dev = optional(string) }))`.
An empty map (the default) disables the feature; no kernel writes, no HTTP listener.

Each entry must set exactly one of `gw` or `dev`. Keys must match the slug
pattern `^[a-z0-9_-]+$` and must not be `auto` (case-insensitive).
