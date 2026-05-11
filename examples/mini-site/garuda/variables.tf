# --- environment ---
variable "env_slug" {
  description = "Short identifier for this environment (e.g. mini-site). Used as a prefix in resource names."
  type        = string
}

# --- Hub SSH connection bundle from infra/ (single object) ---
variable "connection_data_hub" {
  description = "SSH connection bundle for the hub host."
  sensitive   = true
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
}

# --- Edge SSH connection bundles from infra/ (map keyed by edge slug) ---
variable "connection_data_edges" {
  description = "Per-edge SSH connection bundles (keyed by edge slug)."
  sensitive   = true
  type = map(object({
    host                 = string
    user                 = string
    connection           = string
    network_os           = string
    password             = optional(string)
    ssh_private_key_file = optional(string)
    ssh_private_key      = optional(string)
    instance_token       = string
  }))
}

# --- Cloudflare record for the hub host (used as WG endpoint host) ---
variable "cloudflare_hub" {
  description = "Cloudflare record facts for hub (FQDN used as WireGuard endpoint)."
  type = object({
    zone_id     = string
    record_name = string
  })
}

# --- Cloudflare records for edges (keyed by edge slug) ---
variable "cloudflare_edges" {
  description = "Cloudflare record facts for edge hosts (keyed by edge slug)."
  type = map(object({
    zone_id     = string
    record_name = string
  }))
}

# --- RouterOS handles (same shape as inputs.tfvars.yaml::routeros) ---
variable "routeros" {
  description = "RouterOS connection handles from infra/."
  type = object({
    hostname         = string
    management_host  = string
    user             = string
    uplink_interface = string
  })
}

# --- RouterOS password (from SOPS via root.hcl, not from infra dependency) ---
variable "routeros_password" {
  type      = string
  sensitive = true
}

# --- Topology CIDRs (flat, non host-scoped) ---
variable "backbone_subnet"        { type = string }
variable "border_subnet"          { type = string }
variable "firezone_client_subnet" { type = string }

# --- Hub FQDN prefix + base domain (derives Firezone server_url) ---
variable "hub_fqdn_prefix" {
  description = "FQDN prefix for the hub host (prepended to base_domain)."
  type        = string
}

variable "base_domain" {
  description = "Base DNS domain for this topology (e.g. example.net)."
  type        = string
}

# --- Edges map (mirrors infra var.edges; consumed by garuda for WG config) ---
variable "edges" {
  description = "Map of edge hosts with WireGuard tunnel parameters."
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

# --- Hub-ros WireGuard tunnel (RouterOS ↔ hub) ---
variable "hub_ros" {
  description = "WireGuard tunnel parameters for the RouterOS ↔ hub tunnel."
  type = object({
    hub_cidr            = string
    routeros_cidr       = string
    listen_port         = number
    ospf_router_id_hub  = string
  })
}

# --- OSPF router ids for non-tunnel workloads ---
variable "ospf_router_ids" {
  type = object({
    firezone   = string
    ipt_server = string
  })
}

# --- Geo routing ---
variable "ipt_routes_germany_nets" { type = list(string) }

# --- Firezone (SOPS secrets + public OIDC client id) ---
variable "firezone_admin_password" {
  type      = string
  sensitive = true
}
variable "firezone_oidc_google_client_id" { type = string }
variable "firezone_oidc_google_client_secret" {
  type      = string
  sensitive = true
}

# --- Smoke client (pre-existing VPN client, not managed infra) ---
variable "smoke_client_firezone" {
  type = object({
    inventory_name  = string
    management_host = string
    user            = string
  })
}

# --- RouterOS LAN gateway (used for WG handshake bypass route) ---
variable "routeros_lan_gateway" {
  description = "Default gateway on the RouterOS LAN (used as nexthop for the WG handshake bypass route)."
  type        = string
}

# --- Workload container images ---
variable "wireguard_image" {
  description = "Docker image for the WireGuard container workload."
  type        = string
  default     = "ghcr.io/alexmkx/garuda-wireguard:latest"
}

variable "fz_firezone_image" {
  description = "Docker image for the Firezone container workload."
  type        = string
  default     = "ghcr.io/firezone/firezone:latest"
}

variable "ipt_server_image" {
  description = "Docker image for the ipt_server container workload."
  type        = string
  default     = "ghcr.io/alexmkx/garuda-ipt-server:latest"
}

variable "ipt_powerdns_image" {
  description = "Docker image for the PowerDNS container used by ipt_server."
  type        = string
  default     = "powerdns/pdns-recursor:latest"
}
