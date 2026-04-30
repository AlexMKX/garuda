variable "name" {
  description = "Stable workload identifier used for generated payload artifacts."
  type        = string
}

variable "host_name" {
  description = "Inventory host running the IPT stack."
  type        = string
}

variable "ipt_server_dir" {
  description = "Target directory for the IPT compose project."
  type        = string
}

variable "interfaces" {
  description = "List of network interfaces for PBR/input handling."
  type        = list(string)
  default     = ["backbone"]
}

variable "routes" {
  description = "Ordered routing policy entries consumed by the IPT workload. Each entry groups an ordered member list (route) with match rules as bare strings (type inferred in the pydantic model)."
  type = list(object({
    route = list(object({
      gw  = optional(string)
      dev = optional(string)
    }))
    rules = list(string)
  }))

  validation {
    condition = alltrue([
      for entry in var.routes : length(entry.route) >= 1
    ])
    error_message = "Each route entry must have at least one route member."
  }

  validation {
    condition = alltrue([
      for entry in var.routes : length(entry.rules) >= 1
    ])
    error_message = "Each route entry must have at least one rule."
  }
}

variable "clean_conntrack" {
  description = "Whether the IPT workload should clean conntrack state for managed flows."
  type        = bool
  default     = true
}

variable "domain_route_ttl" {
  description = "TTL in seconds for domain-derived routing entries."
  type        = number
  default     = 300
}

variable "nic_attach" {
  description = "Additional transport networks to attach beyond backbone. Backbone is added unconditionally by the role. Supported additional values: 'border'."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for n in var.nic_attach : contains(["backbone", "border"], n)])
    error_message = "nic_attach values must be 'backbone' or 'border'."
  }
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

variable "pinning_egress" {
  description = "Optional egress catalog for per-source-IP pinning. Keys are slug-style identifiers shown to end users (^[a-z0-9_-]+$, 'auto' is reserved). Each value is one of {gw = string} or {dev = string}. An empty map disables the pinning subsystem entirely."
  type = map(object({
    gw  = optional(string)
    dev = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for key, _ in var.pinning_egress :
      can(regex("^[a-z0-9_-]+$", key)) && lower(key) != "auto"
    ])
    error_message = "pinning_egress keys must match ^[a-z0-9_-]+$ and must not be 'auto' (case-insensitive)."
  }

  validation {
    condition = alltrue([
      for _, target in var.pinning_egress :
      (target.gw != null) != (target.dev != null)
    ])
    error_message = "Each pinning_egress entry must set exactly one of gw or dev."
  }
}

variable "pinning_ttl" {
  description = "Pinning TTL in seconds. Each UI/API visit refreshes the TTL for the calling source IP. Default: 24h."
  type        = number
  default     = 86400
}

variable "labels" {
  description = "Docker container labels applied to the workload service. Caller must supply at least 'garuda.frr.ospf.router_id'. Consumed by the sidecar operator for workload discovery and per-container FRR/PBR rendering."
  type        = map(string)

  validation {
    condition     = length(var.labels) > 0
    error_message = "labels must be non-empty; at minimum supply garuda.frr.ospf.router_id."
  }
}
