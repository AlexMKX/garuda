variable "name" {
  description = "Host slug. Used to derive yc instance name and Linux hostname; underscores are replaced with hyphens."
  type        = string
}

variable "prefix" {
  description = "Instance-name prefix (first segment of the full name)."
  type        = string
  default     = "garuda"
}

variable "env_slug" {
  description = <<EOT
Environment slug. Mandatory.

Embedded in instance name AND hostname so multiple garuda stacks
sharing a Yandex VPC do not collide on the auto-derived per-network
FQDN (`<hostname>.<zone>.internal`). Two stacks with role `hub` in the
same VPC need distinct hostnames; this slug provides that scope.

Format: 2–24 chars, lower-case alphanumerics and hyphens, no leading
or trailing hyphen.
EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.env_slug))
    error_message = "env_slug must be 2+ chars, lower-case alphanumerics and hyphens, no leading/trailing hyphen."
  }

  validation {
    condition     = length(var.env_slug) >= 2 && length(var.env_slug) <= 24
    error_message = "env_slug must be between 2 and 24 characters."
  }
}

variable "zone" {
  description = "Yandex Cloud availability zone id (e.g. ru-central1-d)."
  type        = string
  default     = "ru-central1-d"
}

variable "subnet_id" {
  description = "Yandex VPC subnet id to attach the primary interface to."
  type        = string
}

variable "network_id" {
  description = "Yandex VPC network id. Required when default_ingress=true or ingress_ports is non-empty (used to create the module-managed security group). Can be obtained from the subnet's network_id attribute. When null, the module resolves it via a data source lookup on subnet_id."
  type        = string
  default     = null
}

variable "security_group_ids" {
  description = "External security group ids attached to the primary NIC in addition to any module-managed SG."
  type        = list(string)
  default     = []
}

variable "platform_id" {
  description = "Yandex Cloud compute platform id."
  type        = string
  default     = "standard-v3"
}

variable "cores" {
  description = "vCPU cores."
  type        = number
  default     = 2
}

variable "memory_gb" {
  description = "RAM in GiB."
  type        = number
  default     = 4
}

variable "core_fraction" {
  description = "Guaranteed CPU share percent."
  type        = number
  default     = 100
}

variable "preemptible" {
  description = "May be preempted by YC."
  type        = bool
  default     = false
}

variable "image_family" {
  description = <<EOT
Yandex Cloud image family. MUST be an *-oslogin family (e.g.
`ubuntu-2404-lts-oslogin`). Only oslogin images ship the
yandex-cloud-guest-agent that synchronises metadata['ssh-keys'] into
per-user ~/.ssh/authorized_keys files in real time.

Non-oslogin families have no agent: the module's contract (rotate keys
via Terraform, expect them on the VM seconds later) silently breaks
because there is nothing to read metadata.
EOT
  type        = string
  default     = "ubuntu-2404-lts-oslogin"

  validation {
    condition     = can(regex("oslogin", var.image_family))
    error_message = "image_family must be an *-oslogin family (yandex-cloud-guest-agent ships only there); SSH key sync requires the agent."
  }
}

variable "image_folder_id" {
  description = "Folder that holds the image family."
  type        = string
  default     = "standard-images"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GiB."
  type        = number
  default     = 20
}

variable "boot_disk_type" {
  description = "Boot disk type id."
  type        = string
  default     = "network-ssd"
}

variable "nat" {
  description = "Allocate public IPv4 via one-to-one NAT on primary NIC."
  type        = bool
  default     = true
}

variable "ssh_user" {
  description = <<EOT
Username for the module-managed deploy account. A keypair is auto-generated
for this user, exposed via connection_data.ssh_private_key, and added to
metadata['ssh-keys'] as `$${var.ssh_user}:<generated_pubkey>`. Defaults to
"garuda" to keep the deploy account distinct from any operator login.
EOT
  type        = string
  default     = "garuda"
}

variable "ssh_keys" {
  description = <<EOT
Additional ssh keys baked into metadata['ssh-keys']. Each entry is a raw
"user:public_key" line consumed verbatim by the cloud guest agent. The
agent creates each user on first contact (passwordless sudoer with bash
shell) and rewrites that user's ~/.ssh/authorized_keys whenever metadata
changes — no reboot, no cloud-init users-groups, no startup script.

Use this for operator-side keys (e.g. "alex:ssh-ed25519 AAAA... alex@laptop")
or any additional automation account distinct from var.ssh_user.

Format: "username:keytype keydata [comment]" — exactly what GCP/YC expect.
The comment in the public key is informational only; the user prefix
before the first colon is what determines which Linux user the key is
written for.
EOT
  type        = list(string)
  default     = []
}

variable "oslogin_enabled" {
  description = <<EOT
Activate Yandex Cloud OS Login on this instance by setting the
`enable-oslogin=true` metadata key. Default `false`.

IMPORTANT — opt-in by design. yandex-cloud-guest-agent (a fork of the
Google Compute Engine guest agent) inherits its parent's behaviour:
when `enable-oslogin=true` is set, the agent stops syncing
`metadata["ssh-keys"]` into per-user `~/.ssh/authorized_keys`. Turning
this on without (a) org-level OS Login enabled, (b) an OS Login
profile on the connecting user, and (c) the `compute.osLogin` IAM
role on the target cloud/folder will lock everyone out of the VM —
including the module-managed `garuda` deploy user — because both
channels end up unusable.

Recommended rollout: enable on the call site only after the org-level
toggle is on and at least one operator has an OS Login profile with
an SSH key uploaded.
EOT
  type        = bool
  default     = false
}

variable "metadata" {
  description = "Additional instance metadata merged with module-managed keys (ssh-keys, user-data, optionally enable-oslogin). User keys take precedence."
  type        = map(string)
  default     = {}
}

variable "labels" {
  description = "Instance labels."
  type        = map(string)
  default     = {}
}

variable "default_ingress" {
  description = "Create a yandex_vpc_security_group with SSH/HTTP/HTTPS/ICMP ingress from 0.0.0.0/0."
  type        = bool
  default     = true
}

variable "ingress_ports" {
  description = "Additional ingress rules merged into the module-managed SG."
  type = list(object({
    protocol     = string
    port         = number
    description  = string
    source_cidrs = optional(list(string), ["0.0.0.0/0"])
  }))
  default = []
}

variable "data_disk_size_gb" {
  description = "When > 0, create a new persistent disk of this size, ext4, mounted at /opt/garuda."
  type        = number
  default     = 0
}

variable "existing_data_disk_id" {
  description = "Attach an existing disk by id instead of creating a new one."
  type        = string
  default     = null
}

# The module will not accept both data_disk_size_gb > 0 and existing_data_disk_id.
locals {
  _data_disk_conflict = (var.data_disk_size_gb > 0) && (var.existing_data_disk_id != null)
}

check "data_disk_mutually_exclusive" {
  assert {
    condition     = !local._data_disk_conflict
    error_message = "data_disk_size_gb and existing_data_disk_id are mutually exclusive."
  }
}
