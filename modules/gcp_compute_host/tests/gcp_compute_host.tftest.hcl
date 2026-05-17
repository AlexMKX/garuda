# Contract tests for modules/gcp_compute_host. Uses mock_provider so no
# Google API calls are made. All runs are plan-only.

mock_provider "google" {}

variables {
  name       = "outer"
  project_id = "test-project"
  region     = "us-central1"
  zone       = "us-central1-a"
  env_slug   = "test-env"
  ssh_keys   = []
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

run "contract_attached_disk_attaches_caller_disk_id" {
  command = plan

  variables {
    attached_disks = [
      { disk_id = "projects/test-project/zones/us-central1-a/disks/my-existing-disk", device_name = "data", mount_path = "/var/lib/data" }
    ]
  }

  assert {
    condition = anytrue([
      for ad in google_compute_instance.this.attached_disk :
      ad.source == "projects/test-project/zones/us-central1-a/disks/my-existing-disk"
    ])
    error_message = "Caller disk must be attached as attached_disk.source verbatim."
  }
}

run "contract_cloud_init_mounts_caller_disk_at_caller_path" {
  command = plan

  variables {
    attached_disks = [
      { disk_id = "projects/p/zones/z/disks/d", device_name = "data", mount_path = "/var/lib/data" }
    ]
  }

  assert {
    condition     = can(regex("/var/lib/data", google_compute_instance.this.metadata["user-data"]))
    error_message = "Caller-supplied mount_path must appear in rendered cloud-init user-data"
  }

  assert {
    condition     = can(regex("google-data", google_compute_instance.this.metadata["user-data"]))
    error_message = "Stable /dev/disk/by-id/google-<device_name> path must appear in user-data"
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
  # plan (not apply): cloudinit_config is a data source, fully evaluated
  # during plan, so output.test_cloud_init_user_data is materialized.
  # Apply would also work but triggers prevent_destroy on the data disk
  # at teardown — plan-only sidesteps that and is sufficient for content
  # introspection.
  command = plan

  # Enable disk so the bootstrap cloud-init part is rendered; without it
  # output.test_cloud_init_user_data is null (new contract from
  # user-data-extension feature) and strcontains() would error on null.
  # The assertions below check that the module's bootstrap part does NOT
  # introduce user-provisioning artifacts — that property is meaningful
  # only when the bootstrap is actually present.
  variables {
    attached_disks = [
      { disk_id = "projects/p/zones/z/disks/d", device_name = "data", mount_path = "/var/lib/data" }
    ]
  }

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

# NOTE: there is no runtime test for "ssh_keys is required".
# In Terraform/OpenTofu, required-ness is a structural property of the
# variable declaration (no default, `nullable = false`) enforced by the
# language at plan/apply time. The error emitted is "No value for required
# variable" / "required variable may not be set to null" — these are
# variable-layer diagnostics, not check/validation/precondition failures,
# so they are NOT catchable via `expect_failures = [var.ssh_keys]`.
#
# Required-ness is therefore audited via:
#   - source inspection (no `default` keyword in the variable block;
#     `nullable = false` set)
#   - the validation runs below that exercise non-null, non-default
#     inputs and prove the variable is exposed and validated.

run "contract_ssh_keys_accepts_empty_list" {
  command = apply

  variables {
    ssh_keys = []
  }

  assert {
    condition     = can(regex("garuda:ssh-ed25519 ", output.test_ssh_keys_metadata))
    error_message = "Empty ssh_keys must still produce the module-managed garuda admin key in metadata."
  }
}

run "contract_ssh_keys_validation_rejects_malformed" {
  command = plan

  variables {
    ssh_keys = ["not-a-valid-entry"]
  }

  expect_failures = [var.ssh_keys]
}

run "contract_ssh_keys_validation_rejects_bad_username" {
  command = plan

  variables {
    ssh_keys = ["1invalid:ssh-ed25519 AAAAtestkey 1invalid@host"]
  }

  expect_failures = [var.ssh_keys]
}

run "contract_ssh_keys_validation_rejects_bad_keytype" {
  command = plan

  variables {
    ssh_keys = ["alice:ssh-dsa AAAAtestkey alice@host"]
  }

  expect_failures = [var.ssh_keys]
}

run "user_data_parts_default_empty_no_user_data_metadata" {
  command = plan

  variables {
    ssh_keys = []
  }

  assert {
    condition     = output.test_cloud_init_user_data == null
    error_message = "With no disk and no user_data_parts, test_cloud_init_user_data must be null."
  }
}

run "user_data_parts_default_with_disk_renders_auto_part_only" {
  command = plan

  variables {
    ssh_keys       = []
    attached_disks = [{ disk_id = "projects/p/zones/z/disks/d", device_name = "data", mount_path = "/var/lib/data" }]
  }

  assert {
    condition     = output.test_cloud_init_user_data != null
    error_message = "Disk enabled must produce a cloud-init bundle."
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "data")
    error_message = "Auto-injected disk part must include the caller device_name label."
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "google-data")
    error_message = "Auto-injected disk part must reference /dev/disk/by-id/google-data."
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "00-attached-disks.yaml")
    error_message = "Module-managed disk part must use filename prefix '00-attached-disks.yaml'."
  }
}

run "user_data_parts_appended_to_bundle" {
  command = plan

  variables {
    ssh_keys       = []
    attached_disks = [{ disk_id = "projects/p/zones/z/disks/d", device_name = "data", mount_path = "/var/lib/data" }]
    user_data_parts = [
      <<-EOT
        #cloud-config
        runcmd:
          - echo "hello from user part zero"
      EOT
    ]
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "00-attached-disks.yaml")
    error_message = "Auto-injected disk part filename must be present."
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "10-user-0.yaml")
    error_message = "First user part must use filename '10-user-0.yaml'."
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "hello from user part zero")
    error_message = "User part content must pass through verbatim."
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "mount -a")
    error_message = "Bootstrap runcmd 'mount -a' must still appear."
  }
}

run "user_data_parts_multiple_parts_filename_indices" {
  command = plan

  variables {
    ssh_keys = []
    user_data_parts = [
      "#cloud-config\nruncmd:\n  - echo FIRST",
      "#cloud-config\nruncmd:\n  - echo SECOND",
      "#cloud-config\nruncmd:\n  - echo THIRD",
    ]
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "10-user-0.yaml")
    error_message = "First user part must have filename '10-user-0.yaml'."
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "11-user-1.yaml")
    error_message = "Second user part must have filename '11-user-1.yaml'."
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "12-user-2.yaml")
    error_message = "Third user part must have filename '12-user-2.yaml'."
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "echo FIRST")
    error_message = "User part 0 content must appear verbatim."
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "echo SECOND")
    error_message = "User part 1 content must appear verbatim."
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "echo THIRD")
    error_message = "User part 2 content must appear verbatim."
  }
}

run "user_data_parts_validation_rejects_missing_header" {
  command = plan

  variables {
    ssh_keys = []
    user_data_parts = [
      "runcmd:\n  - echo no-header"
    ]
  }

  expect_failures = [var.user_data_parts]
}

run "user_data_parts_validation_rejects_shellscript_header" {
  command = plan

  variables {
    ssh_keys = []
    user_data_parts = [
      "#!/bin/bash\necho 'shell script not allowed'"
    ]
  }

  expect_failures = [var.user_data_parts]
}
