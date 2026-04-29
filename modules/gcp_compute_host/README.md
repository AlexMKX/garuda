# gcp_compute_host

Provisions a Linux VM in Google Cloud with:
- Auto-generated keypair for a module-managed deploy user (default `garuda`)
- Operator/extra ssh keys passed verbatim through metadata
- Optional data disk (new or attach existing)
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
| `ssh_keys`                | `[]`                          | List of raw `user:public_key` lines for metadata['ssh-keys'].        |
| `data_disk_size_gb`       | `0`                           | When > 0, create a new ext4 data disk and mount at `/opt/garuda`.    |
| `existing_data_disk_id`   | `null`                        | Attach an existing disk by id.                                       |
| `default_ingress`         | `true`                        | Create module-managed firewall rule (SSH/HTTP/HTTPS/ICMP/UDP-all).   |
| `ingress_ports`           | `[]`                          | Additional ingress rules.                                            |
| `allow_stopping_for_update` | `false`                     | Allow GCP to stop the VM to apply changes.                           |
| `metadata`                | `{}`                          | Caller-supplied metadata; merges over module-managed keys.           |
| `labels`                  | `{}`                          | Instance labels.                                                     |
| `tags`                    | `[]`                          | Network tags.                                                        |

## Outputs

| Output              | Description                                                              |
|---------------------|--------------------------------------------------------------------------|
| `connection_data`   | Bundle: `{host, user, ssh_private_key, connection, network_os, ...}`. The `instance_token` field carries the cloud instance id (`google_compute_instance.self_link`). Downstream `linux_apply`-based modules use it to detect VM recreation and force ansible re-apply. |
| `public_ipv4`       | External IP if `nat = true` or `public_ip` set; null otherwise.          |
| `private_ipv4`      | Primary NIC internal IP.                                                 |
| `instance_id`       | GCP compute instance id.                                                 |
| `data_disk_id`      | Effective data disk id; null when no disk.                               |

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
    "alex:ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... alex@laptop",
  ]
}
```

## Hostname & FQDN

The module sets `hostname = "${env_slug}-${name}.c.${project_id}.internal"`.
GCE requires hostnames to be FQDNs with at least three labels; the
`c.<project>.internal` suffix matches GCE's auto-generated internal DNS
zone so this is a no-op for routing while making `env_slug` visible in
the operator-facing FQDN. The `hostname` attribute is forces-replacement —
changing `env_slug` or `name` recreates the instance.

## Migration from previous contract (alex user, cloud-init users block)

GCP migrates **without VM replacement** (no image change required):

1. `terragrunt apply` updates metadata in place.
2. `google-guest-agent` creates the new `garuda` user within seconds and
   provisions its `authorized_keys`.
3. Old `alex` user remains until removed from `var.ssh_keys`/inputs (or
   deleted manually). Its `authorized_keys` is untouched if not present
   in metadata.
4. Ansible inventory picks up `connection_data.user = "garuda"`.

For interactive operator access:

```hcl
ssh_keys = ["alex:${file("~/.ssh/id_ed25519.pub")}"]
```
