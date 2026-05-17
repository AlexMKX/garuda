# yc_compute_host

Provisions a Linux VM in Yandex Cloud with:
- Auto-generated keypair for a module-managed deploy user (default `garuda`)
- Operator/extra ssh keys passed verbatim through metadata
- Optional caller-owned disks attached via `attached_disks` (caller creates
  `yandex_compute_disk`; module attaches, formats on first boot, mounts)
- Optional security group with SSH/HTTP/HTTPS/ICMP/UDP-all ingress

## SSH key management

Keys flow through `metadata["ssh-keys"]` only. The cloud guest agent
(`yandex-cloud-guest-agent`) polls metadata and rewrites each user's
`~/.ssh/authorized_keys` within seconds — no reboot, no cloud-init users
block, no per-boot scripts.

Rotating `tls_private_key.admin` (`terraform apply -replace=module.X.tls_private_key.admin`)
or editing `var.ssh_keys` triggers an in-place metadata update;
`allow_stopping_for_update` is hard-coded `true` inside the module
because YC may need to stop/start the instance to apply metadata changes.

## Image family requirement

**Only `*-oslogin` Yandex Cloud image families are supported.** The
`yandex-cloud-guest-agent` is preinstalled there and not in plain
`ubuntu-2404-lts`. Default `image_family = "ubuntu-2404-lts-oslogin"`,
and the variable validation rejects any value not matching `oslogin`.

The `*-oslogin` name only means the agent is preinstalled — it does
**not** by itself activate OS Login (IAM-managed SSH). Activation is a
two-part contract; see below.

## OS Login activation

The module exposes `var.oslogin_enabled` (default **`false`** — opt-in)
to set the per-instance `metadata["enable-oslogin"] = "true"` key.

**Why opt-in.** yandex-cloud-guest-agent is a fork of the Google
Compute Engine guest agent and inherits its switching logic: when
`enable-oslogin=true` is set, the agent **stops** syncing
`metadata["ssh-keys"]` into per-user `authorized_keys` and serves
only IAM-managed OS Login profiles. Flipping the flag without the
full prerequisite chain locks every account out of the VM, including
the module-managed `garuda` deploy user.

Prerequisites before setting `oslogin_enabled = true`:

1. **Org-level toggle.** Enable OS Login at
   *Cloud Organization → Access management → SSH access via OS Login*.
   See <https://yandex.cloud/docs/organization/operations/os-login-access>.
2. **OS Login profile** with an SSH key uploaded for every operator
   (or service account) that needs SSH access. The agent creates the
   linux user matching the profile's `login` field on first connect.
3. **IAM role** `compute.osLogin` (or `compute.osAdminLogin` for
   sudo) granted on the target cloud/folder.

Once enabled, connect with `yc compute ssh --id <instance-id>` (uses
a short-lived SSH certificate) or with a standard SSH client using
the OS Login profile's login as the SSH user.

## Inputs

