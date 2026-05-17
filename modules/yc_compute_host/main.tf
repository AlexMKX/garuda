data "yandex_compute_image" "os" {
  family    = var.image_family
  folder_id = var.image_folder_id
}

# Used to resolve network_id for the module-managed security group and the
# network_id output. The data source uses the default provider folder. If the
# subnet is in a different folder, pass var.network_id directly to avoid this
# lookup (see variables.tf).
data "yandex_vpc_subnet" "primary" {
  subnet_id = var.subnet_id
}

# SSH key for the module-managed deploy user. Always generated. Public key
# goes into metadata["ssh-keys"] together with var.ssh_keys; private key is
# exposed via outputs.connection_data.ssh_private_key. No filesystem dump —
# callers must consume the key through the output.
resource "tls_private_key" "admin" {
  algorithm = "ED25519"
}

# Module-managed Security Group
resource "yandex_vpc_security_group" "this" {
  count       = local.sg_enabled ? 1 : 0
  name        = "${local.instance_name}-sg"
  description = "Managed by garuda yc_compute_host for ${local.instance_name}"
  network_id  = coalesce(var.network_id, data.yandex_vpc_subnet.primary.network_id)

  dynamic "ingress" {
    for_each = local.all_ingress_rules
    content {
      description    = ingress.value.description
      protocol       = ingress.value.protocol
      port           = ingress.value.port
      v4_cidr_blocks = ingress.value.source_cidrs
    }
  }

  # ICMP is a separate block because YC SG ICMP rules don't have a port field.
  dynamic "ingress" {
    for_each = var.default_ingress ? [1] : []
    content {
      description    = "icmp-v4"
      protocol       = "ICMP"
      v4_cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # UDP 0-65535 is a separate block because it needs from_port/to_port
  # (port range), which cannot be expressed via ingress_ports (single port
  # per rule). Every garuda host runs WireGuard and other UDP services on
  # many ports; opening the whole UDP range avoids duplicating the workload
  # port list in infra and garuda configs.
  dynamic "ingress" {
    for_each = var.default_ingress ? [1] : []
    content {
      description    = "udp-all"
      protocol       = "UDP"
      from_port      = 0
      to_port        = 65535
      v4_cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    description    = "all-outbound"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_compute_instance" "this" {
  name        = local.instance_name
  hostname    = local.hostname
  zone        = var.zone
  platform_id = var.platform_id

  allow_stopping_for_update = true

  resources {
    cores         = var.cores
    memory        = var.memory_gb
    core_fraction = var.core_fraction
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.os.id
      size     = var.boot_disk_size_gb
      type     = var.boot_disk_type
    }
  }

  dynamic "secondary_disk" {
    for_each = { for d in var.attached_disks : d.device_name => d }
    content {
      disk_id     = secondary_disk.value.disk_id
      device_name = secondary_disk.key
      mode        = "READ_WRITE"
    }
  }

  network_interface {
    subnet_id          = var.subnet_id
    nat                = var.nat
    security_group_ids = local.effective_sg_ids
  }

  scheduling_policy {
    preemptible = var.preemptible
  }

  labels   = var.labels
  metadata = local.effective_metadata

  # metadata["ssh-keys"] flows through to the guest agent
  # (yandex-cloud-guest-agent on *-oslogin family). Rotating
  # tls_private_key.admin or var.ssh_keys triggers an in-place metadata
  # update; the agent rewrites per-user authorized_keys within seconds.
  # No reboot required. allow_stopping_for_update must be true for YC to
  # apply metadata changes on a running instance (see variables.tf).
}

