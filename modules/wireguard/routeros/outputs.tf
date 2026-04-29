# modules/wireguard/routeros/outputs.tf
#
# Public surface for callers that need to attach extra resources to
# this tunnel's RouterOS-side state. Primary use case: installing a
# physical-WAN default route into the per-tunnel bypass table from
# the call-site.

output "bypass_table_name" {
  description = <<-EOT
    Name of the per-tunnel routing table used for WG handshake bypass.
    The caller MUST install at least one default route into this table
    (typically `0.0.0.0/0` via the physical WAN interface); without it,
    the PBR rule directing handshake packets to this table has no
    nexthop and packets will be dropped when this tunnel becomes the
    main default route (e.g. via OSPF redistribute).

    The bypass table itself is created by the module so that callers
    have a stable target to populate without racing the endpoint sync
    script.
  EOT
  value       = routeros_routing_table.wg_bypass.name
}
