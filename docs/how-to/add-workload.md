# How to Add a Workload

This guide shows the minimal path to add a new Garuda workload: an Ansible role,
a Terraform wrapper, Docker labels, and same-host backbone dependency.

## Overview

Garuda workloads follow the same pattern regardless of what they do:

1. An Ansible role with `provision` and `destroy` entrypoints.
2. A Terraform module wrapper around `modules/linux_apply`.
3. Docker labels on the compose service for backbone operator discovery.
4. `depends_on = [module.backbone_network["<host>"]]` in the call site.

## Step 1: Write the Ansible role

Create a role under `roles/<your-role>/`:

```
roles/my-workload/
  meta/
    argument_specs.yml   # provision and destroy entrypoints
  tasks/
    provision.yml
    destroy.yml
  templates/
    docker-compose.yml.j2
  defaults/
    main.yml
```

Define entrypoints in `meta/argument_specs.yml`:

```yaml
argument_specs:
  provision:
    short_description: Deploy my-workload on a Linux host.
    options:
      my_workload_dir:
        type: str
        required: true
      my_workload_labels:
        type: dict
        required: true
  destroy:
    short_description: Remove my-workload from a Linux host.
    options:
      my_workload_dir:
        type: str
        required: true
```

The role renders a Docker Compose file from `my_workload_labels` and runs
`docker compose up --wait` in `provision.yml`, and `docker compose down` in
`destroy.yml`.

## Step 2: Add Docker labels to the compose service

Labels carry FRR and operator intent. Minimum required:

```yaml
services:
  my-workload:
    labels:
      garuda.managed-by: ospf-injector
      garuda.operator-scope: "{{ my_operator_scope }}"
      garuda.frr.ospf.enabled: "true"
      garuda.frr.ospf.router_id: "{{ my_router_id }}"
```

For a transit-consuming workload (one that should route user traffic through
`ipt_server`), add:

```yaml
      garuda.transit.interfaces: "my-interface"
```

Full label reference: [labels](../reference/labels.md).

## Step 3: Write the Terraform module wrapper

Create `modules/my_workload/`:

```hcl
# modules/my_workload/main.tf
module "apply" {
  source       = "../linux_apply"
  host_name    = var.host_name
  workload_kind = "my_workload"
  connection_data = var.connection_data
  payload = {
    my_workload_dir    = var.my_workload_dir
    my_workload_labels = var.labels
  }
}
```

The `workload_kind` string must match the role name expected by the shared
`playbooks/apply.yml` dispatcher.

## Step 4: Wire the call site with correct depends_on

In your `garuda/main.tf`:

```hcl
module "my_workload_hub" {
  source          = "../../modules/my_workload"
  host_name       = "hub"
  my_workload_dir = "/opt/garuda/my-workload"
  connection_data = var.connection_data_hub
  labels          = {
    "garuda.managed-by"          = "ospf-injector"
    "garuda.operator-scope"      = var.base_domain
    "garuda.frr.ospf.enabled"    = "true"
    "garuda.frr.ospf.router_id"  = "192.0.2.99"
  }
  depends_on = [module.backbone_network["hub"]]
}
```

`depends_on` must reference only the same-host backbone module. Do not add
cross-host dependencies. See [module execution model](../reference/module-execution-model.md).

## Step 5: Apply

```bash
cd examples/mini-site/garuda
terragrunt apply
```

The backbone operator discovers the new container by labels and attaches an FRR
sidecar if `garuda.frr.ospf.enabled = "true"`.

## Further reading

- [Module execution model](../reference/module-execution-model.md)
- [Label taxonomy](../reference/labels.md)
- [`modules/linux_apply` README](../../modules/linux_apply/README.md)
