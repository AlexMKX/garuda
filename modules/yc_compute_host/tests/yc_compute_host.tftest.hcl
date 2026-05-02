# Contract tests for modules/yc_compute_host. Uses mock_provider so no YC
# API calls are made. All runs are plan-only unless noted.

mock_provider "yandex" {}

variables {
  name      = "test_host"
  subnet_id = "test-subnet"
  env_slug  = "test-env"
}

run "contract_env_slug_required" {
  command = plan

  variables {
    env_slug = ""
  }

  expect_failures = [var.env_slug]
}

run "contract_instance_name_uses_env_slug" {
  command = plan

  assert {
    condition     = yandex_compute_instance.this.name == "garuda-test-env-test-host"
    error_message = "Instance name must be prefix-env_slug-name"
  }

  assert {
    condition     = yandex_compute_instance.this.hostname == "test-env-test-host"
    error_message = "Hostname must embed env_slug to keep YC FQDN unique per stack"
  }
}

run "contract_no_data_disk_by_default" {
  command = plan

  assert {
    condition     = length(yandex_compute_disk.data) == 0
    error_message = "Data disk must not be created when data_disk_size_gb=0 and existing_data_disk_id=null"
  }
}

run "contract_data_disk_size_gb_creates_new_disk" {
  command = plan

  variables {
    data_disk_size_gb = 20
  }

  assert {
    condition     = length(yandex_compute_disk.data) == 1
    error_message = "Data disk resource must be created when data_disk_size_gb > 0"
  }

  assert {
    condition     = yandex_compute_disk.data[0].size == 20
    error_message = "Data disk size must match data_disk_size_gb"
  }
}

run "contract_existing_data_disk_attaches_without_creating" {
  command = plan

  variables {
    existing_data_disk_id = "existing-disk-id-42"
  }

  assert {
    condition     = length(yandex_compute_disk.data) == 0
    error_message = "No new data disk must be created when existing_data_disk_id is set"
  }

  assert {
    condition = anytrue([
      for sd in yandex_compute_instance.this.secondary_disk :
      sd.disk_id == "existing-disk-id-42"
    ])
    error_message = "Existing disk must be attached as secondary_disk by id"
  }
}

run "contract_cloud_init_mounts_data_disk_at_opt_garuda" {
  command = plan

  variables {
    data_disk_size_gb = 5
  }

  assert {
    condition     = can(regex("/opt/garuda", yandex_compute_instance.this.metadata["user-data"]))
    error_message = "Mount path /opt/garuda must appear in rendered cloud-init user-data"
  }

  assert {
    condition     = can(regex("virtio-garuda-data", yandex_compute_instance.this.metadata["user-data"]))
    error_message = "Stable /dev/disk/by-id/virtio-garuda-data path must appear in user-data"
  }
}

run "contract_default_ingress_creates_security_group" {
  command = plan

  assert {
    condition     = length(yandex_vpc_security_group.this) == 1
    error_message = "SG must be created when default_ingress=true (default)"
  }
}

run "contract_default_ingress_false_no_sg_when_empty_ingress" {
  command = plan

  variables {
    default_ingress = false
    ingress_ports   = []
  }

  assert {
    condition     = length(yandex_vpc_security_group.this) == 0
    error_message = "SG must not be created when default_ingress=false and ingress_ports empty"
  }
}

run "contract_ingress_ports_add_rules" {
  command = plan

  variables {
    default_ingress = false
    ingress_ports = [
      { protocol = "UDP", port = 55824, description = "wg_uk" },
    ]
  }

  assert {
    condition     = length(yandex_vpc_security_group.this) == 1
    error_message = "SG must be created when ingress_ports non-empty even if default_ingress=false"
  }

  assert {
    condition     = length(yandex_vpc_security_group.this[0].ingress) >= 1
    error_message = "User-supplied ingress port must appear as SG ingress rule"
  }
}

run "contract_metadata_user_keys_merge_over_managed" {
  command = apply

  variables {
    metadata = { "serial-port-enable" = "1" }
  }

  assert {
    condition     = yandex_compute_instance.this.metadata["serial-port-enable"] == "1"
    error_message = "User metadata keys must flow through to the instance"
  }

  assert {
    condition     = can(regex("garuda:ssh-ed25519 ", output.test_ssh_keys_metadata))
    error_message = "Managed ssh-keys metadata must still be present alongside user metadata"
  }
}

run "contract_connection_data_output_shape" {
  command = plan

  assert {
    condition     = output.connection_data.user == "garuda"
    error_message = "connection_data.user must default to garuda"
  }

  assert {
    condition     = output.connection_data.connection == "ssh"
    error_message = "connection_data.connection must be literal 'ssh'"
  }

  assert {
    condition     = output.connection_data.network_os == "linux"
    error_message = "connection_data.network_os must be literal 'linux'"
  }

  assert {
    condition     = output.connection_data.password == null
    error_message = "connection_data.password must be null (key-based auth)"
  }

  assert {
    condition     = output.connection_data.ssh_private_key_file == null
    error_message = "connection_data.ssh_private_key_file must be null (module does not persist a file)"
  }
}

