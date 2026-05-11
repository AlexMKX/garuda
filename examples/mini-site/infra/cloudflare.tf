data "cloudflare_zone" "main" {
  name = var.cloudflare.zone_name
}

# hub.<base_domain> → yc_hub public IPv4. Firezone server_url uses this FQDN.
resource "cloudflare_record" "hub" {
  zone_id = data.cloudflare_zone.main.id
  name    = "${var.hub_fqdn_prefix}.${var.base_domain}"
  type    = "A"
  content = module.yc_hub.public_ipv4
  ttl     = 300
  proxied = false
  comment = "garuda: mini-site hub/Firezone"
}

# <fqdn_prefix>.<base_domain> → GCP edge public IPv4.
# WireGuard endpoints on edges use this FQDN (symmetric DNS pattern).
resource "cloudflare_record" "edges" {
  for_each = var.edges

  zone_id = data.cloudflare_zone.main.id
  name    = "${each.value.fqdn_prefix}.${var.base_domain}"
  type    = "A"
  content = module.gcp_edges[each.key].public_ipv4
  ttl     = 300
  proxied = false
  comment = "garuda: mini-site edge/${each.key}"
}
