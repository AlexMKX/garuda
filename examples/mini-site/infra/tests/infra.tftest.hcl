# Tests for examples/mini-site/infra/ unit.
# Validates RouterOS bootstrap resources, connection_data output shape,
# and Cloudflare DNS record names after the edges-foreach refactor.
# Uses mock providers — no real cloud credentials needed.

mock_provider "yandex" {}
mock_provider "google" {}
mock_provider "cloudflare" {}
mock_provider "routeros" {}
mock_provider "tls" {}
mock_provider "local" {}

variables {
  env_slug = "mini-site"

  yc = {
    cloud_id          = "cloud-example"
    folder_id         = "folder-example"
    zone              = "ru-central1-d"
    network_id        = "net-example"
    primary_subnet_id = "subnet-example"
  }
  yc_service_account_key_json = "{}"

  hub = {
    cores            = 2
    memory_gb        = 4
    boot_disk_gb     = 20
    data_disk_gb     = 20
    existing_disk_id = null
  }

  gcp = {
    project_id = "my-gcp-project"
  }
  gcp_credentials_json = "{}"

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

  cloudflare = {
    zone_name = "example.net"
  }
  cloudflare_api_token = "fixture"

  hub_fqdn_prefix = "hub"
  base_domain     = "example.net"

  routeros = {
    hostname         = "routeros-example"
    management_host  = "203.0.113.1"
    user             = "admin"
    uplink_interface = "ether1"
  }
  routeros_password = "admin"

  operator_ssh_keys = ["operator:ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIexample operator@example"]
}

run "routeros_bootstrap_resources_planned" {
  command = plan

  assert {
    condition     = routeros_interface_list.lan.name == "LAN"
    error_message = "routeros_interface_list.lan name must be LAN"
  }

  assert {
    condition     = length(routeros_ip_dns.this.servers) == 2
    error_message = "routeros_ip_dns must have two DNS servers"
  }
}

run "connection_data_output_has_all_hosts" {
  command = plan

  assert {
    condition     = output.connection_data_hub != null
    error_message = "connection_data_hub must be a single non-null object"
  }

  assert {
    condition     = contains(keys(output.connection_data_edges), "pt")
    error_message = "connection_data_edges must include pt"
  }

  assert {
    condition     = contains(keys(output.connection_data_edges), "de")
    error_message = "connection_data_edges must include de"
  }

  assert {
    condition     = output.routeros.hostname == var.routeros.hostname
    error_message = "routeros.hostname output must equal var.routeros.hostname"
  }
}

run "cloudflare_records_planned" {
  command = plan

  assert {
    condition     = cloudflare_record.hub.name == "${var.hub_fqdn_prefix}.${var.base_domain}"
    error_message = "hub record name must be hub.example.net"
  }

  assert {
    condition     = contains(keys(cloudflare_record.edges), "pt")
    error_message = "edges cloudflare_record map must include pt"
  }

  assert {
    condition     = contains(keys(cloudflare_record.edges), "de")
    error_message = "edges cloudflare_record map must include de"
  }
}

run "edge_user_data_includes_k3s" {
  command = plan

  assert {
    condition = alltrue([
      for _, m in module.gcp_edges :
      strcontains(m.test_cloud_init_user_data, "curl -sfL https://get.k3s.io")
    ])
    error_message = "every GCP edge VM must include the k3s installer in cloud-init user data"
  }

  assert {
    condition = alltrue([
      for _, m in module.gcp_edges :
      strcontains(m.test_cloud_init_user_data, "--tls-san=127.0.0.1")
    ])
    error_message = "every GCP edge VM must add 127.0.0.1 as a TLS SAN on the k3s API"
  }

  assert {
    condition = alltrue([
      for _, m in module.gcp_edges :
      strcontains(m.test_cloud_init_user_data, "--https-listen-port=6443")
    ])
    error_message = "every GCP edge VM must keep the k3s API on port 6443"
  }
}
