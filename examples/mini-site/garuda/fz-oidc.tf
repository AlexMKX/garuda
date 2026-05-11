module "firezone_oidc" {
  source = "../../../roles/firezone_oidc/terraform"

  host_name = local.host_names.hub
  arguments = {
    firezone_oidc_dir        = local.firezone_facts.directory
    firezone_oidc_server_url = local.firezone_facts.server_url
    firezone_oidc_api_url    = null
    firezone_oidc_providers = {
      google = {
        client_id     = var.firezone_oidc_google_client_id
        client_secret = var.firezone_oidc_google_client_secret
        label         = "Google"
      }
    }
  }

  connection_data = var.connection_data_hub

  depends_on = [module.firezone]
}
