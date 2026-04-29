resource "local_file" "payload" {
  filename = "${path.root}/terraform/generated/${var.name}.yml"
  content = yamlencode({
    docker_daemon_config = merge(
      {
        firewall-backend = var.docker_firewall_backend
      },
      var.docker_additional_config,
    )
    reboot_on_change = var.reboot_on_change
  })
}

module "apply" {
  source = "../linux_apply"

  host_name     = var.host_name
  workload_kind = "linux_host_prerequisites"
  payload       = yamldecode(local_file.payload.content)

  connection_data = var.connection_data
  extra_hostvars  = var.extra_hostvars

  depends_on = [local_file.payload]
}
