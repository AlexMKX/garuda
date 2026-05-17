# --- environment ---
variable "env_slug" {
  description = "Short identifier for this environment (e.g. mini-site). Used as a prefix in resource names."
  type        = string
}

# --- Yandex Cloud (public handles) ---
variable "yc" {
  description = "Yandex Cloud identifiers and networking handles."
  type = object({
    cloud_id          = string
    folder_id         = string
    zone              = string
    network_id        = string
    primary_subnet_id = string
  })
}

# --- Yandex Cloud service-account key (SOPS secret, merged by root.hcl) ---
variable "yc_service_account_key_json" {
  type      = string
  sensitive = true
}

# --- GCP (public handle) ---
variable "gcp" {
  description = "Google Cloud project handle. Per-VM region/zone live on host objects."
  type = object({
    project_id = string
  })
}

# --- GCP service-account credentials (SOPS secret) ---
variable "gcp_credentials_json" {
  type      = string
  sensitive = true
}

# --- Cloudflare (public handle) ---
variable "cloudflare" {
  description = "Cloudflare zone handle."
  type = object({
    zone_name = string
  })
}

# --- Cloudflare API token (SOPS secret) ---
variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

# --- RouterOS connection (pre-existing physical device) ---
variable "routeros" {
  description = "RouterOS connection handles used for infra bootstrap and provider setup."
  type = object({
    hostname         = string
    management_host  = string
    user             = string
    uplink_interface = string
  })
}

# --- RouterOS password (SOPS secret) ---
variable "routeros_password" {
  type      = string
  sensitive = true
}

# --- Hub host (YC-managed; runs Firezone + ipt_server) ---
variable "hub" {
  description = "Config for the YC-managed hub host."
  type = object({
    cores            = number
    memory_gb        = number
    boot_disk_gb     = number
    data_disk_gb     = number
    existing_disk_id = optional(string)
  })
}

# --- Edges map (GCP-managed, keyed by slug: pt, de, …) ---
variable "edges" {
  description = "Map of GCP edge hosts. Each entry provides compute sizing and WireGuard tunnel parameters."
  type = map(object({
    machine_type        = string
    boot_disk_gb        = number
    region              = string
    zone                = string
    fqdn_prefix         = string
    hub_cidr            = string
    peer_cidr           = string
    listen_port         = number
    ospf_router_id_hub  = string
    ospf_router_id_peer = string
  }))
}

# --- Operator SSH keys appended to every managed VM ---
variable "operator_ssh_keys" {
  type        = list(string)
  description = <<EOT
Operator/extra SSH keys passed verbatim into metadata['ssh-keys'] on every
managed VM. Each entry MUST be in `username:keytype keydata [comment]`
format (e.g. `operator:ssh-ed25519 AAAA... operator@workstation`). The cloud guest
agent on the VM creates the user on first contact and writes the key into
that user's ~/.ssh/authorized_keys. See
garuda-repo/modules/{yc,gcp}_compute_host/README.md for details.
EOT
  default     = []
}

# --- DNS ---
variable "hub_fqdn_prefix" {
  description = "FQDN prefix for the hub host (prepended to base_domain)."
  type        = string
}

variable "base_domain" {
  description = "Base DNS domain for this topology (e.g. example.net)."
  type        = string
}

