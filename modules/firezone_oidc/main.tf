module "apply" {
  source = "../linux_apply"

  host_name     = var.host_name
  workload_kind = "firezone_oidc"

  payload = {
    firezone_oidc_config = {
      firezone_dir   = var.firezone_dir
      server_url     = var.server_url
      oidc_providers = var.oidc_providers
    }
  }

  destroy_payload_override = {
    firezone_oidc_config = {
      firezone_dir   = var.firezone_dir
      server_url     = var.server_url
      oidc_providers = {}
    }
  }

  connection_data = var.connection_data
}
