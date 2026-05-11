provider "yandex" {
  service_account_key_file = var.yc_service_account_key_json
  cloud_id                 = var.yc.cloud_id
  folder_id                = var.yc.folder_id
  zone                     = var.yc.zone
}

# Google provider is configured WITHOUT region/zone at the provider level
# because edges live in different regions (pt: us-central1, de: europe-west3).
# Each module call passes region/zone explicitly.
provider "google" {
  credentials = var.gcp_credentials_json
  project     = var.gcp.project_id
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "routeros" {
  hosturl  = "api://${var.routeros.management_host}"
  username = var.routeros.user
  password = var.routeros_password
  insecure = true
}
