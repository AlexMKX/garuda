mock_provider "yandex" {}

variables {
  env_slug     = "test-env"
  ssh_keys     = []
  disk_size_gb = 20
  k3s_version  = null
  yc = {
    cloud_id          = "cloud-x"
    folder_id         = "folder-x"
    zone              = "ru-central1-d"
    network_id        = "net-x"
    primary_subnet_id = "subnet-x"
  }
}

run "attached_disk_uses_k3s_data_device_and_mount" {
  command = plan

  assert {
    condition     = yandex_compute_disk.k3s_data.name == "test-env-k3s-data"
    error_message = "Caller-owned disk must be named {env_slug}-k3s-data."
  }

  assert {
    condition     = can(regex("/dev/disk/by-id/virtio-k3s-data", module.host.test_cloud_init_user_data))
    error_message = "device_name='k3s-data' must surface as the by-id path in user-data."
  }

  assert {
    condition     = can(regex("/var/lib/rancher", module.host.test_cloud_init_user_data))
    error_message = "mount_path /var/lib/rancher must appear in rendered user-data."
  }
}

run "user_data_carries_k3s_installer_and_bind" {
  command = plan

  assert {
    condition     = can(regex("curl -sfL https://get.k3s.io", module.host.test_cloud_init_user_data))
    error_message = "k3s installer pipe must appear in user-data."
  }

  assert {
    condition     = can(regex("--tls-san=127.0.0.1", module.host.test_cloud_init_user_data))
    error_message = "Invariant --tls-san=127.0.0.1 must appear in user-data."
  }

  assert {
    condition     = can(regex("--https-listen-port=6443", module.host.test_cloud_init_user_data))
    error_message = "Invariant --https-listen-port=6443 must appear in user-data."
  }
}

run "version_pin_surfaces_in_user_data" {
  command = plan

  variables {
    k3s_version = "v1.30.5+k3s1"
  }

  assert {
    condition     = can(regex("INSTALL_K3S_VERSION=v1.30.5\\+k3s1", module.host.test_cloud_init_user_data))
    error_message = "Pinned k3s_version must propagate into rendered user-data."
  }
}

run "outputs_passthrough_connection_data_and_public_ipv4" {
  command = plan

  assert {
    condition     = output.connection_data != null
    error_message = "connection_data output must be wired."
  }
}
