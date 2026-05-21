#!/bin/bash
# WireGuard PostUp script.
#
# Architecture:
#   - MSS clamp is installed unconditionally.  Path-MTU through any WG
#     tunnel is smaller than the negotiated TCP MSS by default; without
#     clamping, large segments black-hole.  This is independent of
#     whether the container egresses traffic to the public internet.
#   - NAT (oifname "border" masquerade) and RPDB steering are installed
#     only when "border" is present in WG_NIC_ATTACH. Internal-mesh
#     participants (no border) install no NAT and no RPDB so that source
#     IPs propagate through the backbone untouched — required for
#     identity-aware features such as the pinning portal at 1.1.1.1:1111.
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
#
# The same rule works under both topologies the role ships into:
#   * Compose hub stack — `border` is a docker bridge network; the
#     host adds a MASQUERADE rule on eth0 for traffic egressing the
#     bridge, so this in-container rule and the host rule chain
#     together to deliver the packet to the internet.
#   * k3s edge pod — `border` is a Multus NetworkAttachmentDefinition
#     backed by a Linux bridge plugin configured with
#     isGateway=true, ipMasq=true. The bridge plugin itself owns the
#     host-side iptables MASQUERADE rule (see
#     modules/garuda_k8s/charts/garuda/templates/nad-border.yaml),
#     so packets that leave the pod via `border` are masqueraded by
#     CNI before they hit the edge VM's primary NIC.
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
grep -q '^102 border_egress$' /etc/iproute2/rt_tables \
    || echo '102 border_egress' >> /etc/iproute2/rt_tables

ip rule add pref 99 iif backbone lookup via_tunnel 2>/dev/null || true
ip route replace table via_tunnel default dev "$WG_INTERFACE"

# Keep intra-backbone traffic local (not tunneled).
BACKBONE_NET=$(ip -4 route list dev backbone scope link | head -1 | awk '{print $1}')
if [ -n "$BACKBONE_NET" ]; then
    ip route replace table via_tunnel "$BACKBONE_NET" dev backbone
fi

echo "[POSTUP] RPDB via_tunnel configured: iif backbone -> dev ${WG_INTERFACE}"

# Tunnel-ingress transit traffic is directed to the border interface so
# the edge CNI bridge can apply its host-side masquerade. Private
# destinations deliberately throw back to the main table so internal
# routes learned by OSPF keep their normal next hop.
ip rule add pref 98 iif "$WG_INTERFACE" lookup border_egress 2>/dev/null || true
ip route replace table border_egress throw 10.0.0.0/8
ip route replace table border_egress throw 172.16.0.0/12
ip route replace table border_egress throw 192.168.0.0/16
ip route replace table border_egress throw 100.64.0.0/10
BORDER_CIDR=$(ip -4 route list dev border scope link | awk 'NR == 1 { print $1 }')
BORDER_NET=${BORDER_CIDR%/*}
IFS=. read -r BORDER_A BORDER_B BORDER_C BORDER_D <<EOF
${BORDER_NET}
EOF
BORDER_INT=$(( (BORDER_A << 24) + (BORDER_B << 16) + (BORDER_C << 8) + BORDER_D + 1 ))
BORDER_GW="$(( (BORDER_INT >> 24) & 255 )).$(( (BORDER_INT >> 16) & 255 )).$(( (BORDER_INT >> 8) & 255 )).$(( BORDER_INT & 255 ))"
ip route replace table border_egress default via "$BORDER_GW" dev border

echo "[POSTUP] RPDB border_egress configured: iif ${WG_INTERFACE} -> dev border"
