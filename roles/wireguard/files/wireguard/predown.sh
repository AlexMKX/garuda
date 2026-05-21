#!/bin/bash
# WireGuard PreDown script — symmetric to postup.sh.
#
# Block 1 (always): tear down the nft table created by postup's Block 1.
# Block 2 (border only): clean up the RPDB tables installed by postup.

set -e

# --- Block 1: nft table cleanup (always) ---
TABLE_NAME="border_${WG_INTERFACE}"
nft add table inet "$TABLE_NAME" 2>/dev/null || true
nft delete table inet "$TABLE_NAME" 2>/dev/null || true
echo "[PREDOWN] nft table ${TABLE_NAME} removed"

# --- Block 2: gate on border attach ---
if ! echo "${WG_NIC_ATTACH:-[]}" | grep -q '"border"'; then
    exit 0
fi

# --- Block 3: RPDB cleanup (border only) ---
ip rule del pref 99 iif backbone lookup via_tunnel 2>/dev/null || true
ip rule del pref 98 iif "$WG_INTERFACE" lookup border_egress 2>/dev/null || true
ip route flush table via_tunnel 2>/dev/null || true
ip route flush table border_egress 2>/dev/null || true
echo "[PREDOWN] RPDB via_tunnel and border_egress cleaned up"