| Variable                  | Default                          | Description                                                            |
|---------------------------|----------------------------------|------------------------------------------------------------------------|
| `name`                    | (required)                       | Host slug; used to derive instance name and Linux hostname.            |
| `prefix`                  | `"garuda"`                       | First segment of the full instance name.                               |
| `env_slug`                | _(required)_                     | Mandatory environment slug. Embedded in `instance_name` and `hostname` so multiple stacks sharing a YC VPC produce distinct per-network FQDNs. Format: 2–24 chars, lowercase alnum and hyphens. |
| `zone`                    | `"ru-central1-d"`                | YC availability zone.                                                  |
| `subnet_id`               | (required)                       | VPC subnet id for the primary NIC.                                     |
| `network_id`              | `null` (resolved from subnet)    | VPC network id; needed when default_ingress=true.                      |
| `image_family`            | `"ubuntu-2404-lts-oslogin"`      | Image family; **must contain "oslogin"** (validated).                  |
| `cores` / `memory_gb`     | `2` / `4`                        | vCPU count / RAM (GiB).                                                |
| `nat`                     | `true`                           | Allocate public IPv4 via 1:1 NAT.                                      |
| `ssh_user`                | `"garuda"`                       | Module-managed deploy user; auto-generated keypair binds to it.        |
| `ssh_keys`                | _(required)_                     | List of raw `user:public_key` lines for metadata['ssh-keys']. Pass `[]` to opt into "generated admin key only" mode. Format-validated; rejects malformed entries; `null` is not allowed (`nullable = false`). |
| `oslogin_enabled`         | `false`                          | Opt-in. When `true`, sets `metadata["enable-oslogin"]="true"` and the guest agent abandons `metadata["ssh-keys"]` in favour of OS Login profiles. Requires org-level OS Login + per-user profile + `compute.osLogin` role. |
| `attached_disks`          | `[]`                             | Caller-owned disks to attach and mount. Each entry: `{ disk_id, device_name, mount_path, fs_type }`. The module never creates disks. See "With attached disks" below. |
| `default_ingress`         | `true`                           | Create module-managed SG (SSH/HTTP/HTTPS/ICMP/UDP-all from 0.0.0.0/0). |
| `ingress_ports`           | `[]`                             | Additional ingress rules merged into the module-managed SG.            |
| `metadata`                | `{}`                             | Caller-supplied metadata; merges over module-managed `ssh-keys` and `user-data`. |
| `user_data_parts`         | `[]`                             | Additional cloud-config documents (each starting with `#cloud-config`) merged after the module's data-disk bootstrap. See "Extending cloud-init" below. |
| `labels`                  | `{}`                             | Instance labels.                                                       |

## Outputs

| Output              | Description                                                              |
|---------------------|--------------------------------------------------------------------------|
| `connection_data`   | Bundle: `{host, user, ssh_private_key, connection, network_os, ...}`. Pass to Linux workload modules unchanged. The `instance_token` field carries the cloud instance id (`yandex_compute_instance.id`). Downstream `linux_apply`-based modules use it to detect VM recreation and force ansible re-apply. |
| `public_ipv4`       | NAT IP if `nat = true`; null otherwise.                                  |
| `private_ipv4`      | Primary NIC private IP.                                                  |
| `fqdn` / `hostname` | YC-assigned FQDN / configured Linux hostname.                            |
| `instance_id`       | YC compute instance id.                                                  |

## Examples

### Minimal

```hcl
module "vm" {
  source     = "../yc_compute_host"
  name       = "frontend"
  zone       = "ru-central1-d"
  subnet_id  = data.yandex_vpc_subnet.primary.id
  network_id = data.yandex_vpc_network.default.id
}
```

Connects as `garuda` with the module-generated key:

```bash
ssh -i <(echo "${output.connection_data.ssh_private_key}") garuda@${output.public_ipv4}
```

### With operator key

```hcl
module "vm" {
  source     = "../yc_compute_host"
  name       = "frontend"
  zone       = "ru-central1-d"
  subnet_id  = data.yandex_vpc_subnet.primary.id

  ssh_keys = [
    "operator:ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... operator@workstation",
  ]
}
```

`operator` is created by the guest agent on first boot; its `~operator/.ssh/authorized_keys`
contains the operator key. `garuda` (Terraform-managed) coexists in `~garuda/.ssh/authorized_keys`.

### With attached disks

```hcl
resource "yandex_compute_disk" "host_data" {
  name = "${var.env_slug}-host-data"
  zone = var.zone
  size = 50
  type = "network-ssd"

  lifecycle {
    prevent_destroy = true
  }
}

module "vm" {
  source    = "../yc_compute_host"
  name      = "stateful"
  env_slug  = var.env_slug
  subnet_id = data.yandex_vpc_subnet.primary.id
  ssh_keys  = []

  attached_disks = [
    {
      disk_id     = yandex_compute_disk.host_data.id
      device_name = "host-data"
      mount_path  = "/var/lib/host-data"
    },
  ]
}
```

