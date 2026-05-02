variable "name" {
  description = "Stable tunnel name used as interface and workload identifier."
  type        = string

  # Combined-length cap is checked here (not on var.env_slug) so the
  # error fingerprints both contributing variables but Terraform points
  # at the one most often changed by the operator.
  validation {
    condition     = length("${var.env_slug}-${replace(var.name, "_", "-")}") <= 32
    error_message = "env_slug + tunnel name (hyphenated) exceeds the RouterOS 32-char identifier ceiling."
  }
}

variable "subnet" {
  description = "CIDR subnet for the point-to-point tunnel (e.g. 192.0.2.0/28)."
  type        = string
}

variable "peers" {
  description = "Map of exactly two peers keyed by caller-chosen key (e.g. core/edge). Each peer declares its tunnel address, listen port, and optional endpoint."
  type = map(object({
    address       = string
    listen_port   = number
    endpoint_host = optional(string)
  }))

  validation {
    condition     = length(var.peers) == 2
    error_message = "Exactly two peers must be provided."
  }

  validation {
    condition     = alltrue([for p in values(var.peers) : p.address != null && p.address != ""])
    error_message = "Each peer must have a non-empty address."
  }
}

variable "env_slug" {
  description = <<EOT
Environment slug. Mandatory.

Prefixed onto `tunnel_name` so RouterOS resources (interface, OSPF
instance/area, bypass routing table, address-list, scheduler, script,
firewall filter/mangle) named after this tunnel are unique across
stacks sharing a RouterOS device.

Linux WireGuard kernel ifname is exposed separately as `kernel_ifname`
(no env_slug) so it stays within IFNAMSIZ=15.

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
