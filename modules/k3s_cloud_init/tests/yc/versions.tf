terraform {
  required_version = ">= 1.6.0"

  required_providers {
    yandex = {
      source  = "registry.terraform.io/yandex-cloud/yandex"
      version = ">= 0.130.0"
    }
  }
}
