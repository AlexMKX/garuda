# modules/wireguard/routeros/bypass.tf
#
# Per-tunnel RouterOS WireGuard endpoint bypass.
# Creates a dedicated routing table, endpoint address-list entry,
# endpoint sync script, and scheduler for this tunnel.
#
# The caller is responsible for installing a default route into the
# bypass table (see output bypass_table_name in outputs.tf): the WAN
# interface name is environment-specific knowledge and belongs at the
# call-site, not in this generic module.

# Resolve the peer endpoint hostname at plan-time. Used purely as a
# launch_trigger discriminator below: when the IP first appears
# (null -> value on first apply) or changes between applies (DNS
# update), the endpoint sync script re-runs immediately rather than
# waiting up to one minute for the next scheduler tick.
data "dns_a_record_set" "wg_endpoint" {
  host = var.peer.endpoint_host
}

resource "routeros_routing_table" "wg_bypass" {
  name    = "wg-bypass-${var.config.tunnel_name}"
  fib     = true
  comment = "WG endpoint bypass for ${var.config.tunnel_name}"
}

resource "routeros_ip_firewall_addr_list" "endpoint" {
  list    = "wg-endpoints-${var.config.tunnel_name}"
  address = var.peer.endpoint_host
  comment = var.config.tunnel_name
}

resource "routeros_system_script" "wg_endpoint_sync" {
  name   = "wg-endpoint-sync-${var.config.tunnel_name}"
  policy = ["read", "write", "test"]
  source = templatefile("${path.module}/templates/wg_endpoint_sync.rsc.tftpl", {
    tunnel_name = var.config.tunnel_name
    list_name   = "wg-endpoints-${var.config.tunnel_name}"
    table_name  = routeros_routing_table.wg_bypass.name
  })
  comment = "Managed by wireguard/routeros for ${var.config.tunnel_name}"

  # Kick the sync script on apply whenever the resolved endpoint IP
  # set changes. On first apply the trigger transitions from "" to
  # sha1(addrs), so the rule is installed immediately; on subsequent
  # applies the trigger only changes if DNS results changed, avoiding
  # spurious re-runs.
  launch_trigger = sha1(jsonencode(data.dns_a_record_set.wg_endpoint.addrs))
}

resource "routeros_system_scheduler" "wg_endpoint_sync" {
  name     = "wg-endpoint-sync-${var.config.tunnel_name}"
  interval = "1m"
  on_event = "/system script run ${routeros_system_script.wg_endpoint_sync.name}"
  policy   = ["read", "write", "test"]
  comment  = "Managed by wireguard/routeros for ${var.config.tunnel_name}"
}
