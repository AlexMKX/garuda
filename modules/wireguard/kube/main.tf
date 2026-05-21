locals {
  ospf_values = var.ospf == null ? null : {
    router_id          = var.ospf.router_id
    area               = var.ospf.area
    interfaces         = var.ospf.interfaces
    passive_interfaces = var.ospf.passive_interfaces
    default_originate  = var.ospf.default_originate
    redistribute       = var.ospf.redistribute
    extra_frr_conf     = var.ospf.extra_frr_conf
  }
}

resource "helm_release" "wireguard" {
  name             = var.name
  namespace        = var.namespace
  create_namespace = false
  chart            = "${path.module}/charts/wireguard"

  values = [
    yamlencode({
      namespace            = var.namespace
      name                 = var.name
      config               = var.config
      peer                 = var.peer
      allowed_nets         = var.allowed_nets
      table                = var.table
      persistent_keepalive = var.persistent_keepalive
      nic_attach           = var.nic_attach
      images = {
        wireguard = var.wireguard_image
        frr       = var.frr_image
      }
      ospf = local.ospf_values
    })
  ]
}
