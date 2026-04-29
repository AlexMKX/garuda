variable "name" {
  description = "Stable workload identifier used for generated payload artifacts."
  type        = string
}

variable "host_name" {
  description = "Inventory host receiving the prerequisites workload."
  type        = string
}

variable "docker_firewall_backend" {
  description = "Docker firewall backend to configure on the host."
  type        = string
  default     = "nftables"
}

variable "docker_additional_config" {
  description = "Additional daemon.json keys merged into the Docker configuration."
  type        = any
  default     = {}
}

variable "reboot_on_change" {
  description = "Whether to reboot the host after Docker prerequisites change."
  type        = bool
  default     = true
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
