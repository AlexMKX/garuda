# Validates wireguard/linux module accepts connection_data.

mock_provider "ansible" {}

variables {
  host_name = "test-host"
  config = {
    tunnel_name   = "test-env-wg-test"
    kernel_ifname = "wg-test"
    address       = "192.0.2.1/24"
    private_key   = "aGVsbG8gd29ybGQ="
    public_key    = "aGVsbG8gd29ybGQ="
    preshared_key = "aGVsbG8gd29ybGQ="
    listen_port   = 55824
  }
  peer = {
    tunnel_name   = "test-env-wg-test"
    kernel_ifname = "wg-test"
    address       = "192.0.2.2/24"
    private_key   = "aGVsbG8gd29ybGQ="
    public_key    = "aGVsbG8gd29ybGQ="
    preshared_key = "aGVsbG8gd29ybGQ="
  }
  allowed_nets = ["0.0.0.0/0"]
  table        = "off"
  labels       = { "garuda.operator-scope" = "backbone_network" }
  connection_data = {
    host                 = "test.example.net"
    user                 = "testuser"
    password             = null
    connection           = "ssh"
    network_os           = "linux"
    ssh_private_key_file = "~/.ssh/id_ed25519"
    instance_token       = "i-test-baseline"
  }
}

run "contract_module_plans_without_error" {
  command = plan
}

run "contract_labels_variable_accepts_map_string" {
  command = plan

  assert {
    condition     = var.labels["garuda.operator-scope"] == "backbone_network"
    error_message = "labels must pass through verbatim as a map(string)"
  }
}

run "contract_payload_uses_kernel_ifname" {
  command = plan

  assert {
    condition     = local.payload.wireguard_interface_name == "wg-test"
    error_message = "Linux WG ifname must come from config.kernel_ifname (raw, ≤15 chars), not config.tunnel_name (env-prefixed)"
  }
}
