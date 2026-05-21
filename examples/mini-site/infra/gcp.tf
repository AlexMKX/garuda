module "k3s_init_edges" {
  for_each = var.edges

  source = "./modules/k3s_cloud_init"

  # The WireGuard pod template (modules/wireguard/kube/charts/wireguard/templates/deployment.yaml)
  # sets three pod-scope sysctls inside its netns:
  #   * net.ipv4.ip_forward=1                — required so the pod can
  #     forward traffic between its wg interface and the backbone NAD.
  #   * net.ipv4.conf.all.src_valid_mark=1   — required for the
  #     WireGuard fwmark return-path; otherwise replies on the wg
  #     interface are dropped by the RPF check.
  #   * net.ipv4.conf.all.rp_filter=2        — loose RPF; the Garuda
  #     transit topology has asymmetric paths through neighbour edges,
  #     strict RPF would drop them.
  # All three are flagged "unsafe" by upstream kubelet and must be
  # allow-listed at k3s install time; otherwise the pod lands in
  # `Status: Failed; Reason: SysctlForbidden` and the ReplicaSet keeps
  # spawning new replicas until the helm_release wait times out.
  extra_flags = [
    "--kubelet-arg=allowed-unsafe-sysctls=net.ipv4.ip_forward,net.ipv4.conf.all.src_valid_mark,net.ipv4.conf.all.rp_filter",
  ]
}

module "gcp_edges" {
  for_each = var.edges

  source = "./modules/gcp_compute_host"

  name              = each.key
  env_slug          = var.env_slug
  project_id        = var.gcp.project_id
  region            = each.value.region
  zone              = each.value.zone
  machine_type      = each.value.machine_type
  boot_disk_size_gb = each.value.boot_disk_gb

  ssh_keys = var.operator_ssh_keys

  allocate_static_ip = true

  # default_ingress opens TCP 22/80/443, UDP 0-65535, ICMP — covers WireGuard.
  default_ingress = true

  user_data_parts = module.k3s_init_edges[each.key].user_data_parts

  labels = {
    garuda_role    = "edge"
    garuda_managed = "terraform"
    garuda_env     = var.env_slug
  }
}
