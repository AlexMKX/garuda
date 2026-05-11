terraform {
  required_version = ">= 1.6.0"

  required_providers {
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5.3"
    }
    routeros = {
      source  = "terraform-routeros/routeros"
      version = ">= 1.86.0"
    }
    wireguard = {
      source  = "OJFord/wireguard"
      version = ">= 0.4.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }
  }
}
