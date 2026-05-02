# yc_compute_host

Provisions a Linux VM in Yandex Cloud with:
- Auto-generated keypair for a module-managed deploy user (default `garuda`)
- Operator/extra ssh keys passed verbatim through metadata
- Optional data disk (new or attach existing)
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
| `ssh_keys`                | `[]`                             | List of raw `user:public_key` lines for metadata['ssh-keys'].          |
| `oslogin_enabled`         | `false`                          | Opt-in. When `true`, sets `metadata["enable-oslogin"]="true"` and the guest agent abandons `metadata["ssh-keys"]` in favour of OS Login profiles. Requires org-level OS Login + per-user profile + `compute.osLogin` role. |
| `data_disk_size_gb`       | `0`                              | When > 0, create a new ext4 data disk and mount at `/opt/garuda`.      |
| `existing_data_disk_id`   | `null`                           | Attach an existing disk by id instead of creating a new one.           |
| `default_ingress`         | `true`                           | Create module-managed SG (SSH/HTTP/HTTPS/ICMP/UDP-all from 0.0.0.0/0). |
| `ingress_ports`           | `[]`                             | Additional ingress rules merged into the module-managed SG.            |
| `metadata`                | `{}`                             | Caller-supplied metadata; merges over module-managed `ssh-keys` and `user-data`. |
| `labels`                  | `{}`                             | Instance labels.                                                       |

## Outputs

| Output              | Description                                                              |
|---------------------|--------------------------------------------------------------------------|
| `connection_data`   | Bundle: `{host, user, ssh_private_key, connection, network_os, ...}`. Pass to Linux workload modules unchanged. The `instance_token` field carries the cloud instance id (`yandex_compute_instance.id`). Downstream `linux_apply`-based modules use it to detect VM recreation and force ansible re-apply. |
| `public_ipv4`       | NAT IP if `nat = true`; null otherwise.                                  |
| `private_ipv4`      | Primary NIC private IP.                                                  |
| `fqdn` / `hostname` | YC-assigned FQDN / configured Linux hostname.                            |
| `instance_id`       | YC compute instance id.                                                  |
| `data_disk_id`      | Effective data disk id (new or attached existing); null when no disk.    |

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
    "alex:ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... alex@laptop",
  ]
}
```

`alex` is created by the guest agent on first boot; its `~alex/.ssh/authorized_keys`
contains the operator key. `garuda` (Terraform-managed) coexists in `~garuda/.ssh/authorized_keys`.

### With data disk

```hcl
module "vm" {
  source            = "../yc_compute_host"
  name              = "stateful"
  subnet_id         = data.yandex_vpc_subnet.primary.id
  data_disk_size_gb = 50  # creates new ext4 at /opt/garuda
}

# To reattach an existing disk after VM recreate:
# data_disk_size_gb = 0
# existing_data_disk_id = "fv4..."
```

## Hostname & FQDN

The module sets `hostname = "${env_slug}-${name}"` (with underscores in
`name` replaced by hyphens). YC computes the per-VPC FQDN as
`<hostname>.<zone>.internal`, which must be unique across instances
attached to the same network. Embedding `env_slug` is what allows two
garuda stacks (e.g. `prod` and `staging`) to coexist with the
same role (e.g. `hub`) inside one VPC.

`hostname` is a forces-replacement attribute: changing `env_slug` or
`name` on an existing instance recreates it. Pre-create the data disk
(see `existing_data_disk_id`) if you need disk persistence across
recreates.

## Migration from previous contract (alex user, cloud-init users block)

VMs created on the old contract migrate as follows:

1. `terragrunt apply` updates metadata. **Image family change** (`ubuntu-2404-lts` → `ubuntu-2404-lts-oslogin`) triggers boot disk replacement.
2. Preserve data with `existing_data_disk_id`. Set `data_disk_size_gb = 0` and pass the existing disk id.
3. After apply, new VM comes up with `garuda` (Terraform-managed) plus any users from `var.ssh_keys`. The old `alex` user is gone with the boot disk.
4. Ansible inventory naturally picks up `connection_data.user = "garuda"`. Workload playbooks run as `garuda`.

For interactive operator access, add an entry to `var.ssh_keys`:

```hcl
ssh_keys = ["alex:${file("~/.ssh/id_ed25519.pub")}"]
```
