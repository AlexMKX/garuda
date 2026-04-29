variable "name" {
  description = "Stable workload identifier used for generated payload artifacts."
  type        = string
}

variable "host_name" {
  description = "Inventory host running the Firezone stack."
  type        = string
}

variable "firezone_dir" {
  description = "Target directory for the Firezone compose project. Default sits under /opt/garuda so that data disks mounted at /opt/garuda automatically persist Firezone state (Postgres DB, WireGuard private key, Caddy data) across VM recreates."
  type        = string
  default     = "/opt/garuda/firezone"
}

variable "server_url" {
  description = "Public Firezone server URL advertised to clients."
  type        = string
}

variable "admin_password" {
  description = "Bootstrap password for the Firezone admin account."
  type        = string
  sensitive   = true
}

variable "client_subnet" {
  description = "Client address pool routed through Firezone."
  type        = string
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
