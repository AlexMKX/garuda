# Validates the tunnel-centric RouterOS module contract.

mock_provider "routeros" {}

# bypass.tf calls data.dns_a_record_set on the peer endpoint hostname
# to drive the endpoint sync script's launch_trigger. Mock it so tests
# don't depend on real DNS; the value only matters for the sha1 hash.
mock_provider "dns" {
  mock_data "dns_a_record_set" {
    defaults = {
      addrs = ["192.0.2.1"]
    }
  }
}

variables {
  hostname = "routeros-test"
  config = {
    tunnel_name   = "test-env-wg-tik"
    kernel_ifname = "wg-tik"
    address       = "192.0.2.2/24"
    private_key   = "aGVsbG8gd29ybGQ="
    public_key    = "aGVsbG8gd29ybGQ="
    preshared_key = "aGVsbG8gd29ybGQ="
    listen_port   = 13231
  }
  peer = {
    tunnel_name   = "test-env-wg-tik"
    kernel_ifname = "wg-tik"
    address       = "192.0.2.1/24"
    private_key   = "aGVsbG8gd29ybGQ="
    public_key    = "aGVsbG8gd29ybGQ="
    preshared_key = "aGVsbG8gd29ybGQ="
    listen_port   = 55825
    endpoint_host = "vpn.example.net"
  }
  subnet         = "192.0.2.0/24"
  allowed_nets   = ["0.0.0.0/0", "224.0.0.0/4"]
  interface_list = "LAN"
  router_id      = "192.0.2.2"
  ospf_area      = "0.0.0.0"
}

run "contract_routeros_tunnel_stack" {
  command = plan

  assert {
    condition     = routeros_routing_ospf_instance.this.name == "garuda-test-env-wg-tik"
    error_message = "RouterOS module must create a per-tunnel OSPF instance"
  }

  assert {
    condition     = contains(tolist(routeros_routing_ospf_instance.this.redistribute), "connected")
    error_message = "RouterOS OSPF instance must redistribute connected routes"
  }

  assert {
    condition     = routeros_routing_table.wg_bypass.name == "wg-bypass-test-env-wg-tik"
    error_message = "RouterOS module must create a per-tunnel bypass routing table"
  }

  assert {
    condition     = routeros_system_scheduler.wg_endpoint_sync.interval == "1m"
    error_message = "RouterOS module must schedule endpoint sync every minute"
  }

  assert {
    condition     = routeros_system_script.wg_endpoint_sync.launch_trigger != ""
    error_message = "RouterOS module must set launch_trigger so the sync script runs on apply rather than waiting for the next scheduler tick"
  }

  assert {
    condition     = output.bypass_table_name == "wg-bypass-test-env-wg-tik"
    error_message = "RouterOS module must expose bypass_table_name so callers can populate it with a physical-WAN default route"
  }
}

run "contract_requires_peer_endpoint_host" {
  command = plan

  variables {
    peer = {
      tunnel_name   = "test-env-wg-tik"
      kernel_ifname = "wg-tik"
      address       = "192.0.2.1/24"
      private_key   = "aGVsbG8gd29ybGQ="
      public_key    = "aGVsbG8gd29ybGQ="
      preshared_key = "aGVsbG8gd29ybGQ="
      listen_port   = 55825
    }
  }

  expect_failures = [var.peer]
}

run "contract_routeros_interface_uses_tunnel_name" {
  command = plan

  assert {
    condition     = routeros_interface_wireguard.this.name == "test-env-wg-tik"
    error_message = "RouterOS WG interface name must be tunnel_name (env-prefixed), not kernel_ifname"
  }
}
