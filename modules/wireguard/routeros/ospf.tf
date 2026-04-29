# modules/wireguard/routeros/ospf.tf
#
# Per-tunnel RouterOS OSPF stack.
# Creates one dedicated OSPF instance and area per tunnel.
# Announces all connected prefixes into OSPF (redistribute=connected).

resource "routeros_routing_ospf_instance" "this" {
  name         = "garuda-${var.config.tunnel_name}"
  router_id    = var.router_id
  redistribute = ["connected"]
  comment      = "garuda-${var.config.tunnel_name}"
}

resource "routeros_routing_ospf_area" "this" {
  name     = "garuda-${var.config.tunnel_name}"
  instance = routeros_routing_ospf_instance.this.name
  area_id  = var.ospf_area
  comment  = "garuda-${var.config.tunnel_name}"
}

resource "routeros_routing_ospf_interface_template" "this" {
  area       = routeros_routing_ospf_area.this.name
  interfaces = [var.config.tunnel_name]
  type       = "ptp"
  comment    = "garuda-${var.config.tunnel_name}"

  # Match the FRR sidecar timers (backbone_network role default: hello=5, dead=15).
  # OSPF hello-interval and dead-interval MUST be identical on both sides of
  # a p2p link; mismatched timers silently prevent adjacency formation.
  hello_interval = "5s"
  dead_interval  = "15s"
}
