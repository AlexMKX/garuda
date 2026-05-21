locals {
  # --- Ansible inventory host names (transient, derived from env_slug). ---
  # hub: fixed key; edges: keyed by edge slug.
  host_names = merge(
    { hub = "hub-${var.env_slug}" },
    { for k, _ in var.edges : k => "${k}-${var.env_slug}" }
  )

  # --- Firezone FQDN derived from hub_fqdn_prefix + base_domain. ---
  firezone_fqdn = "${var.hub_fqdn_prefix}.${var.base_domain}"

  # --- Tunnel facts: one entry per edge (from var.edges map). ---
  # hub-side: hub_cidr, ospf_router_id_hub
  # edge-side: peer_cidr, ospf_router_id_peer
  tunnel_facts = {
    for k, e in var.edges : k => {
      subnet_cidr = "${cidrhost(e.hub_cidr, 0)}/${split("/", e.hub_cidr)[1]}"
      peers = {
        hub  = { cidr = e.hub_cidr, listen_port = e.listen_port }
        edge = { cidr = e.peer_cidr, listen_port = e.listen_port }
      }
      labels = {
        hub = {
          "garuda.frr.ospf.enabled"           = "true"
          "garuda.frr.ospf.router_id"         = e.ospf_router_id_hub
          "garuda.frr.ospf.interfaces"        = "wg-${replace(k, "_", "-")}"
          "garuda.frr.ospf.active_interfaces" = "wg-${replace(k, "_", "-")}"
          "garuda.frr.ospf.default_originate" = "false"
        }
        edge = {
          "garuda.frr.ospf.enabled"           = "true"
          "garuda.frr.ospf.router_id"         = e.ospf_router_id_peer
          "garuda.frr.ospf.interfaces"        = "wg-${replace(k, "_", "-")}"
          "garuda.frr.ospf.active_interfaces" = "wg-${replace(k, "_", "-")}"
          "garuda.frr.ospf.default_originate" = "true"
        }
      }
    }
  }

  wireguard_kube_inputs = {
    for k, e in var.edges : k => {
      config = {
        kernel_ifname = module.wireguard_tunnel[k].peers["edge"].kernel_ifname
        private_key   = module.wireguard_tunnel[k].peers["edge"].private_key
        address       = module.wireguard_tunnel[k].peers["edge"].address
        subnet        = local.tunnel_facts[k].subnet_cidr
        listen_port   = module.wireguard_tunnel[k].peers["edge"].listen_port
        endpoint_host = module.wireguard_tunnel[k].peers["edge"].endpoint_host
      }
      peer = {
        public_key           = module.wireguard_tunnel[k].peers["core"].public_key
        endpoint_host        = module.wireguard_tunnel[k].peers["core"].endpoint_host
        endpoint_listen_port = module.wireguard_tunnel[k].peers["core"].listen_port
        preshared_key        = module.wireguard_tunnel[k].peers["core"].preshared_key
        address              = module.wireguard_tunnel[k].peers["core"].address
      }
      allowed_nets = ["0.0.0.0/0", "224.0.0.0/4"]
      ospf = {
        router_id          = e.ospf_router_id_peer
        area               = "0.0.0.0"
        interfaces         = [module.wireguard_tunnel[k].peers["edge"].kernel_ifname]
        passive_interfaces = []
        default_originate  = true
        redistribute       = []
        extra_frr_conf     = ""
      }
    }
  }

  # --- Hub-ros tunnel facts (RouterOS ↔ hub). ---
  hub_ros_facts = {
    subnet_cidr = "${cidrhost(var.hub_ros.hub_cidr, 0)}/${split("/", var.hub_ros.hub_cidr)[1]}"
    peers = {
      hub      = { cidr = var.hub_ros.hub_cidr, listen_port = var.hub_ros.listen_port }
      routeros = { cidr = var.hub_ros.routeros_cidr, listen_port = var.hub_ros.listen_port }
    }
    labels = {
      hub = {
        "garuda.frr.ospf.enabled"           = "true"
        "garuda.frr.ospf.router_id"         = var.hub_ros.ospf_router_id_hub
        "garuda.frr.ospf.interfaces"        = "wg-hub-ros"
        "garuda.frr.ospf.active_interfaces" = "wg-hub-ros"
        "garuda.frr.ospf.default_originate" = "false"
        "garuda.transit.interfaces"         = "wg-hub-ros"
      }
    }
  }

  # --- Firezone workload facts. ---
  firezone_facts = {
    directory      = "/opt/garuda/firezone"
    server_url     = "https://${local.firezone_fqdn}"
    admin_password = var.firezone_admin_password
    client_subnet  = var.firezone_client_subnet
    labels = {
      "garuda.frr.ospf.enabled"           = "true"
      "garuda.frr.ospf.router_id"         = var.ospf_router_ids.firezone
      "garuda.frr.ospf.interfaces"        = "wg-firezone"
      "garuda.frr.ospf.active_interfaces" = ""
      "garuda.frr.ospf.default_originate" = "false"
      "garuda.transit.interfaces"         = "wg-firezone"
    }
  }

  # --- ipt_server facts. ---
  ipt_server_facts = {
    directory     = "/opt/garuda/ipt_server"
    frr_router_id = var.ospf_router_ids.ipt_server
  }

  # --- ipt_server pinning_egress: one entry per edge (gw = peer address). ---
  pinning_egress = {
    for k, e in var.edges : k => { gw = split("/", e.peer_cidr)[0] }
  }

  # --- ipt_routes: primary → fallback. ---
  # Egress order derived from var.edges iteration (lexicographic by key): de → pt → border.
  # To change routing priority, reorder var.edges keys (rename to control sort order).
  ipt_routes = [
    {
      route = concat(
        [for k, e in var.edges : { gw = split("/", e.peer_cidr)[0] }],
        [{ dev = "border" }],
      )
      rules = concat(
        [
          ".*",
          "0.0.0.0/0",
        ],
        var.ipt_routes_germany_nets,
      )
    },
    {
      route = [{ dev = "border" }]
      rules = [
        "RU",
        ".*\\.ru",
      ]
    },
  ]

  # --- Edge kubeconfig + endpoint, decoded from garuda-tunnel state. ---
  # See variable "tunnel_path" in variables.tf. The shape of the JSON is
  # documented in
  # https://github.com/AlexMKX/garuda-tunnel/blob/main/README.md
  # under "Output reference".
  tunnel = jsondecode(file(var.tunnel_path))

  edges_kubeconfig = {
    for k, conn in local.tunnel.connections :
    k => yamldecode(base64decode(conn.fetch_files.kubeconfig.content_b64))
  }

  edges_endpoint = {
    for k, conn in local.tunnel.connections :
    k => "https://127.0.0.1:${conn.ports["k3s"]}"
  }
}
