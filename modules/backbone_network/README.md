# backbone_network

Workload module that creates a shared Docker bridge network (`backbone_network`) on a Linux host. This network serves as the single-host transit underlay between per-stack FRR router containers.

The module renders an Ansible workload payload for `roles/backbone_network`, which deploys an empty Docker Compose stack that owns only the named bridge network. All dependent workload stacks reference this network as `external: true`.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | string | required | Stable workload identifier |
| `host_name` | string | required | Inventory host |
| `backbone_dir` | string | `/opt/garuda/backbone` | Stack directory on host |
| `backbone_subnet` | string | required | CIDR for the bridge |
