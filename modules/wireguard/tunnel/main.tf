# modules/wireguard/tunnel/main.tf
#
# Canonical WireGuard tunnel data: key generation and normalized peer output.
# This module owns no deployment logic and no routing/OSPF/FRR concerns.

locals {
  # kernel_ifname: Linux WireGuard kernel interface name. Raw,
  # underscores normalized to hyphens, NO env_slug, capped by caller
  # discipline to ≤15 chars (Linux IFNAMSIZ-1). Consumed by
  # wireguard/linux as the literal device name.
  kernel_ifname = replace(var.name, "_", "-")

  # tunnel_name: identifier used by wireguard/routeros for ALL its
  # resource names (interface, OSPF instance/area, bypass routing
  # table, address-list, scheduler, script, FW filter/mangle).
  # Embedding env_slug here keeps two stacks sharing a RouterOS
  # device from collision on these names.
  tunnel_name = "${var.env_slug}-${local.kernel_ifname}"
}

resource "wireguard_asymmetric_key" "peer" {
  for_each = var.peers
}

resource "wireguard_preshared_key" "this" {}
