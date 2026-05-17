# gcp_compute_host

Provisions a Linux VM in Google Cloud with:
- Auto-generated keypair for a module-managed deploy user (default `garuda`)
- Operator/extra ssh keys passed verbatim through metadata
- Optional caller-owned disks attached via `attached_disks` (caller creates
  `google_compute_disk`; module attaches, formats on first boot, mounts)
- Optional firewall rule with SSH/HTTP/HTTPS/ICMP/UDP-all ingress

## SSH key management

Keys flow through `metadata["ssh-keys"]` only. `google-guest-agent`
(preinstalled on every official Ubuntu image) polls metadata and rewrites
each user's `~/.ssh/authorized_keys` within seconds — no reboot, no
cloud-init users block, no per-boot scripts.

Rotating `tls_private_key.admin` (`terraform apply -replace=module.X.tls_private_key.admin`)
or editing `var.ssh_keys` triggers an in-place metadata update.
`allow_stopping_for_update = true` is recommended on the caller side for
metadata changes that GCP cannot apply on a running instance.

## Image requirement

The module assumes `google-guest-agent` is preinstalled on the boot
image. **Every official GCP Ubuntu image satisfies this** (debian, RHEL,
SLES, Windows-Server families also ship the agent). No `image_family`
validation is enforced — the universe of valid families is too large to
regex-check without false positives.

If you use a custom image, ensure `google-guest-agent` is installed and
enabled. Otherwise SSH key sync silently fails — same failure mode as
not having the variable defined at all.

## Inputs

| Variable                  | Default                       | Description                                                          |
|---------------------------|-------------------------------|----------------------------------------------------------------------|
| `name`                    | (required)                    | Host slug.                                                           |
| `prefix`                  | `"garuda"`                    | First segment of the full instance name.                             |
| `env_slug`                | _(required)_                  | Mandatory environment slug. Embedded in `instance_name` and `hostname`. Format: 2–24 chars, lowercase alnum and hyphens. |
| `project`                 | (required)                    | GCP project id.                                                      |
| `region` / `zone`         | (required)                    | GCP region and zone.                                                 |
| `subnetwork`              | (required)                    | VPC subnetwork id/self-link.                                         |
| `machine_type`            | `"e2-small"`                  | GCE machine type.                                                    |
| `image_family`            | (module default)              | Boot image family — must include `google-guest-agent`.               |
| `image_project`           | (module default)              | Image project id (e.g. `ubuntu-os-cloud`).                           |
| `nat`                     | `true`                        | Allocate ephemeral external IP.                                      |
| `public_ip`               | `null`                        | Static external IP id (overrides `nat`).                             |
| `ssh_user`                | `"garuda"`                    | Module-managed deploy user.                                          |
| `ssh_keys`                | _(required)_                  | List of raw `user:public_key` lines for metadata['ssh-keys']. Pass `[]` to opt into "generated admin key only" mode. Format-validated; rejects malformed entries; `null` is not allowed (`nullable = false`). |
| `attached_disks`          | `[]`                          | Caller-owned disks to attach and mount. Each entry: `{ disk_id, device_name, mount_path, fs_type }`. The module never creates disks. See "With attached disks" below. |
| `default_ingress`         | `true`                        | Create module-managed firewall rule (SSH/HTTP/HTTPS/ICMP/UDP-all).   |
| `ingress_ports`           | `[]`                          | Additional ingress rules.                                            |
| `allow_stopping_for_update` | `false`                     | Allow GCP to stop the VM to apply changes.                           |
| `metadata`                | `{}`                          | Caller-supplied metadata; merges over module-managed keys.           |
| `user_data_parts`         | `[]`                          | Additional cloud-config documents (each starting with `#cloud-config`) merged after the module's data-disk bootstrap. See "Extending cloud-init" below. |
| `labels`                  | `{}`                          | Instance labels.                                                     |
| `tags`                    | `[]`                          | Network tags.                                                        |

## Outputs

| Output              | Description                                                              |
|---------------------|--------------------------------------------------------------------------|
| `connection_data`   | Bundle: `{host, user, ssh_private_key, connection, network_os, ...}`. The `instance_token` field carries the cloud instance id (`google_compute_instance.self_link`). Downstream `linux_apply`-based modules use it to detect VM recreation and force ansible re-apply. |
| `public_ipv4`       | External IP if `nat = true` or `public_ip` set; null otherwise.          |
| `private_ipv4`      | Primary NIC internal IP.                                                 |
| `instance_id`       | GCP compute instance id.                                                 |

## Examples

### Minimal

```hcl
module "vm" {
  source       = "../gcp_compute_host"
  name         = "frontend"
  project      = var.project
  region       = "us-central1"
  zone         = "us-central1-a"
  subnetwork   = data.google_compute_subnetwork.primary.id
}
```

### With operator key

```hcl
module "vm" {
  source       = "../gcp_compute_host"
  name         = "frontend"
  project      = var.project
  region       = "us-central1"
  zone         = "us-central1-a"
  subnetwork   = data.google_compute_subnetwork.primary.id

  ssh_keys = [
    "operator:ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... operator@workstation",
  ]
}
```

### With attached disks

