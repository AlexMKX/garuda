# Validates computed locals in garuda/ module.
# Covers ipt_routes, tunnel_facts, firezone_facts, smoke inventory shape.

mock_provider "routeros" {}
mock_provider "ansible" {}
mock_provider "wireguard" {}
mock_provider "local" {}
mock_provider "tls" {}
mock_provider "dns" {}

variables {
  env_slug = "mini-site"

  connection_data_hub = {
    host = "192.0.2.1", user = "operator", connection = "ssh", network_os = "linux",
    password = null, ssh_private_key_file = null, ssh_private_key = null,
    instance_token = "mock-hub",
  }

  connection_data_edges = {
    pt = {
      host = "192.0.2.2", user = "operator", connection = "ssh", network_os = "linux",
      password = null, ssh_private_key_file = null, ssh_private_key = null,
      instance_token = "mock-pt",
    }
    de = {
      host = "192.0.2.3", user = "operator", connection = "ssh", network_os = "linux",
      password = null, ssh_private_key_file = null, ssh_private_key = null,
      instance_token = "mock-de",
    }
  }

  cloudflare_hub   = { zone_id = "fixture-zone", record_name = "hub.example.net" }
  cloudflare_edges = {
    pt = { zone_id = "fixture-zone", record_name = "pt.example.net" }
    de = { zone_id = "fixture-zone", record_name = "de.example.net" }
  }

  routeros = {
    hostname = "routeros-example", management_host = "203.0.113.1",
    user = "admin", uplink_interface = "ether1"
  }
  routeros_password    = "admin"
  routeros_lan_gateway = "203.0.113.1"

  backbone_subnet        = "192.0.2.0/26"
  border_subnet          = "192.0.2.64/26"
  firezone_client_subnet = "198.51.100.128/25"

  hub_fqdn_prefix = "hub"
  base_domain     = "example.net"

  edges = {
    pt = {
      machine_type        = "e2-small"
      boot_disk_gb        = 20
      region              = "us-central1"
      zone                = "us-central1-a"
      fqdn_prefix         = "pt"
      hub_cidr            = "192.0.2.129/28"
      peer_cidr           = "192.0.2.130/28"
      listen_port         = 51820
      ospf_router_id_hub  = "198.51.100.20"
      ospf_router_id_peer = "198.51.100.23"
    }
    de = {
      machine_type        = "e2-small"
      boot_disk_gb        = 20
      region              = "europe-west3"
      zone                = "europe-west3-a"
      fqdn_prefix         = "de"
      hub_cidr            = "192.0.2.145/28"
      peer_cidr           = "192.0.2.146/28"
      listen_port         = 51821
      ospf_router_id_hub  = "198.51.100.30"
      ospf_router_id_peer = "198.51.100.33"
    }
  }

  hub_ros = {
    hub_cidr           = "192.0.2.161/28"
    routeros_cidr      = "192.0.2.162/28"
    listen_port        = 51822
    ospf_router_id_hub = "198.51.100.21"
  }

  ospf_router_ids = {
    firezone   = "198.51.100.22"
    ipt_server = "198.51.100.99"
  }

  ipt_routes_germany_nets = ["203.0.113.0/26", "203.0.113.64/26"]

  firezone_admin_password            = "test-password"
  firezone_oidc_google_client_id     = "test-id"
  firezone_oidc_google_client_secret = "test-secret"

  smoke_client_firezone = {
    inventory_name  = "fz-client-example"
    management_host = "203.0.113.200"
    user            = "operator"
  }
}

run "tunnel_facts_structure" {
  command = plan

  assert {
    condition     = length(keys(local.tunnel_facts)) == 2
    error_message = "tunnel_facts must have 2 entries (pt + de)"
  }

  assert {
    condition = (
      contains(keys(local.tunnel_facts), "pt") &&
      contains(keys(local.tunnel_facts), "de")
    )
    error_message = "tunnel_facts keys must be pt and de"
  }

  assert {
    condition = (
      contains(keys(local.tunnel_facts.pt.peers), "hub") &&
      contains(keys(local.tunnel_facts.pt.peers), "edge")
    )
    error_message = "tunnel_facts[pt] peer keys must be hub and edge"
  }
}

run "ipt_routes_two_entries" {
  command = plan

  assert {
    condition     = length(local.ipt_routes) == 2
    error_message = "ipt_routes must have exactly two action groups"
  }

  assert {
    condition     = length(local.ipt_routes[0].route) == 3
    error_message = "default action group must have three route members (pt gw, de gw, border dev)"
  }

  assert {
    # Terraform maps iterate in lexicographic key order: de < pt.
    condition = (
      local.ipt_routes[0].route[0].gw == "192.0.2.146" &&
      local.ipt_routes[0].route[1].gw == "192.0.2.130" &&
      local.ipt_routes[0].route[2].dev == "border"
    )
    error_message = "route order must be de gw -> pt gw -> border dev (lexicographic map iteration)"
  }
}

run "firezone_facts_server_url" {
  command = plan

  assert {
    condition     = local.firezone_facts.directory == "/opt/garuda/firezone"
    error_message = "firezone directory must be /opt/garuda/firezone"
  }

  assert {
    condition     = local.firezone_facts.server_url == "https://hub.example.net"
    error_message = "firezone server_url must derive from hub_fqdn_prefix + base_domain"
  }
}

run "regression_catchall_domain_in_ipt_routes" {
  command = plan

  assert {
    condition     = output.ipt_routes_count > 0
    error_message = "ipt_routes must not be empty"
  }
}

run "collection_root_resolves_to_examples_mini_site" {
  command = plan

  assert {
    condition     = endswith(local.collection_root, "/examples/mini-site")
    error_message = "local.collection_root must point at examples/mini-site/, got: ${local.collection_root}"
  }
}

run "ansible_smoke_inventory_shape" {
  command = plan

  assert {
    condition     = length(keys(output.ansible_smoke_inventory)) == 4
    error_message = "ansible_smoke_inventory must expose exactly 4 managed hosts (hub, pt, de, routeros)"
  }

  assert {
    condition     = contains(output.ansible_smoke_inventory.routeros.groups, "routeros")
    error_message = "routeros entry must be in 'routeros' group"
  }

  assert {
    condition     = contains(output.ansible_smoke_inventory.hub.groups, "linux_hosts")
    error_message = "hub must be in 'linux_hosts' group"
  }

  assert {
    condition = alltrue([
      for name, entry in output.ansible_smoke_inventory :
      contains(entry.groups, "smoke_all")
    ])
    error_message = "every host must be in 'smoke_all' group"
  }
}
