terraform {
  required_version = ">= 1.10.0"

  # Rationale: provider `for_each` (used in providers.tf for edge
  # k3s providers) requires OpenTofu >= 1.10 or Terraform >= 1.13.
  # The >= 1.10 floor satisfies OpenTofu; Terraform users would need
  # to bump past 1.13 separately — that is not expressible as a
  # single required_version range, so we document but do not gate
  # on it. The native error from older Terraform is self-explanatory.

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
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.30.0"
    }
  }
}
