output "peers" {
  description = <<EOT
Canonical peer config map keyed by caller-chosen peer key (e.g. core/edge).

Two name fields are exposed deliberately:
- `tunnel_name`: env-prefixed (`<env_slug>-<name>`), consumed by
  wireguard/routeros for resource naming. Globally unique across
  garuda stacks sharing a RouterOS device.
- `kernel_ifname`: raw (`<name>` with underscores hyphenated), consumed
  by wireguard/linux as the Linux kernel interface name. Bounded by
  IFNAMSIZ=15. NOT env-scoped — Linux interface namespace is per-host.
EOT
  value = {
    for peer_key, peer in var.peers : peer_key => {
      tunnel_name   = local.tunnel_name
      kernel_ifname = local.kernel_ifname
      subnet        = var.subnet
      address       = peer.address
      listen_port   = peer.listen_port
      endpoint_host = peer.endpoint_host
      private_key   = wireguard_asymmetric_key.peer[peer_key].private_key
      public_key    = wireguard_asymmetric_key.peer[peer_key].public_key
      preshared_key = wireguard_preshared_key.this.key
    }
  }
  sensitive = true
}
