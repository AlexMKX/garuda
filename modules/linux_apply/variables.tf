variable "host_name" {
  description = "Inventory host that should receive this workload apply or cleanup."
  type        = string
}

variable "workload_kind" {
  description = "Workload discriminator consumed by the shared Ansible executor playbook."
  type        = string
}

variable "payload" {
  description = "Role-native payload rendered to YAML and passed to the shared Ansible executor."
  type        = any
}

variable "connection_data" {
  description = "Normalized transport/auth contract for the target host. instance_token is an opaque invalidation discriminator: any change forces ansible re-execution; by convention populated with the cloud instance id."
  type = object({
    host                 = string
    user                 = string
    connection           = string
    network_os           = string
    password             = optional(string)
    ssh_private_key_file = optional(string)
    ssh_private_key      = optional(string)
    instance_token       = string
  })
  sensitive = true

  validation {
    condition = !(
      try(var.connection_data.ssh_private_key, null) != null &&
      try(var.connection_data.ssh_private_key_file, null) != null
    )
    error_message = "connection_data: ssh_private_key and ssh_private_key_file are mutually exclusive — provide at most one."
  }
}

variable "extra_hostvars" {
  description = "Optional additional hostvars merged into module-local inventory vars."
  type        = map(any)
  default     = {}
}

variable "destroy_payload_override" {
  description = "Optional payload used only for destroy-time execution."
  type        = any
  default     = null
}
