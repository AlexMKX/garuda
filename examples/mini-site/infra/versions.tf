terraform {
  required_version = ">= 1.6.0"

  required_providers {
    yandex = {
      source  = "registry.terraform.io/yandex-cloud/yandex"
      version = ">= 0.130.0"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 4.40.0, < 5.0.0"
    }
    routeros = {
      source  = "terraform-routeros/routeros"
      version = ">= 1.86.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5.3"
    }
  }
}
