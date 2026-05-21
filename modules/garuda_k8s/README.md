# garuda_k8s

Bootstraps one Kubernetes namespace with the shared transport plumbing
required by every Garuda edge workload: namespace, two
`NetworkAttachmentDefinition` resources (`backbone`, `border`), a network
metadata `ConfigMap`, and optionally the Multus and Whereabouts CNI
DaemonSets.

The module is a thin wrapper over `helm_release` rendering the bundled
chart at `${path.module}/charts/garuda`.

## Inputs

| Variable          | Default     | Description |
|-------------------|-------------|-------------|
| `namespace`       | `"garuda"`  | DNS-1123 label for the Kubernetes namespace. |
| `backbone_subnet` | (required)  | CIDR for the `backbone` NAD's Whereabouts IPAM, e.g. `10.42.0.0/24`. |
| `border_subnet`   | (required)  | CIDR for the `border` NAD's Whereabouts IPAM, e.g. `10.43.0.0/24`. |
| `install_cni`     | `true`      | When `true`, install Multus and Whereabouts from vendored manifests. Set `false` when CNI is pre-installed. |

## Outputs

| Output              | Description |
|---------------------|-------------|
| `namespace`         | Echo of `var.namespace`. Pass to `modules/wireguard/kube`. |
| `backbone_nad_name` | Static value `"backbone"`. |
| `border_nad_name`   | Static value `"border"`. |

## Providers

The module declares only `required_providers`. The caller must pass aliased
`helm` and `kubernetes` providers via the `providers` block:

```hcl
module "garuda_k8s_pt" {
  source = "../../../modules/garuda_k8s"
  providers = {
    helm       = helm.pt
    kubernetes = kubernetes.pt
  }
  backbone_subnet = "10.42.0.0/24"
  border_subnet   = "10.43.0.0/24"
}
```

## What this module does NOT do

- No workload pods. See `modules/wireguard/kube` for the WireGuard endpoint.
- No host CNI binaries install on the node — that is `modules/k3s_cloud_init`'s job. This module only installs the in-cluster Multus / Whereabouts DaemonSets.
- No `hostNetwork` for Garuda workload pods. The CNI DaemonSets installed when `install_cni = true` do use `hostNetwork` because that is how CNI plugin binaries are delivered to the kubelet; that exception is scoped to `kube-system` CNI installation, not application workloads.
- No kubeconfig fetch. Consumers fetch `/etc/rancher/k3s/k3s.yaml` over SSH and rewrite the apiserver `server:` URL to a local SSH forward — see the consumer Terragrunt unit's `before_hook` (the `examples/mini-site/garuda` consumer uses `garuda-tunnel` for this).
- No cluster-init / multi-node clustering. Each edge runs an independent single-node k3s server.
