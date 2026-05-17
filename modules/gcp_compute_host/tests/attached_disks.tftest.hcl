mock_provider "google" {}

variables {
  name       = "outer"
  project_id = "test-project"
  region     = "us-central1"
  zone       = "us-central1-a"
  env_slug   = "test-env"
  ssh_keys   = []
}

run "zero_disks_no_user_data_metadata" {
  command = plan

  variables {
    attached_disks = []
  }

  assert {
    condition     = output.test_cloud_init_user_data == null
    error_message = "Empty attached_disks and empty user_data_parts must leave metadata['user-data'] absent."
  }
}

run "one_disk_renders_mount_part" {
  command = plan

  variables {
    attached_disks = [
      { disk_id = "projects/p/zones/z/disks/d", device_name = "data", mount_path = "/var/lib/data" }
    ]
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "/dev/disk/by-id/google-data")
    error_message = "Mount part must reference /dev/disk/by-id/google-<device_name>."
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "/var/lib/data")
    error_message = "Mount part must reference caller-supplied mount_path."
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "ext4")
    error_message = "Default fs_type must be ext4."
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "nofail")
    error_message = "Mount entry must include nofail option."
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "00-attached-disks.yaml")
    error_message = "Auto-injected disk-mount part must use filename '00-attached-disks.yaml'."
  }
}

run "two_disks_mixed_fs_render_both" {
  command = plan

  variables {
    attached_disks = [
      { disk_id = "projects/p/zones/z/disks/etcd", device_name = "etcd", mount_path = "/var/lib/etcd", fs_type = "xfs" },
      { disk_id = "projects/p/zones/z/disks/data", device_name = "data", mount_path = "/var/lib/data" }
    ]
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "xfs")
    error_message = "fs_type=xfs must appear in rendered user-data."
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "/dev/disk/by-id/google-etcd")
    error_message = "First disk by-id path must appear."
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "/dev/disk/by-id/google-data")
    error_message = "Second disk by-id path must appear."
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "/var/lib/etcd")
    error_message = "First mount_path must appear."
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "/var/lib/data")
    error_message = "Second mount_path must appear."
  }
}

run "auto_part_precedes_caller_parts" {
  command = plan

  variables {
    attached_disks = [
      { disk_id = "projects/p/zones/z/disks/d", device_name = "data", mount_path = "/var/lib/data" }
    ]
    user_data_parts = [
      "#cloud-config\nruncmd:\n  - echo hi"
    ]
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "00-attached-disks.yaml")
    error_message = "Auto-injected mount part must be present."
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "10-user-0.yaml")
    error_message = "Caller part must keep the PR #37 filename contract '10-user-0.yaml'."
  }

  assert {
    condition     = strcontains(output.test_cloud_init_user_data, "echo hi")
    error_message = "Caller part content must pass through verbatim."
  }
}

run "module_does_not_create_disk_resources" {
  command = plan

  variables {
    attached_disks = [
      { disk_id = "projects/p/zones/z/disks/d", device_name = "data", mount_path = "/var/lib/data" }
    ]
  }

  assert {
    condition = anytrue([
      for ad in google_compute_instance.this.attached_disk :
      ad.source == "projects/p/zones/z/disks/d"
    ])
    error_message = "Caller disk_id must be attached as attached_disk.source verbatim."
  }
}

run "reject_duplicate_device_name" {
  command = plan

  variables {
    attached_disks = [
      { disk_id = "a", device_name = "data", mount_path = "/a" },
      { disk_id = "b", device_name = "data", mount_path = "/b" }
    ]
  }

  expect_failures = [var.attached_disks]
}

run "reject_duplicate_mount_path" {
  command = plan

  variables {
    attached_disks = [
      { disk_id = "a", device_name = "x", mount_path = "/same" },
      { disk_id = "b", device_name = "y", mount_path = "/same" }
    ]
  }

  expect_failures = [var.attached_disks]
}

run "reject_relative_mount_path" {
  command = plan

  variables {
    attached_disks = [
      { disk_id = "a", device_name = "x", mount_path = "relative/path" }
    ]
  }

  expect_failures = [var.attached_disks]
}

run "reject_root_mount_path" {
  command = plan

  variables {
    attached_disks = [
      { disk_id = "a", device_name = "x", mount_path = "/" }
    ]
  }

  expect_failures = [var.attached_disks]
}

run "reject_invalid_fs_type" {
  command = plan

  variables {
    attached_disks = [
      { disk_id = "a", device_name = "x", mount_path = "/data", fs_type = "btrfs" }
    ]
  }

  expect_failures = [var.attached_disks]
}

run "reject_uppercase_device_name" {
  command = plan

  variables {
    attached_disks = [
      { disk_id = "a", device_name = "Data", mount_path = "/data" }
    ]
  }

  expect_failures = [var.attached_disks]
}

run "reject_too_long_device_name" {
  command = plan

  variables {
    attached_disks = [
      { disk_id = "a", device_name = "a234567890123456789012345678901234567890123456789012345678", mount_path = "/data" }
    ]
  }

  expect_failures = [var.attached_disks]
}
