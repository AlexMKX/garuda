variable "namespace" {
  description = "Existing Kubernetes namespace, sourced from module.garuda_k8s.namespace."
  type        = string
}

variable "name" {
  description = "Deployment name, for example 'wg-pt'."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid DNS-1123 label."
  }
}

variable "config" {
  description = "WireGuard local-peer configuration (matches modules/wireguard/linux config shape)."
  type = object({
    kernel_ifname = string
    private_key   = string
    address       = string
    subnet        = string
    listen_port   = optional(number)
    endpoint_host = optional(string)
  })
  sensitive = true

  validation {
    condition     = length(var.config.kernel_ifname) <= 15
    error_message = "config.kernel_ifname must be at most 15 characters (Linux IFNAMSIZ-1)."
  }
}

variable "peer" {
  description = <<EOT
WireGuard remote-peer configuration. `endpoint_host` is the bare
hostname or IP (without port); the chart joins it with
`endpoint_listen_port` to produce the `host:port` form the image
entrypoint expects.
EOT
  type = object({
    public_key           = string
    endpoint_host        = string
    endpoint_listen_port = number
    preshared_key        = optional(string)
    address              = string
  })
  sensitive = true
}

variable "allowed_nets" {
  description = "AllowedIPs entries for the peer (semantics identical to modules/wireguard/linux)."
  type        = list(string)
}

variable "table" {
  description = "WireGuard routing table directive. 'off' disables WireGuard-managed routes."
  type        = string
  default     = "off"
}

variable "persistent_keepalive" {
  description = "WireGuard PersistentKeepalive in seconds."
  type        = number
  default     = 25
}

variable "ospf" {
  description = <<EOT
Structured OSPF intent. When null, no FRR sidecar is rendered and the
Deployment runs WireGuard only. Interfaces participating in OSPF normally
include config.kernel_ifname so the hub-edge adjacency is established
over the WireGuard tunnel.
EOT
  type = object({
    router_id          = string
    area               = optional(string, "0.0.0.0")
    interfaces         = list(string)
    passive_interfaces = optional(list(string), [])
    default_originate  = optional(bool, false)
    redistribute       = optional(list(string), [])
    extra_frr_conf     = optional(string, "")
  })
  default = null

  validation {
    condition     = var.ospf == null || can(regex("^\\d+\\.\\d+\\.\\d+\\.\\d+$", var.ospf.router_id))
    error_message = "ospf.router_id must be an IPv4-formatted string."
  }

  validation {
    condition     = var.ospf == null || length(var.ospf.interfaces) > 0
    error_message = "ospf.interfaces must be non-empty when ospf is set."
  }

  validation {
    condition = (
      var.ospf == null
      || alltrue([for r in var.ospf.redistribute : contains(["connected", "kernel", "static"], r)])
    )
    error_message = "ospf.redistribute values must be subset of ['connected', 'kernel', 'static']."
  }
}

variable "nic_attach" {
  description = "Secondary networks the pod attaches to via Multus. Becomes the k8s.v1.cni.cncf.io/networks annotation."
  type        = list(string)
  default     = ["backbone", "border"]
}

variable "wireguard_image" {
  description = "Image reference for the wg container."
  type        = string
}

variable "frr_image" {
  description = "Image reference for the frr-sidecar container. Required when ospf != null; ignored otherwise."
  type        = string
  default     = ""
}
