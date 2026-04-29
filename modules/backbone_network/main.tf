module "apply" {
  source = "../linux_apply"

  host_name     = var.host_name
  workload_kind = "backbone_network"
  payload = {
    backbone_dir    = var.backbone_dir
    backbone_subnet = var.backbone_subnet
    border_subnet   = var.border_subnet
  }

  connection_data = var.connection_data
  extra_hostvars  = var.extra_hostvars
}
