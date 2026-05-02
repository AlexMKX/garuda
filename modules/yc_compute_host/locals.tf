locals {
  # hostname_short: per-host name only, no env scope.
  # Used only as a building block for hostname below; never used in any
  # resource directly to avoid silent scope collisions.
  hostname_short = replace(var.name, "_", "-")

  # hostname: what the guest agent sets and what YC uses to compute
  # the per-VPC FQDN <hostname>.<zone>.internal. MUST embed env_slug
  # to keep two stacks with the same role distinct.
  hostname = "${var.env_slug}-${local.hostname_short}"

  # instance_name: what shows up in the YC console and CLI. Carries
  # the prefix as well to namespace garuda-managed instances away
  # from operator-managed ones.
  instance_name = "${var.prefix}-${local.hostname}"

  # SSH keys: single channel through metadata["ssh-keys"].
  # Module always generates a keypair for var.ssh_user. Operator/extra keys
  # in var.ssh_keys are appended verbatim. The cloud guest agent
  # (yandex-cloud-guest-agent on *-oslogin images) reads metadata and
  # writes per-user authorized_keys files live — no cloud-init users
  # block, no per-boot script, no reboot needed for rotation.
  ssh_keys_metadata = join("\n", concat(
    var.ssh_keys,
    ["${var.ssh_user}:${trimspace(tls_private_key.admin.public_key_openssh)}"],
  ))

  # Data disk effective presence
  data_disk_enabled = var.data_disk_size_gb > 0 || var.existing_data_disk_id != null
  data_disk_id      = var.existing_data_disk_id != null ? var.existing_data_disk_id : (
    var.data_disk_size_gb > 0 ? yandex_compute_disk.data[0].id : null
  )

  cloud_init = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    data_disk_enabled = local.data_disk_enabled
  })

  # Firewall / SG
  sg_enabled = var.default_ingress || length(var.ingress_ports) > 0

  default_ingress_rules = var.default_ingress ? [
    { protocol = "TCP", port = 22, description = "ssh", source_cidrs = ["0.0.0.0/0"] },
    { protocol = "TCP", port = 80, description = "http", source_cidrs = ["0.0.0.0/0"] },
    { protocol = "TCP", port = 443, description = "https", source_cidrs = ["0.0.0.0/0"] },
  ] : []

  # TCP/UDP rules only. ICMP is handled separately in main.tf because YC SG
  # resource has different schema for ICMP (no port field).
  # User-supplied ingress_ports must specify a port number; ICMP cannot be
  # added via ingress_ports — set default_ingress=true to include ICMP.
  all_ingress_rules = concat(local.default_ingress_rules, var.ingress_ports)

  effective_sg_ids = concat(
    local.sg_enabled ? [yandex_vpc_security_group.this[0].id] : [],
    var.security_group_ids,
  )

  # OS Login activation is opt-in (default false). Setting
  # enable-oslogin=true makes the guest agent abandon metadata['ssh-keys']
  # in favour of IAM-managed OS Login profiles; without org-level OS
  # Login + per-user profile + compute.osLogin role this locks every
  # account out of the VM, including the module-managed `garuda`
  # deploy user. Flip the variable to true on the call site only when
  # all three preconditions are in place.
  oslogin_metadata = var.oslogin_enabled ? { "enable-oslogin" = "true" } : {}

  managed_metadata = merge(
    {
      "ssh-keys"  = local.ssh_keys_metadata
      "user-data" = local.cloud_init
    },
    local.oslogin_metadata,
  )
  effective_metadata = merge(local.managed_metadata, var.metadata)
}
