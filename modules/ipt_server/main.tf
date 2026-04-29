module "apply" {
  source = "../linux_apply"

  host_name     = var.host_name
  workload_kind = "ipt_server"
  payload = {
    ipt_server_dir       = var.ipt_server_dir
    ipt_interfaces       = tolist(var.interfaces)
    ipt_routes           = [for route in var.routes : { for key, value in route : key => value if value != null }]
    ipt_nic_attach       = var.nic_attach
    ipt_clean_conntrack  = var.clean_conntrack
    ipt_domain_route_ttl = var.domain_route_ttl
    ipt_server_labels    = var.labels
  }

  connection_data = var.connection_data
  extra_hostvars  = var.extra_hostvars
}
