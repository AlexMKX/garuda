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
| `extra_flags`        | `[]`                  | Extra `--…` flags appended to `INSTALL_K3S_EXEC` after the invariant `--bind-address=127.0.0.1 --https-listen-port=6443`. |
| `extra_install_env`  | `{}`                  | Extra `INSTALL_K3S_*` env vars passed to the curl pipe.     |

## Invariants

The rendered installer always includes:

```
INSTALL_K3S_EXEC="server --bind-address=127.0.0.1 --https-listen-port=6443 <extra_flags joined>"
```

The k3s API is bound strictly to `127.0.0.1:6443`. Operator-side access
goes through `garuda-tunnel` SSH local-forward. The module does not
expose a knob to bind elsewhere.

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
- No public API binding. Bind 127.0.0.1 is invariant.
