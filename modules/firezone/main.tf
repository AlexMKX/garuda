module "apply" {
  source = "../linux_apply"

  host_name     = var.host_name
  workload_kind = "firezone"
  payload = {
    fz_config = {
      fz_admin_password = var.admin_password
      fz_client_subnet  = var.client_subnet
      fz_server_url     = var.server_url
      fz_nic_attach     = var.nic_attach
    }
    fz_firezone_dir = var.firezone_dir
    firezone_labels = var.labels
  }

  connection_data = var.connection_data
  extra_hostvars  = var.extra_hostvars
}
