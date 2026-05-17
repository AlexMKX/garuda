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

  # Disk mount cloud-config rendering. Empty string when attached_disks is
  # empty; the cloudinit_config data source then skips this part entirely.
  _disk_by_id_prefix = "/dev/disk/by-id/google"

  _mount_cloud_config = length(var.attached_disks) == 0 ? "" : yamlencode({
    fs_setup = [for d in var.attached_disks : {
      device     = "${local._disk_by_id_prefix}-${d.device_name}"
      filesystem = coalesce(d.fs_type, "ext4")
      label      = d.device_name
      overwrite  = false
    }]
    mounts = [for d in var.attached_disks : [
      "${local._disk_by_id_prefix}-${d.device_name}",
      d.mount_path,
      coalesce(d.fs_type, "ext4"),
      "defaults,nofail",
      "0",
      "2",
    ]]
    runcmd = concat(
      [for d in var.attached_disks : "mkdir -p ${d.mount_path}"],
      ["mount -a"],
    )
  })

  _auto_user_data_part = length(var.attached_disks) == 0 ? "" : "#cloud-config\n${local._mount_cloud_config}"

  # Whether to instantiate the cloudinit_config data source at all.
  needs_cloud_init = length(var.attached_disks) > 0 || length(var.user_data_parts) > 0

  firewall_enabled = var.default_ingress || length(var.ingress_ports) > 0
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

  managed_metadata = merge(
    { "ssh-keys" = local.ssh_keys_metadata },
    local.needs_cloud_init ? { "user-data" = data.cloudinit_config.this[0].rendered } : {},
  )
  effective_metadata = merge(local.managed_metadata, var.metadata)
}
