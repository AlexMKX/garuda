#!/bin/bash
# WireGuard PostUp script.
#
# Architecture:
#   - MSS clamp is installed unconditionally.  Path-MTU through any WG
#     tunnel is smaller than the negotiated TCP MSS by default; without
#     clamping, large segments black-hole.  This is independent of
#     whether the container egresses traffic to the public internet.
#   - NAT (oifname "border" masquerade) and RPDB (iif backbone lookup
#     via_tunnel) are installed only when "border" is present in
#     WG_NIC_ATTACH.  Internal-mesh participants (no border) install
#     no NAT and no RPDB so that source IPs propagate through the
#     backbone untouched — required for identity-aware features such
#     as the pinning portal at 1.1.1.1:1111.
#
# Operators deploying the role outside the standard Garuda topology
# can layer additional rules via WG_POST_UP (already injected into the
# wg-quick conf by entrypoint.sh, before this script runs).

set -e

TABLE_NAME="border_${WG_INTERFACE}"

# --- Block 1: nft table base + MSS clamp (always) ---
nft add table inet "$TABLE_NAME" 2>/dev/null || true
nft delete table inet "$TABLE_NAME" 2>/dev/null || true

nft -f - <<EOF
table inet ${TABLE_NAME} {
    chain forward {
        type filter hook forward priority mangle; policy accept;
        oifname "${WG_INTERFACE}" tcp flags syn tcp option maxseg size set rt mtu
    }
}
EOF

echo "[POSTUP] MSS clamp applied: oifname ${WG_INTERFACE} in table ${TABLE_NAME}"

# --- Block 2: gate on border attach ---
if ! echo "${WG_NIC_ATTACH:-[]}" | grep -q '"border"'; then
    echo "[POSTUP] border not in WG_NIC_ATTACH — skipping NAT and RPDB"
    exit 0
fi

# --- Block 3: nft NAT (border only) ---
# Append the postrouting chain to the existing table.  oifname
# "border" only: backbone is internal mesh, never masqueraded.
nft -f - <<EOF
table inet ${TABLE_NAME} {
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        ip daddr 10.0.0.0/8 return
        ip daddr 172.16.0.0/12 return
        ip daddr 192.168.0.0/16 return
        ip daddr 100.64.0.0/10 return
        oifname "border" masquerade
    }
}
EOF

echo "[POSTUP] border masquerade applied in table ${TABLE_NAME}"

# --- Block 4: RPDB via_tunnel (border only) ---
# Backbone-ingress transit traffic is directed into the WG tunnel
# instead of the local default route.  Locally-originated traffic
# (OSPF, health checks) is unaffected because the iif match only
# fires on forwarded packets.

mkdir -p /etc/iproute2
touch /etc/iproute2/rt_tables
grep -q '^101 via_tunnel$' /etc/iproute2/rt_tables \
    || echo '101 via_tunnel' >> /etc/iproute2/rt_tables

ip rule add pref 99 iif backbone lookup via_tunnel 2>/dev/null || true
ip route replace table via_tunnel default dev "$WG_INTERFACE"

# Keep intra-backbone traffic local (not tunneled).
BACKBONE_NET=$(ip -4 route list dev backbone scope link | head -1 | awk '{print $1}')
if [ -n "$BACKBONE_NET" ]; then
    ip route replace table via_tunnel "$BACKBONE_NET" dev backbone
fi

echo "[POSTUP] RPDB via_tunnel configured: iif backbone -> dev ${WG_INTERFACE}"
