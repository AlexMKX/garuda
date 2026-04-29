variable "host_name" {
  description = "Inventory host running the Firezone stack."
  type        = string
}

variable "firezone_dir" {
  description = "Directory where the Firezone compose project lives."
  type        = string
  default     = "/opt/garuda/firezone"
}

variable "server_url" {
  description = "Public URL at which Firezone is reachable; used to compute the default OIDC redirect URI."
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

variable "oidc_providers" {
  description = "Map of OIDC provider configurations to reconcile into Firezone."
  type = map(object({
    client_id              = string
    client_secret          = string
    label                  = optional(string)
    discovery_document_uri = optional(string)
    redirect_uri           = optional(string)
    response_type          = optional(string)
    scope                  = optional(string)
    auto_create_users      = optional(bool)
  }))
}
