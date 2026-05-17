data "yandex_vpc_network" "default" {
  network_id = var.yc.network_id
}

data "yandex_vpc_subnet" "primary" {
  subnet_id = var.yc.primary_subnet_id
}

locals {
  labels = {
    garuda_role    = "k3s-validation"
    garuda_managed = "terraform"
    garuda_env     = var.env_slug
  }
}

resource "yandex_compute_disk" "k3s_data" {
  name   = "${var.env_slug}-k3s-data"
  zone   = var.yc.zone
  type   = "network-ssd"
  size   = var.disk_size_gb
  labels = local.labels

  lifecycle {
    prevent_destroy = false # validation root is disposable
  }
}

module "k3s_init" {
  source = "../.."

  k3s_version = var.k3s_version
}

module "host" {
  source = "../../../yc_compute_host"

  name       = "k3s"
  env_slug   = var.env_slug
  zone       = var.yc.zone
  subnet_id  = data.yandex_vpc_subnet.primary.id
  network_id = data.yandex_vpc_network.default.id

  ssh_keys        = var.ssh_keys
  default_ingress = true # SSH only matters; k3s API is on 127.0.0.1

  attached_disks = [
    {
      disk_id     = yandex_compute_disk.k3s_data.id
      device_name = "k3s-data"
      mount_path  = "/var/lib/rancher"
    },
  ]

  user_data_parts = module.k3s_init.user_data_parts

  labels = local.labels
}