```hcl
resource "google_compute_disk" "host_data" {
  name    = "${var.env_slug}-host-data"
  project = var.project_id
  zone    = var.zone
  type    = "pd-balanced"
  size    = 50

  lifecycle {
    prevent_destroy = true
  }
}

module "vm" {
  source     = "../gcp_compute_host"
  name       = "stateful"
  env_slug   = var.env_slug
  project    = var.project_id
  region     = var.region
  zone       = var.zone
  subnetwork = data.google_compute_subnetwork.primary.id
  ssh_keys   = []

  attached_disks = [
    {
      disk_id     = google_compute_disk.host_data.id
      device_name = "host-data"
      mount_path  = "/var/lib/host-data"
    },
  ]
}
```

`device_name` surfaces inside the guest as `/dev/disk/by-id/google-host-data`.
The compute-host module renders a `00-attached-disks.yaml` cloud-config part
that runs `fs_setup` with `overwrite: false`, writes an `/etc/fstab` entry
with `nofail`, and runs `mkdir -p` plus `mount -a` on first boot. On
instance recreate (same disk, new VM) the existing filesystem is preserved.

## Hostname & FQDN

The module sets `hostname = "${env_slug}-${name}.c.${project_id}.internal"`.
GCE requires hostnames to be FQDNs with at least three labels; the
`c.<project>.internal` suffix matches GCE's auto-generated internal DNS
zone so this is a no-op for routing while making `env_slug` visible in
the operator-facing FQDN. The `hostname` attribute is forces-replacement —
changing `env_slug` or `name` recreates the instance.

## Extending cloud-init

The module renders `metadata["user-data"]` as a multipart MIME bundle via the
`hashicorp/cloudinit` provider. Part ordering:

1. **Attached-disk bootstrap** (filename `00-attached-disks.yaml`) — only
   rendered when `attached_disks` is non-empty. Runs `fs_setup`,
   appends `/etc/fstab` entries with `nofail`, and runs
   `mkdir -p <mount_path>` plus `mount -a` for every entry.
2. **Caller parts** (filenames `10-user-0.yaml`, `11-user-1.yaml`, …) —
   each element of `var.user_data_parts` in declared order.

Cloud-init applies parts alphabetically by filename, so the numeric prefix
guarantees the bootstrap runs before any caller part on the VM.

Merge type: `list(append)+dict(no_replace,recurse_list)+str(append)`. Caller
`runcmd` lists are appended to the bootstrap; callers cannot overwrite the
module's `fs_setup`/`mounts`.

When neither the bootstrap nor `user_data_parts` is needed, the
`metadata["user-data"]` key is absent from the instance (rather than
empty).

### Example: k3s install

```hcl
module "vm" {
  source     = "../gcp_compute_host"
  name       = "edge"
  env_slug   = "example-prod"
  project    = var.project
  region     = "us-central1"
  zone       = "us-central1-a"
  subnetwork = data.google_compute_subnetwork.primary.id
  ssh_keys   = ["operator:${file("~/.ssh/id_ed25519.pub")}"]

  user_data_parts = [
    "#cloud-config\n${yamlencode({
      packages = ["curl", "ca-certificates"]
      runcmd   = ["curl -sfL https://example.net/k3s-install | sh -"]
    })}",
  ]
}
```

`yamlencode` emits a bare YAML document without the `#cloud-config`
header that cloud-init requires. Prepend the header explicitly when
building inline as shown above.

## Migration from previous contract (operator user, cloud-init users block)

GCP migrates **without VM replacement** (no image change required):

1. `terragrunt apply` updates metadata in place.
2. `google-guest-agent` creates the new `garuda` user within seconds and
   provisions its `authorized_keys`.
3. Old `operator` user remains until removed from `var.ssh_keys`/inputs (or
   deleted manually). Its `authorized_keys` is untouched if not present
   in metadata.
4. Ansible inventory picks up `connection_data.user = "garuda"`.

For interactive operator access:

```hcl
ssh_keys = ["operator:${file("~/.ssh/id_ed25519.pub")}"]
```

### Migration from the old `data_disk_size_gb` / `existing_data_disk_id`

This release removes both variables. Pick the path that matches the previous caller setup:

- **Previously `data_disk_size_gb > 0` (module owned the disk).** Run
  `terraform state mv 'module.<name>.google_compute_disk.data[0]' <caller_disk_address>` before `terragrunt apply`. The `[0]` index is required — the historic resource was declared with `count = 1`. After the move the disk lives in caller TF state without recreation; then pass it via `attached_disks`.
- **Previously `existing_data_disk_id` (caller already owned the disk).** Stop passing `existing_data_disk_id`. Declare or reference the disk on the caller side and pass its id (or self_link) via `attached_disks`. No `state mv` is needed.
- **Disposable stacks.** Drop the old variable, declare a fresh `google_compute_disk`, and apply. The old disk is destroyed; data is lost.

Unlike the YC module, the GCP module never hardcoded a workload mount path. Choose `device_name` and `mount_path` to fit the calling stack. If a stack expects `/opt/garuda` (e.g. when mirroring the YC hub layout), pass `device_name = "garuda-data"` and `mount_path = "/opt/garuda"`.

Production stacks should declare `lifecycle { prevent_destroy = true }` on the caller-owned `google_compute_disk` so an accidental `terragrunt destroy` cannot wipe the persistent data; only disposable test stacks should leave it at `false`.