run "contract_connection_data_host_uses_private_ip_when_no_nat" {
  command = plan

  variables {
    nat = false
  }

  assert {
    condition     = output.connection_data.host == yandex_compute_instance.this.network_interface[0].ip_address
    error_message = "With nat=false, connection_data.host must fall back to private IP"
  }
}

run "contract_ssh_keys_metadata_includes_managed_user" {
  command = apply

  assert {
    condition     = can(regex("garuda:ssh-ed25519 ", output.test_ssh_keys_metadata))
    error_message = "metadata['ssh-keys'] must contain a `garuda:ssh-ed25519 ...` line for the module-managed user"
  }

  assert {
    condition     = !strcontains(output.test_ssh_keys_metadata, "\n\n")
    error_message = "metadata['ssh-keys'] must not contain blank lines"
  }
}

run "contract_ssh_keys_passthrough_verbatim" {
  command = apply

  variables {
    ssh_keys = [
      "alice:ssh-ed25519 AAAAtestkeyalice alice@hostA",
      "bob:ssh-ed25519 AAAAtestkeybob bob@hostB",
    ]
  }

  assert {
    condition     = can(regex("alice:ssh-ed25519 AAAAtestkeyalice alice@hostA", output.test_ssh_keys_metadata))
    error_message = "var.ssh_keys[0] must appear verbatim in metadata"
  }

  assert {
    condition     = can(regex("bob:ssh-ed25519 AAAAtestkeybob bob@hostB", output.test_ssh_keys_metadata))
    error_message = "var.ssh_keys[1] must appear verbatim in metadata"
  }

  assert {
    condition     = can(regex("garuda:ssh-ed25519 ", output.test_ssh_keys_metadata))
    error_message = "managed user line must coexist with var.ssh_keys entries"
  }
}

run "contract_cloud_init_has_no_user_provisioning" {
  command = apply

  assert {
    condition     = !strcontains(output.test_cloud_init_user_data, "users:")
    error_message = "cloud-init user-data must not declare a users: block — guest agent handles users"
  }

  assert {
    condition     = !strcontains(output.test_cloud_init_user_data, "write_files")
    error_message = "cloud-init user-data must not write any files — per-boot key sync is gone"
  }

  assert {
    condition     = !strcontains(output.test_cloud_init_user_data, "per-boot")
    error_message = "cloud-init user-data must not reference per-boot scripts"
  }
}

run "contract_image_family_default_is_oslogin" {
  command = plan

  assert {
    condition     = can(regex("oslogin", var.image_family))
    error_message = "default image_family must be an *-oslogin family for guest-agent SSH key sync"
  }
}

run "contract_image_family_rejects_non_oslogin" {
  command = plan

  variables {
    image_family = "ubuntu-2404-lts"
  }

  expect_failures = [
    var.image_family,
  ]
}

run "contract_allow_stopping_for_update_hardcoded_true" {
  command = plan

  assert {
    condition     = yandex_compute_instance.this.allow_stopping_for_update == true
    error_message = "allow_stopping_for_update must be hardcoded true (not configurable)"
  }
}

run "contract_connection_data_carries_instance_token" {
  command = plan

  assert {
    condition     = output.connection_data.instance_token == output.instance_id
    error_message = "connection_data.instance_token must equal output.instance_id so VM recreation propagates to linux_apply triggers"
  }
}

run "contract_oslogin_default_false_omits_metadata_key" {
  command = plan

  assert {
    condition     = !contains(keys(yandex_compute_instance.this.metadata), "enable-oslogin")
    error_message = "enable-oslogin metadata key must be absent by default — opt-in only, otherwise guest agent stops syncing metadata['ssh-keys'] and locks everyone out"
  }
}

run "contract_oslogin_enabled_sets_metadata_key" {
  command = plan

  variables {
    oslogin_enabled = true
  }

  assert {
    condition     = yandex_compute_instance.this.metadata["enable-oslogin"] == "true"
    error_message = "oslogin_enabled=true must set enable-oslogin=true metadata"
  }
}

run "contract_user_metadata_can_override_enable_oslogin" {
  command = plan

  variables {
    oslogin_enabled = true
    metadata        = { "enable-oslogin" = "false" }
  }

  assert {
    condition     = yandex_compute_instance.this.metadata["enable-oslogin"] == "false"
    error_message = "user-supplied metadata must win over module-managed enable-oslogin"
  }
}
