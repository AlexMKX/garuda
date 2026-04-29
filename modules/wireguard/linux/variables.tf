# modules/wireguard/linux/variables.tf
#
# Linux WireGuard endpoint deployment module.
# Accepts canonical tunnel data from modules/wireguard/tunnel and
# Linux-specific deployment arguments. Delegates to linux_apply.

variable "host_name" {
  description = "Ansible inventory hostname for the target Linux host."
  type        = string
}

variable "config" {
  description = "Canonical tunnel config object for this endpoint (from wireguard/tunnel output)."
  type = object({
    tunnel_name   = string
    kernel_ifname = string
    address       = string
    private_key   = string
    public_key    = string
    preshared_key = string
    listen_port   = optional(number)
    endpoint_host = optional(string)
  })
}

variable "peer" {
  description = "Canonical tunnel config object for the remote endpoint (from wireguard/tunnel output)."
  type = object({
    tunnel_name   = string
    kernel_ifname = string
    address       = string
    private_key   = string
    public_key    = string
    preshared_key = string
    listen_port   = optional(number)
    endpoint_host = optional(string)
  })
}

variable "allowed_nets" {
  description = "Additional AllowedIPs routed through the tunnel beyond the peer /32."
  type        = list(string)
}

variable "table" {
  description = "WireGuard routing table mode (e.g. 'off', 'auto', or a table number)."
  type        = string
}

variable "persistent_keepalive" {
  description = "Optional PersistentKeepalive seconds forwarded to WireGuard peer config."
  type        = number
  default     = null
  nullable    = true
}

variable "post_up" {
  description = "Optional WireGuard PostUp command."
  type        = string
  default     = ""
}

variable "pre_down" {
  description = "Optional WireGuard PreDown command."
  type        = string
  default     = ""
}

variable "labels" {
  description = "Docker container labels applied to the workload service. Consumed by the sidecar operator for workload discovery and per-container FRR/PBR rendering."
  type        = map(string)
  default     = {}
}

variable "connection_data" {
  description = "Normalized transport/auth contract for the target Linux host. Passed through to linux_apply unchanged."
  type = object({
    host                 = string
    user                 = string
    password             = optional(string)
    connection           = string
    network_os           = string
    ssh_private_key_file = optional(string)
    ssh_private_key      = optional(string)
    instance_token       = string
  })
}

variable "extra_hostvars" {
  description = "Optional additional hostvars merged into the module-local ansible_host variables."
  type        = map(any)
  default     = {}
}

variable "nic_attach" {
  description = "Transport networks to attach. Supported values: 'backbone', 'border'. Order is ignored."
  type        = list(string)
  default     = ["backbone"]

  validation {
    condition     = alltrue([for n in var.nic_attach : contains(["backbone", "border"], n)])
    error_message = "nic_attach values must be 'backbone' or 'border'."
  }
}
