# --- Linux host prerequisites (docker, ip_forward, base config) ---

module "linux_host_prerequisites_hub" {
  source = "../../../roles/linux_host_prerequisites/terraform"

  host_name = local.host_names.hub
  arguments = {
    docker_daemon_config = {
      "log-driver" = "json-file"
      "log-opts"   = { "max-file" = "5", "max-size" = "100m" }
      "ip-forward" = true
    }
  }

  connection_data = var.connection_data_hub
}

module "linux_host_prerequisites_edges" {
  for_each = var.edges

  source = "../../../roles/linux_host_prerequisites/terraform"

  host_name = local.host_names[each.key]
  arguments = {
    docker_daemon_config = {
      "log-driver" = "json-file"
      "log-opts"   = { "max-file" = "5", "max-size" = "100m" }
      "ip-forward" = true
    }
  }

  connection_data = var.connection_data_edges[each.key]
}

# --- Backbone network: hub (single) ---

module "backbone_hub" {
  source = "../../../roles/backbone_network/terraform"

  depends_on = [module.linux_host_prerequisites_hub]

  host_name = local.host_names.hub
  arguments = {
    backbone_dir    = "/opt/garuda/backbone"
    backbone_subnet = var.backbone_subnet
    border_subnet   = var.border_subnet
  }

  connection_data = var.connection_data_hub
}

# --- Backbone networks: edges (for_each) ---

module "backbone_edges" {
  for_each = var.edges

  source = "../../../roles/backbone_network/terraform"

  depends_on = [module.linux_host_prerequisites_edges]

  host_name = local.host_names[each.key]
  arguments = {
    backbone_dir    = "/opt/garuda/backbone"
    backbone_subnet = var.backbone_subnet
    border_subnet   = var.border_subnet
  }

  connection_data = var.connection_data_edges[each.key]
}

# --- WireGuard tunnel key-pairs (one tunnel object per edge) ---

module "wireguard_tunnel" {
  for_each = var.edges

  source = "./modules/wireguard/tunnel"

  name     = "wg_${each.key}"
  env_slug = var.env_slug
  subnet   = local.tunnel_facts[each.key].subnet_cidr
  peers = {
    core = {
      address       = each.value.hub_cidr
      listen_port   = each.value.listen_port
      endpoint_host = var.cloudflare_hub.record_name
    }
    edge = {
      address       = each.value.peer_cidr
      listen_port   = each.value.listen_port
      endpoint_host = var.cloudflare_edges[each.key].record_name
    }
  }
}

# --- WireGuard Linux modules: hub side (one per edge) ---

module "wireguard_linux_hub" {
  for_each = var.edges

  source = "../../../roles/wireguard/terraform"

  depends_on = [module.backbone_hub]

  host_name = local.host_names.hub
  arguments = {
    wireguard_interface_name            = module.wireguard_tunnel[each.key].peers["core"].kernel_ifname
    wireguard_tunnel_name               = module.wireguard_tunnel[each.key].peers["core"].tunnel_name
    wireguard_address                   = module.wireguard_tunnel[each.key].peers["core"].address
    wireguard_private_key               = module.wireguard_tunnel[each.key].peers["core"].private_key
    wireguard_listen_port               = module.wireguard_tunnel[each.key].peers["core"].listen_port
    wireguard_public_endpoint           = module.wireguard_tunnel[each.key].peers["core"].endpoint_host
    wireguard_peer_public_key           = module.wireguard_tunnel[each.key].peers["edge"].public_key
    wireguard_peer_address              = module.wireguard_tunnel[each.key].peers["edge"].address
    wireguard_peer_endpoint_host        = module.wireguard_tunnel[each.key].peers["edge"].endpoint_host
    wireguard_peer_listen_port          = module.wireguard_tunnel[each.key].peers["edge"].listen_port
    wireguard_peer_preshared_key        = module.wireguard_tunnel[each.key].peers["edge"].preshared_key
    wireguard_peer_persistent_keepalive = 25
    wireguard_table                     = "off"
    wireguard_allowed_nets              = ["0.0.0.0/0", "224.0.0.0/4"]
    wireguard_labels                    = merge(local.tunnel_facts[each.key].labels.hub, { "garuda.operator-scope" = "backbone_network" })
    wireguard_nic_attach                = ["backbone", "border"]
    wireguard_image                     = var.wireguard_image
    wireguard_post_up                   = null
    wireguard_pre_down                  = null
  }

