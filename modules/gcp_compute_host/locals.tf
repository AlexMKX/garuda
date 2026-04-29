locals {
  # hostname_short: per-host name only, no env scope.
  # Used only as a building block for hostname below; never used in any
  # resource directly to avoid silent scope collisions.
  hostname_short = replace(var.name, "_", "-")

  # hostname: short identifier embedded in the GCE FQDN via
  # google_compute_instance.hostname below.
  hostname = "${var.env_slug}-${local.hostname_short}"

  instance_name = "${var.prefix}-${local.hostname}"

  firewall_tag = "garuda-fw-${local.instance_name}"

  # SSH keys: single channel through metadata["ssh-keys"].
  # Module always generates a keypair for var.ssh_user. Operator/extra keys
  # in var.ssh_keys are appended verbatim. google-guest-agent (preinstalled
  # on every official Ubuntu image on GCP) reads metadata and writes
  # per-user authorized_keys files live — no cloud-init users block,
  # no per-boot script, no reboot needed for rotation.
  ssh_keys_metadata = join("\n", concat(
    var.ssh_keys,
    ["${var.ssh_user}:${trimspace(tls_private_key.admin.public_key_openssh)}"],
  ))

  # Data disk effective presence
  data_disk_enabled = var.data_disk_size_gb > 0 || var.existing_data_disk_id != null
  data_disk_source  = var.existing_data_disk_id != null ? var.existing_data_disk_id : (
    var.data_disk_size_gb > 0 ? google_compute_disk.data[0].self_link : null
  )

  cloud_init = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    data_disk_enabled = local.data_disk_enabled
  })

  firewall_enabled   = var.default_ingress || length(var.ingress_ports) > 0
  default_allow_list = var.default_ingress ? [
    { protocol = "tcp", ports = ["22"] },
    { protocol = "tcp", ports = ["80"] },
    { protocol = "tcp", ports = ["443"] },
    # Open the whole UDP range: every garuda host runs WireGuard and other
    # UDP services; opening 0-65535 avoids duplicating the workload port
    # list in infra and garuda configs.
    { protocol = "udp", ports = ["0-65535"] },
    { protocol = "icmp", ports = [] },
  ] : []
  extra_allow_list = [
    for rule in var.ingress_ports : {
      protocol = lower(rule.protocol)
      ports    = [tostring(rule.port)]
    }
  ]

  # NOTE: GCE firewall does not support per-allow-rule source CIDRs in a single resource.
  # All rules share the union of source_cidrs from default_ingress and ingress_ports.
  # If per-rule isolation is needed, use multiple module instances or manual firewall rules.
  ingress_source_cidrs = distinct(concat(
    var.default_ingress ? ["0.0.0.0/0"] : [],
    flatten([for rule in var.ingress_ports : rule.source_cidrs]),
  ))

  instance_tags = distinct(concat(var.tags, [local.firewall_tag]))

  managed_metadata = {
    "ssh-keys"  = local.ssh_keys_metadata
    "user-data" = local.cloud_init
  }
  effective_metadata = merge(local.managed_metadata, var.metadata)
}
