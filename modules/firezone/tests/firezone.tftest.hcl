# Contract tests for modules/firezone.

mock_provider "ansible" {}

variables {
  name           = "firezone__test"
  host_name      = "test-host"
  server_url     = "https://firezone.example.com"
  admin_password = "test-admin-password"
  client_subnet  = "10.11.0.0/24"
  labels         = { "garuda.operator-scope" = "backbone_network" }
  connection_data = {
    host                 = "test.example.com"
    user                 = "testuser"
    password             = null
    connection           = "ssh"
    network_os           = "linux"
    ssh_private_key_file = "~/.ssh/id_ed25519"
    instance_token       = "i-test-baseline"
  }
}

run "contract_labels_variable_accepts_map_string" {
  command = plan

  assert {
    condition     = var.labels["garuda.operator-scope"] == "backbone_network"
    error_message = "labels must pass through verbatim as a map(string)"
  }
}

run "contract_masquerade_defaults_to_false" {
  command = plan

  assert {
    condition     = var.masquerade == false
    error_message = "masquerade must default to false (Garuda topologies own SNAT at the border bridge); stand-alone deployments must set masquerade=true explicitly"
  }
}

run "contract_masquerade_accepts_true_override" {
  command = plan

  variables {
    masquerade = true
  }

  assert {
    condition     = var.masquerade == true
    error_message = "masquerade must accept an explicit true override for stand-alone deployments without an upstream border SNAT chain"
  }
}