  connection_data = var.connection_data_hub
}

# --- WireGuard Linux modules: edge side (one per edge) ---

module "wireguard_linux_edges" {
  for_each = var.edges

  source = "../../../roles/wireguard/terraform"

  depends_on = [module.backbone_edges]

  host_name = local.host_names[each.key]
  arguments = {
    wireguard_interface_name            = module.wireguard_tunnel[each.key].peers["edge"].kernel_ifname
    wireguard_tunnel_name               = module.wireguard_tunnel[each.key].peers["edge"].tunnel_name
    wireguard_address                   = module.wireguard_tunnel[each.key].peers["edge"].address
    wireguard_private_key               = module.wireguard_tunnel[each.key].peers["edge"].private_key
    wireguard_listen_port               = module.wireguard_tunnel[each.key].peers["edge"].listen_port
    wireguard_public_endpoint           = module.wireguard_tunnel[each.key].peers["edge"].endpoint_host
    wireguard_peer_public_key           = module.wireguard_tunnel[each.key].peers["core"].public_key
    wireguard_peer_address              = module.wireguard_tunnel[each.key].peers["core"].address
    wireguard_peer_endpoint_host        = module.wireguard_tunnel[each.key].peers["core"].endpoint_host
    wireguard_peer_listen_port          = module.wireguard_tunnel[each.key].peers["core"].listen_port
    wireguard_peer_preshared_key        = module.wireguard_tunnel[each.key].peers["core"].preshared_key
    wireguard_peer_persistent_keepalive = 25
    wireguard_table                     = "off"
    wireguard_allowed_nets              = ["0.0.0.0/0", "224.0.0.0/4"]
    wireguard_labels                    = merge(local.tunnel_facts[each.key].labels.edge, { "garuda.operator-scope" = "backbone_network" })
    wireguard_nic_attach                = ["backbone", "border"]
    wireguard_image                     = var.wireguard_image
    wireguard_post_up                   = null
    wireguard_pre_down                  = null
  }

  connection_data = var.connection_data_edges[each.key]
}

# --- WireGuard tunnel key-pair for hub-ros (RouterOS <-> hub) ---

module "wireguard_tunnel_hub_ros" {
  source = "./modules/wireguard/tunnel"

  name     = "wg_hub_ros"
  env_slug = var.env_slug
  subnet   = local.hub_ros_facts.subnet_cidr
  peers = {
    core = {
      address       = var.hub_ros.hub_cidr
      listen_port   = var.hub_ros.listen_port
      endpoint_host = var.cloudflare_hub.record_name
    }
    edge = {
      address     = var.hub_ros.routeros_cidr
      listen_port = var.hub_ros.listen_port
    }
  }
}

# --- WireGuard Linux module: hub side of hub-ros tunnel ---

module "wireguard_linux_hub_ros" {
  source = "../../../roles/wireguard/terraform"

  depends_on = [module.backbone_hub]

  host_name = local.host_names.hub
  arguments = {
    wireguard_interface_name            = module.wireguard_tunnel_hub_ros.peers["core"].kernel_ifname
    wireguard_tunnel_name               = module.wireguard_tunnel_hub_ros.peers["core"].tunnel_name
    wireguard_address                   = module.wireguard_tunnel_hub_ros.peers["core"].address
    wireguard_private_key               = module.wireguard_tunnel_hub_ros.peers["core"].private_key
    wireguard_listen_port               = module.wireguard_tunnel_hub_ros.peers["core"].listen_port
    wireguard_public_endpoint           = module.wireguard_tunnel_hub_ros.peers["core"].endpoint_host
    wireguard_peer_public_key           = module.wireguard_tunnel_hub_ros.peers["edge"].public_key
    wireguard_peer_address              = module.wireguard_tunnel_hub_ros.peers["edge"].address
    wireguard_peer_endpoint_host        = module.wireguard_tunnel_hub_ros.peers["edge"].endpoint_host
    wireguard_peer_listen_port          = module.wireguard_tunnel_hub_ros.peers["edge"].listen_port
    wireguard_peer_preshared_key        = module.wireguard_tunnel_hub_ros.peers["edge"].preshared_key
    wireguard_peer_persistent_keepalive = 25
    wireguard_table                     = "off"
    wireguard_allowed_nets              = ["0.0.0.0/0", "224.0.0.0/4"]
    wireguard_labels                    = merge(local.hub_ros_facts.labels.hub, { "garuda.operator-scope" = "backbone_network" })
    # Attach to backbone so the ospf-injector running on this host
    # discovers the tunnel as a transit consumer (matches_target Rule 3
    # requires the backbone_network attachment) and creates an FRR
    # sidecar. Without this attachment, RouterOS has no OSPF peer on
    # the hub side and no adjacency forms.
    wireguard_nic_attach                = ["backbone"]
    wireguard_image                     = var.wireguard_image
    wireguard_post_up                   = null
    wireguard_pre_down                  = null
  }

