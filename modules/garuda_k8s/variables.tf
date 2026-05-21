variable "namespace" {
  description = "Kubernetes namespace to create and configure."
  type        = string
  default     = "garuda"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid DNS-1123 label."
  }
}

variable "backbone_subnet" {
  description = "CIDR for the host-side `backbone` bridge IPAM, for example 10.42.0.0/24."
  type        = string

  validation {
    condition     = can(cidrhost(var.backbone_subnet, 0))
    error_message = "backbone_subnet must be a valid CIDR."
  }
}

variable "border_subnet" {
  description = "CIDR for the host-side `border` bridge IPAM, for example 10.43.0.0/24."
  type        = string

  validation {
    condition     = can(cidrhost(var.border_subnet, 0))
    error_message = "border_subnet must be a valid CIDR."
  }
}

variable "install_cni" {
  description = <<EOT
When true, the chart installs Multus and Whereabouts using k3s-native CNI
paths. Set to false if both are pre-installed by the cluster operator.
EOT
  type        = bool
  default     = true
}
