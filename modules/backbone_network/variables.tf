variable "name" {
  description = "Stable workload identifier used for the generated payload file."
  type        = string
}

variable "host_name" {
  description = "Inventory host that should receive this workload."
  type        = string
}

variable "backbone_dir" {
  description = "Directory on the target host where the backbone compose stack lives."
  type        = string
  default     = "/opt/garuda/backbone"
}

variable "backbone_subnet" {
  description = "CIDR subnet for the backbone bridge network."
  type        = string
}

variable "border_subnet" {
  description = "CIDR subnet for the border bridge network (internet-facing underlay)."
  type        = string
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

