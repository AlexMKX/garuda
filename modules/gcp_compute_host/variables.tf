variable "name" {
  description = "Host slug, used to derive the instance and hostname. Underscores replaced with hyphens."
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
sharing a GCP project do not collide on the auto-derived per-project
internal FQDN. Two stacks with role `edge` in the same project
need distinct hostnames; this slug provides that scope.

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

variable "project_id" {
  description = "GCP project id to create the instance in."
  type        = string
}

variable "region" {
  description = "GCP region (e.g. us-central1). Used for google_compute_address."
  type        = string
}

variable "zone" {
  description = "GCP zone (e.g. us-central1-a)."
  type        = string
}

variable "network" {
  description = "VPC network name or self_link."
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "Optional VPC subnetwork name or self_link. Null means auto-select from network."
  type        = string
  default     = null
}

variable "machine_type" {
  description = "GCE machine type."
  type        = string
  default     = "e2-small"
}

variable "image" {
  description = "GCE image family or full image path."
  type        = string
  default     = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2404-lts-amd64"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GiB."
  type        = number
  default     = 20
}

variable "boot_disk_type" {
  description = "Boot disk type (pd-standard, pd-balanced, pd-ssd)."
  type        = string
  default     = "pd-balanced"
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
"user:public_key" line consumed verbatim by google-guest-agent. The agent
creates each user on first contact (passwordless sudoer with bash shell)
and rewrites that user's ~/.ssh/authorized_keys whenever metadata changes
— no reboot, no cloud-init users-groups, no startup script.

Use this for operator-side keys (e.g. "alex:ssh-ed25519 AAAA... alex@laptop")
or any additional automation account distinct from var.ssh_user.

Format: "username:keytype keydata [comment]" — exactly what GCP expects.
The comment in the public key is informational only; the user prefix
before the first colon is what determines which Linux user the key is
written for.
EOT
  type        = list(string)
  default     = []
}

variable "metadata" {
  description = "Additional instance metadata merged with module-managed keys (ssh-keys, user-data). User keys take precedence."
  type        = map(string)
  default     = {}
}

variable "labels" {
  description = "Instance labels."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Network tags added to the instance in addition to the module-managed firewall tag."
  type        = list(string)
  default     = []
}

variable "allocate_static_ip" {
  description = "Create a regional google_compute_address and attach as external IP."
  type        = bool
  default     = true
}

variable "default_ingress" {
  description = "Create a firewall with SSH/HTTP/HTTPS/ICMP allow from 0.0.0.0/0."
  type        = bool
  default     = true
}

variable "ingress_ports" {
  description = "Additional ingress rules merged into the module-managed firewall."
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
  description = "Attach an existing persistent disk by id/self_link instead of creating a new one."
  type        = string
  default     = null
}

variable "allow_stopping_for_update" {
  description = "Allow terraform to stop the instance to apply machine_type or metadata changes."
  type        = bool
  default     = false
}

# Mutual exclusion between create-new vs attach-existing.
locals {
  _data_disk_conflict = (var.data_disk_size_gb > 0) && (var.existing_data_disk_id != null)
}

check "data_disk_mutually_exclusive" {
  assert {
    condition     = !local._data_disk_conflict
    error_message = "data_disk_size_gb and existing_data_disk_id are mutually exclusive."
  }
}

