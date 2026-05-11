# Resources required on a fresh RouterOS install before any other module
# can usefully apply. These were previously in vpn2/main.tf and moved here
# because they belong to the infra layer (bootstrap primitives, not
# workloads).

resource "routeros_interface_list" "lan" {
  name    = "LAN"
  comment = "garuda"
}

resource "routeros_ip_dns" "this" {
  servers = ["1.1.1.1", "8.8.8.8"]
}
