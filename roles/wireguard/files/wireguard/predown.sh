#!/bin/bash
# WireGuard PreDown script.
# Cleans up nft masquerade table (always) and RPDB via_tunnel (border only).

set -e

# --- Block 1: nft table cleanup (always) ---
TABLE_NAME="border_${WG_INTERFACE}"
nft add table inet "$TABLE_NAME" 2>/dev/null || true
nft delete table inet "$TABLE_NAME" 2>/dev/null || true
echo "[PREDOWN] nft table ${TABLE_NAME} removed"

# --- Block 2: RPDB via_tunnel cleanup (border only) ---
if ! echo "${WG_NIC_ATTACH:-[]}" | grep -q '"border"'; then
    exit 0
fi

ip rule del pref 99 iif backbone lookup via_tunnel 2>/dev/null || true
ip route flush table via_tunnel 2>/dev/null || true
echo "[PREDOWN] RPDB via_tunnel cleaned up"
