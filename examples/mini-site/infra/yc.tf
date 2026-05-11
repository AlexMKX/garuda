# Default VPC and the primary subnet are pre-existing — consumed as data.
data "yandex_vpc_network" "default" {
  network_id = var.yc.network_id
}

data "yandex_vpc_subnet" "primary" {
  subnet_id = var.yc.primary_subnet_id
}

module "yc_hub" {
  source = "./modules/yc_compute_host"

  name       = "hub"
  env_slug   = var.env_slug
  zone       = var.yc.zone
  subnet_id  = data.yandex_vpc_subnet.primary.id
  network_id = data.yandex_vpc_network.default.id

  cores             = var.hub.cores
  memory_gb         = var.hub.memory_gb
  boot_disk_size_gb = var.hub.boot_disk_gb

  # data_disk: create new by default; attach existing if explicitly requested.
  data_disk_size_gb     = var.hub.existing_disk_id == null ? var.hub.data_disk_gb : 0
  existing_data_disk_id = var.hub.existing_disk_id

  ssh_keys = var.operator_ssh_keys

  # default_ingress opens TCP 22/80/443, UDP 0-65535, ICMP — covers all
  # WireGuard tunnels and Firezone UDP 51620.
  default_ingress = true

  labels = {
    garuda_role    = "hub"
    garuda_managed = "terraform"
    garuda_env     = var.env_slug
  }
}
