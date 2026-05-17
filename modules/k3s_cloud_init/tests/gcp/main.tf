locals {
  labels = {
    garuda_role    = "k3s-validation"
    garuda_managed = "terraform"
    garuda_env     = var.env_slug
  }
}

resource "google_compute_disk" "k3s_data" {
  name    = "${var.env_slug}-k3s-data"
  project = var.gcp.project_id
  zone    = var.gcp.zone
  type    = "pd-balanced"
  size    = var.disk_size_gb
  labels  = local.labels

  lifecycle {
    prevent_destroy = false # validation root is disposable
  }
}

module "k3s_init" {
  source = "../.."

  k3s_version = var.k3s_version
}

module "host" {
  source = "../../../gcp_compute_host"

  name       = "k3s"
  env_slug   = var.env_slug
  project_id = var.gcp.project_id
  region     = var.gcp.region
  zone       = var.gcp.zone
  network    = var.gcp.network
  subnetwork = var.gcp.subnetwork

  ssh_keys        = var.ssh_keys
  default_ingress = true # SSH only matters; k3s API is on 127.0.0.1

  attached_disks = [
    {
      disk_id     = google_compute_disk.k3s_data.id
      device_name = "k3s-data"
      mount_path  = "/var/lib/rancher"
    },
  ]

  user_data_parts = module.k3s_init.user_data_parts

  labels = local.labels
}
