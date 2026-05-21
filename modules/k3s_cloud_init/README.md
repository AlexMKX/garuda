# k3s_cloud_init

Pure render module: emits one cloud-config part that installs k3s on
first boot. No providers, no resources, no data sources.

## Output

| Output            | Description                                                       |
|-------------------|-------------------------------------------------------------------|
| `user_data_parts` | `list(string)` of length 1. Feed verbatim into compute-host's `user_data_parts`. |

## Inputs

| Variable             | Default               | Description                                                 |
|----------------------|-----------------------|-------------------------------------------------------------|
| `k3s_version`        | `null` (stable)       | k3s version pin, e.g. `v1.30.5+k3s1`. `null` = stable channel. |
| `install_url`        | `https://get.k3s.io`  | Base URL of the installer script. HTTPS only.               |
| `extra_flags`        | `[]`                  | Extra `--…` flags appended to `INSTALL_K3S_EXEC` after the invariants `--tls-san=127.0.0.1 --https-listen-port=6443`. |
| `extra_install_env`  | `{}`                  | Extra `INSTALL_K3S_*` env vars passed to the curl pipe.     |

## Invariants

The rendered installer always includes:

```
INSTALL_K3S_EXEC="server --tls-san=127.0.0.1 --https-listen-port=6443 <extra_flags joined>"
```

kube-apiserver listens on all interfaces and advertises its node
primary IP (Kubernetes endpoint validation forbids loopback IPs in
the `kubernetes` Endpoints record, so we don't try to pin advertise to
127.0.0.1). Operator-side kubeconfigs still use
`https://127.0.0.1:<local-forward-port>` over the SSH local-forward
set up by `garuda-tunnel`; the `--tls-san=127.0.0.1` invariant adds
that hostname to the apiserver certificate's SAN list so the operator
client trusts the connection. Public exposure of the API is prevented
by the compute-host firewall, which opens only `tcp/22,80,443` and
UDP (see `gcp_compute_host` / `yc_compute_host` `default_ingress`).

## Usage

```hcl
module "k3s_init" {
  source      = "../../modules/k3s_cloud_init"
  k3s_version = "v1.30.5+k3s1"
}

module "host" {
  source = "../../modules/yc_compute_host"
  # ...
  attached_disks = [{
    disk_id     = yandex_compute_disk.k3s_data.id
    device_name = "k3s-data"
    mount_path  = "/var/lib/rancher"
  }]
  user_data_parts = module.k3s_init.user_data_parts
}
```

## What this module does NOT do

- No agent role (single-server only). G3 problem.
- No HA cluster-init join. G3 problem.
- No kubeconfig fetch. Operator-side via `garuda-tunnel`.
- No bundled add-ons (cert-manager, cilium, …). Workload concern.
- No public API binding. The k3s API stays unreachable from the
  internet via firewall (port `tcp/6443` is not opened by
  `default_ingress`). Inside the node the apiserver listens on all
  interfaces but the cluster only ever sees it advertised as
  `127.0.0.1:6443`.
