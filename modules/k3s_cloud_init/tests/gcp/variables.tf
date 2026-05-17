variable "env_slug" {
  description = "Environment slug; embedded in instance name, hostname, and disk name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.env_slug))
    error_message = "env_slug must be 2+ chars, lower-case alphanumerics and hyphens, no leading/trailing hyphen."
  }
}

variable "gcp" {
  description = "Google Cloud substrate."
  type = object({
    project_id = string
    region     = string
    zone       = string
    network    = string
    subnetwork = string
  })
}

variable "ssh_keys" {
  description = "Operator/extra SSH keys (user:keytype keydata [comment]). Pass [] for the module-managed admin key only."
  type        = list(string)
  nullable    = false
}

variable "disk_size_gb" {
  description = "Size in GiB for the k3s data disk (/var/lib/rancher)."
  type        = number
  default     = 20
}

variable "k3s_version" {
  description = "Optional k3s version pin (e.g. v1.30.5+k3s1). null = stable channel."
  type        = string
  default     = null
}
