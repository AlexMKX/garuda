# wireguard/kube

Deploys one WireGuard endpoint as a single-replica Kubernetes Deployment.
When `ospf` is set, an FRR sidecar runs in the same pod's network
namespace and speaks OSPF on the interfaces declared in `ospf.interfaces`.

This module mirrors the variable shape of `modules/wireguard/linux`. The
OSPF intent that used to be expressed via Docker labels read by
`ospf_injector` is expressed here as a structured `ospf` object input.

## Inputs

| Variable               | Required | Description |
|------------------------|----------|-------------|
| `namespace`            | yes      | Existing namespace, typically `module.garuda_k8s.namespace`. |
| `name`                 | yes      | Deployment name (DNS-1123), e.g. `wg-pt`. |
| `config`               | yes      | WireGuard local-peer config object: `kernel_ifname`, `private_key`, `address`, `subnet`, optional `listen_port`, optional `endpoint_host`. Sensitive. |
| `peer`                 | yes      | WireGuard remote-peer config object: `public_key`, `endpoint_host`, optional `preshared_key`, `address`. Sensitive. |
| `allowed_nets`         | yes      | List of `AllowedIPs` entries. |
| `table`                | no       | Default `"off"`. Same semantics as `modules/wireguard/linux`. |
| `persistent_keepalive` | no       | Default `25`. |
| `ospf`                 | no       | Structured OSPF intent. When `null`, no FRR sidecar is rendered. |
| `nic_attach`           | no       | Default `["backbone", "border"]`. Becomes the Multus annotation. |
| `wireguard_image`      | yes      | Image reference for the `wg` container. |
| `frr_image`            | when `ospf != null` | Image reference for the `frr-sidecar` container. |

### `ospf` object

| Field                | Required | Description |
|----------------------|----------|-------------|
| `router_id`          | yes      | IPv4-formatted OSPF router-id. |
| `area`               | no       | Default `"0.0.0.0"`. |
| `interfaces`         | yes      | Interfaces participating in OSPF; typically includes `config.kernel_ifname`. |
| `passive_interfaces` | no       | Marked `ip ospf passive`. |
| `default_originate`  | no       | Default `false`. |
| `redistribute`       | no       | Subset of `["connected", "kernel", "static"]`. |
| `extra_frr_conf`     | no       | Free-form FRR config appended verbatim. |

## Outputs

| Output            | Description |
|-------------------|-------------|
| `deployment_name` | Equals `var.name`. |

## Providers

```hcl
module "wireguard_kube_pt" {
  source = "../../../modules/wireguard/kube"
  providers = {
    helm       = helm.pt
    kubernetes = kubernetes.pt
  }
  namespace        = module.garuda_k8s_pt.namespace
  name             = "wg-pt"
  config           = local.wg_pt.config
  peer             = local.wg_pt.peer
  allowed_nets     = local.wg_pt.allowed_nets
  wireguard_image  = "ghcr.io/alexmkx/garuda-wireguard:latest"
  frr_image        = "ghcr.io/alexmkx/garuda-frr-sidecar:latest"
  ospf = {
    router_id  = "10.130.30.1"
    interfaces = ["wg-pt"]
  }
}
```

## What this module does NOT do

- No `hostNetwork`. The pod uses the pod network namespace and attaches
  `backbone`/`border` as Multus secondary interfaces.
- No Docker socket access, no `ospf_injector`. The FRR sidecar is rendered
  as a literal container in the same pod.
- No cluster-side CNI install. See `modules/garuda_k8s` for Multus and
  Whereabouts installation.
- No multi-replica scaling. WireGuard private state is single-instance by
  construction.
