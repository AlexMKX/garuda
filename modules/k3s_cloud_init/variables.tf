variable "k3s_version" {
  description = <<EOT
k3s version pin in the form vMAJOR.MINOR.PATCH+k3s<N>, e.g. "v1.30.5+k3s1".
null means use the stable channel (installer default).
EOT
  type        = string
  default     = null

  validation {
    condition     = var.k3s_version == null || can(regex("^v\\d+\\.\\d+\\.\\d+[+-]", var.k3s_version))
    error_message = "k3s_version must be a semver-like string starting with 'v', e.g. 'v1.30.5+k3s1'."
  }
}

variable "install_url" {
  description = "Base URL of the k3s installer script. Must be HTTPS."
  type        = string
  default     = "https://get.k3s.io"

  validation {
    condition     = can(regex("^https://", var.install_url))
    error_message = "install_url must start with https://"
  }
}

variable "extra_flags" {
  description = <<EOT
Extra flags appended to INSTALL_K3S_EXEC after the invariants
--tls-san=127.0.0.1 --https-listen-port=6443.
Each element must start with '--'.
EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for f in var.extra_flags : can(regex("^--", f))])
    error_message = "extra_flags entries must start with '--'."
  }
}

variable "extra_install_env" {
  description = <<EOT
Extra environment variables passed to the curl | sh - pipe.
Keys must match INSTALL_K3S_[A-Z_]+ (official installer env vars only).
Use this for INSTALL_K3S_CHANNEL, INSTALL_K3S_SKIP_START, etc.
EOT
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k, _ in var.extra_install_env : can(regex("^INSTALL_K3S_[A-Z_]+$", k))])
    error_message = "extra_install_env keys must match INSTALL_K3S_[A-Z_]+."
  }
}