`device_name` surfaces inside the guest as `/dev/disk/by-id/virtio-host-data`.
The compute-host module renders a `00-attached-disks.yaml` cloud-config part
that runs `fs_setup` with `overwrite: false`, writes an `/etc/fstab` entry
with `nofail`, and runs `mkdir -p` plus `mount -a` on first boot. On
instance recreate (same disk, new VM) the existing filesystem is preserved.

## Hostname & FQDN

The module sets `hostname = "${env_slug}-${name}"` (with underscores in
`name` replaced by hyphens). YC computes the per-VPC FQDN as
`<hostname>.<zone>.internal`, which must be unique across instances
attached to the same network. Embedding `env_slug` is what allows two
garuda stacks (e.g. `prod` and `staging`) to coexist with the
same role (e.g. `hub`) inside one VPC.

`hostname` is a forces-replacement attribute: changing `env_slug` or
`name` on an existing instance recreates it. Persist state across
recreates by creating `yandex_compute_disk` resources in the caller
(with `prevent_destroy`) and passing them through `attached_disks`.

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
  source    = "../yc_compute_host"
  name      = "edge"
  env_slug  = "example-prod"
  subnet_id = data.yandex_vpc_subnet.primary.id
  ssh_keys  = ["operator:${file("~/.ssh/id_ed25519.pub")}"]

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

## Extending cloud-init

The module renders `metadata["user-data"]` as a multipart MIME bundle via the
`hashicorp/cloudinit` provider. Part ordering:

1. **Bootstrap** (filename `00-bootstrap-data-disk.yaml`) — only rendered
   when `data_disk_size_gb > 0` or `existing_data_disk_id != null`. Mounts
   the data disk at `/opt/garuda` with `fs_setup.overwrite: false`.
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
  source    = "../yc_compute_host"
  name      = "edge"
  env_slug  = "example-prod"
  subnet_id = data.yandex_vpc_subnet.primary.id
  ssh_keys  = ["operator:${file("~/.ssh/id_ed25519.pub")}"]

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

VMs created on the old contract migrate as follows:

1. `terragrunt apply` updates metadata. **Image family change** (`ubuntu-2404-lts` → `ubuntu-2404-lts-oslogin`) triggers boot disk replacement.
2. Preserve data by pre-creating a `yandex_compute_disk` in the caller (with `prevent_destroy`) and passing it through `attached_disks`.
3. After apply, new VM comes up with `garuda` (Terraform-managed) plus any users from `var.ssh_keys`. The old `operator` user is gone with the boot disk.
4. Ansible inventory naturally picks up `connection_data.user = "garuda"`. Workload playbooks run as `garuda`.

For interactive operator access, add an entry to `var.ssh_keys`:

```hcl
ssh_keys = ["operator:${file("~/.ssh/id_ed25519.pub")}"]
```

### Migration from the old `data_disk_size_gb` / `existing_data_disk_id`

This release removes both variables. Pick the path that matches the previous caller setup:

- **Previously `data_disk_size_gb > 0` (module owned the disk).** Run
  `terraform state mv 'module.<name>.yandex_compute_disk.data[0]' <caller_disk_address>` before `terragrunt apply`. The `[0]` index is required — the historic resource was declared with `count = 1`. After the move the disk lives in caller TF state without recreation; then pass it via `attached_disks`.
- **Previously `existing_data_disk_id` (caller already owned the disk).** Stop passing `existing_data_disk_id`. Declare or reference the disk on the caller side and pass its id via `attached_disks`. No `state mv` is needed — the disk was never in the module's state.
- **Disposable stacks.** Drop the old variable, declare a fresh `yandex_compute_disk`, and apply. The old disk is destroyed; data is lost.

In all paths, set `device_name = "garuda-data"` and `mount_path = "/opt/garuda"` to keep compatibility with workload roles (firezone_oidc, ipt_server, backbone_network) that default to subpaths under `/opt/garuda`.

Production stacks should declare `lifecycle { prevent_destroy = true }` on the caller-owned `yandex_compute_disk` so an accidental `terragrunt destroy` cannot wipe the persistent data; only disposable test stacks (like `examples/mini-site/`) should leave it at `false`.
