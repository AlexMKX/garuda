# modules/wireguard/linux/main.tf
#
# Linux WireGuard endpoint deployment.
# Flat payload — conditional rendering happens in the role's Jinja
# templates. Format concerns (host:port, comma-separated AllowedIPs)
# also live in templates.

locals {
  payload = {
    wireguard_interface_name   = var.config.kernel_ifname
    wireguard_address          = var.config.address
    wireguard_table            = var.table
    wireguard_private_key      = var.config.private_key
    wireguard_peer_public_key  = var.peer.public_key
    wireguard_peer_allowed_ips = concat(
      ["${split("/", var.peer.address)[0]}/32"],
      var.allowed_nets,
    )
    wireguard_labels   = var.labels
    wireguard_nic_attach = var.nic_attach

    # Optional fields: null/empty signals "not set"; templates use
    # truthy guards (`{% if X %}`) instead of `is defined`.
    wireguard_listen_port               = try(tostring(var.config.listen_port), "")
    wireguard_public_endpoint           = try(trimspace(var.config.endpoint_host), "")
    wireguard_peer_preshared_key        = trimspace(var.config.preshared_key)
    wireguard_peer_endpoint_host        = try(trimspace(var.peer.endpoint_host), "")
    wireguard_peer_listen_port          = try(tostring(var.peer.listen_port), "")
    wireguard_peer_persistent_keepalive = try(tostring(var.persistent_keepalive), "")
    wireguard_post_up                   = trimspace(var.post_up)
    wireguard_pre_down                  = trimspace(var.pre_down)
  }
}

module "linux_apply" {
  source = "../../linux_apply"

  host_name     = var.host_name
  workload_kind = "wireguard"
  payload       = local.payload

  connection_data = var.connection_data
  extra_hostvars  = var.extra_hostvars
}
