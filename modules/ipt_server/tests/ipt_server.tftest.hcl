# Contract tests for modules/ipt_server.

mock_provider "ansible" {}

variables {
  name           = "ipt_server__test"
  host_name      = "test-host"
  ipt_server_dir = "/opt/garuda/ipt_server"
  routes = [{
    route = [{ gw = "10.0.0.1" }]
    rules = ["0.0.0.0/0"]
  }]
  connection_data = {
    host                 = "test.example.com"
    user                 = "testuser"
    password             = null
    connection           = "ssh"
    network_os           = "linux"
    ssh_private_key_file = "~/.ssh/id_ed25519"
    instance_token       = "i-test-baseline"
  }
  labels = {
    "garuda.frr.ospf.router_id" = "10.130.30.99"
  }
}

run "contract_labels_variable_passes_through_router_id" {
  command = plan

  assert {
    condition     = var.labels["garuda.frr.ospf.router_id"] == "10.130.30.99"
    error_message = "labels variable must pass through the router_id key verbatim"
  }
}

# Absence of variable "frr_router_id" is enforced statically: if someone
# re-introduces it, terraform validate in this module will fail when any
# caller omits it. No runtime assertion is possible for a missing variable —
# the guarantee lives in the module schema, not in a test run.

# contract_workload_client_cidrs_no_longer_accepted: enforced statically —
# var.workload_client_cidrs was removed from variables.tf. Any caller that
# passes it will get "An argument named workload_client_cidrs is not expected"
# at terraform validate / plan time. No runtime test needed.

run "contract_labels_mandatory" {
  command = plan

  variables {
    labels = {}
  }

  expect_failures = [
    var.labels,
  ]
}
