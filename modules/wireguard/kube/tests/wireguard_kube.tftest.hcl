mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  namespace = "garuda"
  name      = "wg-pt"

  config = {
    kernel_ifname = "wg-pt"
    private_key   = "stubprivatekey"
    address       = "192.0.2.2/30"
    subnet        = "192.0.2.0/30"
    listen_port   = null
    endpoint_host = null
  }

  peer = {
    public_key           = "stubpublickey"
    endpoint_host        = "hub.example.net"
    endpoint_listen_port = 51820
    preshared_key        = null
    address              = "192.0.2.1/30"
  }

  allowed_nets    = ["0.0.0.0/0"]
  wireguard_image = "ghcr.io/alexmkx/garuda-wireguard:latest"
  frr_image       = "ghcr.io/alexmkx/garuda-frr-sidecar:latest"
}

run "chart_path_resolves_to_bundled_chart" {
  command = plan

  assert {
    condition     = endswith(helm_release.wireguard.chart, "/charts/wireguard")
    error_message = "helm_release.chart must point at $${path.module}/charts/wireguard"
  }
}

# OpenTofu's yamlencode emits quoted block-style YAML ("key": "value"),
# so substrings below match that form. See modules/garuda_k8s/tests/garuda_k8s.tftest.hcl
# for the precedent set in Task 5.
run "values_include_peer_and_config" {
  command = plan

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"kernel_ifname\": \"wg-pt\"")
    error_message = "rendered values must contain config.kernel_ifname"
  }

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"endpoint_host\": \"hub.example.net\"")
    error_message = "rendered values must contain peer.endpoint_host"
  }

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"table\": \"off\"")
    error_message = "rendered values must contain table"
  }
}

run "default_ospf_is_null" {
  command = plan

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"ospf\": null")
    error_message = "with default var.ospf=null, rendered values must contain 'ospf: null'"
  }
}

run "ospf_set_propagates_router_id_and_interfaces" {
  command = plan

  variables {
    ospf = {
      router_id  = "10.130.30.1"
      interfaces = ["wg-pt"]
    }
  }

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"router_id\": \"10.130.30.1\"")
    error_message = "rendered values must contain ospf.router_id"
  }

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "- \"wg-pt\"")
    error_message = "rendered values must contain ospf.interfaces entry"
  }

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "\"default_originate\": false")
    error_message = "ospf.default_originate must default to false"
  }
}

run "nic_attach_default_is_backbone_and_border" {
  command = plan

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "- \"backbone\"")
    error_message = "default nic_attach must include backbone"
  }

  assert {
    condition     = strcontains(helm_release.wireguard.values[0], "- \"border\"")
    error_message = "default nic_attach must include border"
  }
}

run "deployment_name_output" {
  command = plan

  assert {
    condition     = output.deployment_name == "wg-pt"
    error_message = "output.deployment_name must equal var.name"
  }
}

run "invalid_ifname_too_long_rejected" {
  command = plan

  variables {
    config = {
      kernel_ifname = "wg-this-name-is-too-long"
      private_key   = "stubprivatekey"
      address       = "192.0.2.2/30"
      subnet        = "192.0.2.0/30"
      listen_port   = null
      endpoint_host = null
    }
  }

  expect_failures = [var.config]
}

run "invalid_ospf_router_id_rejected" {
  command = plan

  variables {
    ospf = {
      router_id  = "not-an-ip"
      interfaces = ["wg-pt"]
    }
  }

  expect_failures = [var.ospf]
}

run "invalid_ospf_redistribute_value_rejected" {
  command = plan

  variables {
    ospf = {
      router_id    = "10.130.30.1"
      interfaces   = ["wg-pt"]
      redistribute = ["bgp"]
    }
  }

  expect_failures = [var.ospf]
}
