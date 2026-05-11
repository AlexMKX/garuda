# Hub SSH connection bundle (single object).
output "connection_data_hub" {
  description = "SSH connection bundle for the hub host."
  sensitive   = true
  value       = module.yc_hub.connection_data
}

# Edge SSH connection bundles (map keyed by edge slug: pt, de, …).
output "connection_data_edges" {
  description = "Per-edge SSH connection bundles (keyed by edge slug)."
  sensitive   = true
  value       = { for k, m in module.gcp_edges : k => m.connection_data }
}

# Cloudflare record for the hub host (used by garuda/ as WG endpoint host).
output "cloudflare_hub" {
  description = "Cloudflare record for hub (FQDN used as WG endpoint host)."
  value = {
    zone_id     = data.cloudflare_zone.main.id
    record_name = cloudflare_record.hub.hostname
  }
}

# Cloudflare records for edges (keyed by edge slug).
output "cloudflare_edges" {
  description = "Cloudflare records for edge hosts (keyed by edge slug)."
  value = {
    for k, r in cloudflare_record.edges : k => {
      zone_id     = data.cloudflare_zone.main.id
      record_name = r.hostname
    }
  }
}

# RouterOS handles pulled from variables (not Terraform-managed ingress).
# Kept here so garuda/ consumes one "infra facts" surface via dependency.
output "routeros" {
  description = "RouterOS connection handles."
  value       = var.routeros
}
