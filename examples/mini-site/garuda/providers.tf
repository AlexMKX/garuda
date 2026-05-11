provider "routeros" {
  hosturl  = "api://${var.routeros.management_host}"
  username = var.routeros.user
  password = var.routeros_password
  insecure = true
}
