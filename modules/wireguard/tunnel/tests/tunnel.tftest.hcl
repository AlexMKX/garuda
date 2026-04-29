# Contract tests for modules/wireguard/tunnel.
# Validates the env-prefixed tunnel_name vs raw kernel_ifname split.

mock_provider "wireguard" {}

variables {
  name     = "hub_edge"
  subnet   = "192.0.2.0/28"
  env_slug = "test-env"
  peers = {
    hub = {
      address       = "192.0.2.1/28"
      listen_port   = 51820
      endpoint_host = "hub.example.net"
    }
    edge = {
      address       = "192.0.2.2/28"
      listen_port   = 51820
      endpoint_host = "edge.example.net"
    }
  }
}

run "contract_tunnel_name_embeds_env_slug" {
  command = plan

  assert {
    condition     = output.peers["hub"].tunnel_name == "test-env-hub-edge"
    error_message = "tunnel_name must be env_slug-name (underscores replaced) so RouterOS resource names are env-scoped"
  }

  assert {
    condition     = output.peers["edge"].tunnel_name == "test-env-hub-edge"
    error_message = "All peers in a tunnel share the same tunnel_name"
  }
}

run "contract_kernel_ifname_excludes_env_slug" {
  command = plan

  assert {
    condition     = output.peers["hub"].kernel_ifname == "hub-edge"
    error_message = "kernel_ifname must NOT include env_slug so it stays within Linux IFNAMSIZ=15"
  }

  assert {
    condition     = length(output.peers["hub"].kernel_ifname) <= 15
    error_message = "kernel_ifname must be ≤15 chars (Linux IFNAMSIZ-1)"
  }
}

run "contract_env_slug_required" {
  command = plan

  variables {
    env_slug = ""
  }

  expect_failures = [var.env_slug]
}

run "contract_combined_length_validation" {
  command = plan

  variables {
    env_slug = "very-long-environment-slug"
  }

  expect_failures = [var.env_slug]
}

run "contract_routeros_combined_length_validation" {
  command = plan

  variables {
    name     = "extremely-long-tunnel-name-here"
    env_slug = "test-env"
  }

  expect_failures = [var.name]
}
