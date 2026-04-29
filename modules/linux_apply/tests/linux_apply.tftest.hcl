# Validates linux_apply module shallow-merged outputs contract.

mock_provider "ansible" {}

variables {
  host_name     = "test-host"
  workload_kind = "test_workload"
  payload = {
    firezone_dir = "/opt/firezone"
    cfg = {
      a = 1
      b = 2
    }
  }
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

run "contract_module_plans_without_error" {
  command = plan
}

run "contract_outputs_equal_payload_when_no_role_result_exists" {
  command = plan

  assert {
    condition = output.outputs == {
      firezone_dir = "/opt/firezone"
      cfg = {
        a = 1
        b = 2
      }
    }
    error_message = "linux_apply outputs must default to the original payload when no role result exists"
  }
}

run "contract_outputs_do_not_deep_merge_nested_objects" {
  command = plan

  assert {
    condition = output.outputs.cfg == {
      a = 1
      b = 2
    }
    error_message = "linux_apply must keep payload nested objects intact when no ansible override exists"
  }
}

# Apply-time override contract:
# payload.cfg={a=1,b=2} + ansible_outputs.cfg={a=10} -> outputs.cfg={a=10}
# This module test cannot synthesize a post-apply result file at plan time,
# so the override path is covered by behavior tests outside terraform test.

# Raw-key-only: planning succeeds; runtime input carries no caller key path.
run "accepts_only_raw_key" {
  command = plan

  variables {
    host_name     = "test-host"
    workload_kind = "test_workload"
    payload       = { firezone_dir = "/opt/firezone" }
    connection_data = {
      host            = "test.example.com"
      user            = "testuser"
      password        = null
      connection      = "ssh"
      network_os      = "linux"
      ssh_private_key = "fixture-private-key-redacted"
      instance_token  = "i-test-baseline"
    }
  }

  assert {
    condition     = terraform_data.runtime.input.ansible_ssh_private_key_file == ""
    error_message = "raw-key mode must leave ansible_ssh_private_key_file empty (helper materializes it)"
  }

  assert {
    condition     = terraform_data.runtime.input.ansible_ssh_private_key_content != null
    error_message = "raw-key mode must pass ansible_ssh_private_key_content in runtime input"
  }
}

# Neither password, key_file, nor key content — plan succeeds (system auth).
run "accepts_neither_credentials" {
  command = plan

  variables {
    host_name     = "test-host"
    workload_kind = "test_workload"
    payload       = { firezone_dir = "/opt/firezone" }
    connection_data = {
      host       = "test.example.com"
      user       = "testuser"
      connection = "ssh"
      network_os = "linux"
      instance_token = "i-test-baseline"
    }
  }

  assert {
    condition = (
      terraform_data.runtime.input.ansible_ssh_private_key_file == "" &&
      (
        terraform_data.runtime.input.ansible_password == null ||
        terraform_data.runtime.input.ansible_password == ""
      ) &&
      (
        terraform_data.runtime.input.ansible_ssh_private_key_content == null ||
        terraform_data.runtime.input.ansible_ssh_private_key_content == ""
      )
    )
    error_message = "system-auth mode must pass empty/null values for all three auth fields"
  }
}

# Key rotation changes the fingerprint written to triggers_replace.
run "raw_key_fingerprint_present_in_triggers" {
  command = plan

  variables {
    host_name     = "test-host"
    workload_kind = "test_workload"
    payload       = { firezone_dir = "/opt/firezone" }
    connection_data = {
      host            = "test.example.com"
      user            = "testuser"
      connection      = "ssh"
      network_os      = "linux"
      ssh_private_key = "fixture-private-key-redacted"
      instance_token  = "i-test-baseline"
    }
  }

  assert {
    condition = (
      terraform_data.runtime.triggers_replace.ssh_key_fingerprint != null &&
      terraform_data.runtime.triggers_replace.ssh_key_fingerprint != ""
    )
    error_message = "raw-key mode must populate triggers_replace.ssh_key_fingerprint"
  }
}

# Contract: connection_data type must NOT expose ssh_common_args to the runner.
# SSH policy lives in operator-side env vars (ANSIBLE_HOST_KEY_CHECKING,
# ANSIBLE_SSH_ARGS) exported from terragrunt root.hcl.
run "contract_no_ssh_common_args_in_connection_data" {
  command = plan

  variables {
    connection_data = {
      host       = "192.0.2.1"
      user       = "ubuntu"
      connection = "ssh"
      network_os = "linux"
      instance_token = "i-test-baseline"
    }
    host_name     = "test"
    workload_kind = "test_linux_apply"
    payload       = {}
  }

  assert {
    condition = !can(terraform_data.runtime.input["ansible_ssh_common_args"])
    error_message = "ansible_ssh_common_args must not be present in runtime input — SSH policy belongs to operator env vars"
  }
}

# Mutually exclusive key fields — expects validation failure on plan.
run "validation_rejects_both_key_path_and_key_content" {
  command = plan

  variables {
    host_name     = "test-host"
    workload_kind = "test_workload"
    payload       = { firezone_dir = "/opt/firezone" }
    connection_data = {
      host                 = "test.example.com"
      user                 = "testuser"
      password             = null
      connection           = "ssh"
      network_os           = "linux"
      ssh_private_key_file = "~/.ssh/id_ed25519"
      ssh_private_key      = "fixture-private-key-redacted"
      instance_token       = "i-test-baseline"
    }
  }

  expect_failures = [var.connection_data]
}

run "contract_instance_token_in_triggers" {
  command = plan

  assert {
    condition     = terraform_data.runtime.triggers_replace.instance_token == "i-test-baseline"
    error_message = "instance_token from connection_data must appear in triggers_replace so VM recreation forces ansible re-apply"
  }
}

run "contract_instance_token_change_forces_replace" {
  command = plan

  variables {
    connection_data = {
      host                 = "test.example.com"
      user                 = "testuser"
      password             = null
      connection           = "ssh"
      network_os           = "linux"
      ssh_private_key_file = "~/.ssh/id_ed25519"
      instance_token       = "i-test-different"
    }
  }

  assert {
    condition     = terraform_data.runtime.triggers_replace.instance_token == "i-test-different"
    error_message = "changing instance_token must propagate to triggers_replace value"
  }
}

run "contract_apply_log_output_starts_empty" {
  command = plan

  assert {
    condition     = output.apply_log == ""
    error_message = "apply_log output must default to empty string when no result file exists yet"
  }
}
