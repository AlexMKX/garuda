#!/bin/bash
# WireGuard PostUp script.
#
# Block 1 (always): nft masquerade + MSS clamping on backbone and wg tunnel
#   interfaces.
#   - oifname "backbone": masquerades transit traffic that exits via backbone
#     to the Docker host (outer-pt role — decrypted packets forwarded out).
#   - oifname WG_INTERFACE: masquerades transit traffic entering the wg tunnel
#     (rutestvpn role — packets forwarded into the encrypted tunnel).
#   - MSS clamping on the WG interface prevents TCP black-hole issues when
#     the effective path MTU is smaller than what the endpoints negotiate.
#
# Block 2 (border only): RPDB via_tunnel so backbone-ingress transit traffic
#   is directed into the WG tunnel instead of the local default route.

set -e

# --- Block 1: nft masquerade (always) ---
# Applied unconditionally so both tunnel roles work:
#   rutestvpn wg_uk: oifname WG_INTERFACE catches packets going into the tunnel.
#   outer-pt wg_uk:  oifname backbone catches decrypted packets forwarded to host.
# Private destinations are bypassed on both rules.

TABLE_NAME="border_${WG_INTERFACE}"

nft add table inet "$TABLE_NAME" 2>/dev/null || true
nft delete table inet "$TABLE_NAME" 2>/dev/null || true

nft -f - <<EOF
table inet ${TABLE_NAME} {
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        ip daddr 10.0.0.0/8 return
        ip daddr 172.16.0.0/12 return
        ip daddr 192.168.0.0/16 return
        ip daddr 100.64.0.0/10 return
        oifname "${WG_INTERFACE}" masquerade
        oifname "backbone" masquerade
        oifname "border" masquerade
    }

    chain forward {
        type filter hook forward priority mangle; policy accept;
        # Clamp MSS on TCP SYN/SYN-ACK entering the WG tunnel so that the
        # negotiated TCP segment size never exceeds the tunnel MTU minus headers.
        # This prevents TCP black-hole issues (large packets silently dropped)
        # when the path MTU through the tunnel is lower than what endpoints agree.
        oifname "${WG_INTERFACE}" tcp flags syn tcp option maxseg size set rt mtu
    }
}
EOF

echo "[POSTUP] nft masquerade + MSS clamp applied: oifname ${WG_INTERFACE} in table ${TABLE_NAME}"

# --- Block 2: RPDB via_tunnel (border only) ---
# When border is attached, transit traffic arriving on backbone must be
# directed into the WG tunnel (not default-routed via border).
# Locally-originated traffic (OSPF, health checks) is unaffected because
# iif only matches forwarded packets.

if ! echo "${WG_NIC_ATTACH:-[]}" | grep -q '"border"'; then
    echo "[POSTUP] border not in WG_NIC_ATTACH — skipping via_tunnel RPDB"
    exit 0
fi

echo "[POSTUP] Configuring via_tunnel RPDB for ${WG_INTERFACE}"

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
