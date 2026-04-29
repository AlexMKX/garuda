# modules/wireguard/routeros/versions.tf

terraform {
  required_providers {
    routeros = {
      source = "terraform-routeros/routeros"
    }
    # Used by data.dns_a_record_set in bypass.tf to resolve the WG peer
    # endpoint hostname into IP addresses, which drive launch_trigger of
    # the endpoint sync script (kicks the script on apply when the IP
    # changes; null -> resolved transition triggers it on first apply).
    dns = {
      source = "hashicorp/dns"
    }
  }
}
