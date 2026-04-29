# Contract tests for modules/gcp_compute_host. Uses mock_provider so no
# Google API calls are made. All runs are plan-only.

mock_provider "google" {}

variables {
  name       = "outer"
  project_id = "test-project"
  region     = "us-central1"
  zone       = "us-central1-a"
  env_slug   = "test-env"
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
    condition     = google_compute_instance.this.name == "garuda-test-env-outer"
    error_message = "Instance name must be prefix-env_slug-name"
  }

  assert {
    condition     = google_compute_instance.this.hostname == "test-env-outer.c.test-project.internal"
    error_message = "Hostname must embed env_slug; FQDN scoped to project's internal DNS zone"
  }
}

run "contract_default_ingress_creates_firewall_with_ssh_http_https_icmp" {
  command = plan

  assert {
    condition     = length(google_compute_firewall.this) == 1
    error_message = "Firewall must be created when default_ingress is true (default)"
  }

  assert {
    condition     = length(google_compute_firewall.this[0].allow) >= 4
    error_message = "Default ingress must include at least 4 allow blocks (SSH, HTTP, HTTPS, ICMP)"
  }
}

run "contract_default_ingress_false_no_firewall_when_empty_ingress" {
  command = plan

  variables {
    default_ingress = false
    ingress_ports   = []
  }

  assert {
    condition     = length(google_compute_firewall.this) == 0
    error_message = "Firewall must not be created when default_ingress=false and ingress_ports empty"
  }
}

run "contract_ingress_ports_add_allow_blocks" {
  command = plan

  variables {
    ingress_ports = [
      { protocol = "UDP", port = 55824, description = "wg_uk" },
    ]
  }

  assert {
    condition     = length(google_compute_firewall.this[0].allow) >= 5
    error_message = "Ingress_ports entries must be added as extra allow blocks"
  }
}

run "contract_no_data_disk_by_default" {
  command = plan

  assert {
    condition     = length(google_compute_disk.data) == 0
    error_message = "Data disk must not be created when data_disk_size_gb=0 and existing_data_disk_id=null"
  }
}

run "contract_data_disk_size_gb_creates_new_disk" {
  command = plan

  variables {
    data_disk_size_gb = 20
  }

  assert {
    condition     = length(google_compute_disk.data) == 1
    error_message = "Data disk resource must be created when data_disk_size_gb > 0"
  }

  assert {
    condition     = google_compute_disk.data[0].size == 20
    error_message = "Data disk size must match data_disk_size_gb"
  }
}

run "contract_existing_data_disk_attaches_without_creating" {
  command = plan

  variables {
    existing_data_disk_id = "projects/test-project/zones/us-central1-a/disks/my-existing-disk"
  }

  assert {
    condition     = length(google_compute_disk.data) == 0
    error_message = "No new data disk must be created when existing_data_disk_id is set"
  }

  assert {
    condition = anytrue([
      for ad in google_compute_instance.this.attached_disk :
      ad.source == "projects/test-project/zones/us-central1-a/disks/my-existing-disk"
    ])
    error_message = "Existing disk must be attached via attached_disk.source"
  }
}

run "contract_cloud_init_mounts_data_disk_at_opt_garuda" {
  command = plan

  variables {
    data_disk_size_gb = 5
  }

  assert {
    condition     = can(regex("/opt/garuda", google_compute_instance.this.metadata["user-data"]))
    error_message = "Mount path /opt/garuda must appear in rendered cloud-init user-data"
  }

  assert {
    condition     = can(regex("google-garuda-data", google_compute_instance.this.metadata["user-data"]))
    error_message = "Stable /dev/disk/by-id/google-garuda-data path must appear in user-data"
  }
}

run "contract_metadata_user_keys_merge_over_managed" {
  command = apply

  variables {
    metadata = { "block-project-ssh-keys" = "true" }
  }

  assert {
    condition     = google_compute_instance.this.metadata["block-project-ssh-keys"] == "true"
    error_message = "User metadata keys must flow through to the instance"
  }

  assert {
    condition     = can(regex("garuda:ssh-ed25519 ", google_compute_instance.this.metadata["ssh-keys"]))
    error_message = "Managed ssh-keys metadata must still be present alongside user metadata"
  }
}

run "contract_connection_data_output_shape" {
  command = apply

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

  assert {
    condition     = output.connection_data.ssh_private_key != null
    error_message = "connection_data.ssh_private_key must be populated (module always generates a keypair)"
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

run "contract_connection_data_carries_instance_token" {
  command = plan

  assert {
    condition     = output.connection_data.instance_token == output.instance_id
    error_message = "connection_data.instance_token must equal output.instance_id so VM recreation propagates to linux_apply triggers"
  }
}