  connection_data = var.connection_data_hub
}

# --- WireGuard RouterOS module: RouterOS side of hub-ros tunnel ---

module "wireguard_routeros_hub_ros" {
  source = "./modules/wireguard/routeros"

  hostname       = var.routeros.hostname
  config         = module.wireguard_tunnel_hub_ros.peers["edge"]
  peer           = module.wireguard_tunnel_hub_ros.peers["core"]
  subnet         = local.hub_ros_facts.subnet_cidr
  allowed_nets   = ["0.0.0.0/0", "224.0.0.0/4"]
  interface_list = "LAN"

  router_id = split("/", var.hub_ros.routeros_cidr)[0]
  ospf_area = "0.0.0.0"
}

# Default route into the hub-ros bypass routing table.  Without this route,
# the per-tunnel PBR rule installed by the endpoint sync script has no nexthop
# and the WG handshake packets are dropped.
resource "routeros_ip_route" "hub_ros_bypass_default" {
  dst_address   = "0.0.0.0/0"
  gateway       = var.routeros_lan_gateway
  routing_table = module.wireguard_routeros_hub_ros.bypass_table_name
  comment       = "garuda: WG handshake bypass default for wg_hub_ros"
}

# --- RouterOS masquerade for VPN -> LAN traffic ---

resource "routeros_ip_firewall_nat" "hub_ros_masquerade" {
  chain         = "srcnat"
  action        = "masquerade"
  out_interface = var.routeros.uplink_interface
  comment       = "garuda: masquerade VPN -> LAN"

  depends_on = [module.wireguard_routeros_hub_ros]
}

# --- Firezone ---

module "firezone" {
  source = "../../../roles/firezone/terraform"

  depends_on = [module.backbone_hub]

  host_name = local.host_names.hub
  arguments = {
    fz_firezone_dir            = local.firezone_facts.directory
    fz_firezone_image          = var.fz_firezone_image
    firezone_main_compose_file = "${local.firezone_facts.directory}/docker-compose.yml"
    fz_server_url              = local.firezone_facts.server_url
    fz_admin_password          = local.firezone_facts.admin_password
    fz_client_subnet           = local.firezone_facts.client_subnet
    fz_mgmt_subnet             = null
    firezone_labels            = merge(local.firezone_facts.labels, { "garuda.operator-scope" = "backbone_network" })
  }

  connection_data = var.connection_data_hub
}

# --- ipt_server (geo routing + transit provider) ---

module "ipt_server" {
  source = "../../../roles/ipt_server/terraform"

  host_name = local.host_names.hub
  arguments = {
    ipt_server_dir     = local.ipt_server_facts.directory
    ipt_server_image   = var.ipt_server_image
    ipt_powerdns_image = var.ipt_powerdns_image
    ipt_routes         = local.ipt_routes
    ipt_nic_attach     = ["border"]
    # PBR/DNS classification interfaces — the ipt_server container reads
    # this list and inserts iifname { ... } guards into its nftables ruleset.
    # An empty list renders as `iifname { }` which is a syntax error and
    # crashes the container at startup, so the list MUST be non-empty.
    ipt_interfaces = ["backbone"]
    ipt_server_labels = {
      "garuda.frr.ospf.router_id" = local.ipt_server_facts.frr_router_id
    }
    ipt_pinning_egress = local.pinning_egress
  }

  connection_data = var.connection_data_hub

  depends_on = [module.backbone_hub]
}
