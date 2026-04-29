#!/bin/bash
# WireGuard health check: peer-state using wg transfer counters + handshake age.

set -euo pipefail

WG_INTERFACE="${WG_INTERFACE:-wg0}"

# Validate WG_PEER_PERSISTENT_KEEPALIVE (unconditionally required; see spec §6.1)
if [[ -z "${WG_PEER_PERSISTENT_KEEPALIVE:-}" ]]; then
    echo "WG_PEER_PERSISTENT_KEEPALIVE is required" >&2
    exit 1
fi
if ! [[ $WG_PEER_PERSISTENT_KEEPALIVE =~ ^[0-9]+$ ]]; then
    echo "WG_PEER_PERSISTENT_KEEPALIVE must be numeric — invalid keepalive value" >&2
    exit 1
fi
if [[ "${WG_PEER_PERSISTENT_KEEPALIVE}" -le 0 ]]; then
    echo "WG_PEER_PERSISTENT_KEEPALIVE must be > 0 — keepalive must be greater than zero" >&2
    exit 1
fi

# Sample 1: read tx and rx transfer counters
read -r _peer tx_before rx_before <<< "$(wg show "$WG_INTERFACE" transfer | head -n 1)"

# Wait one sample window
sleep 10

# Sample 2: read tx and rx transfer counters again
read -r _peer tx_after rx_after <<< "$(wg show "$WG_INTERFACE" transfer | head -n 1)"

# Read latest handshake timestamp and compute age in seconds (empty = absent/never)
handshake_ts="$(wg show "$WG_INTERFACE" latest-handshakes | head -n 1 | awk '{print $2}')"
now="$(date +%s)"
if [ -z "$handshake_ts" ] || [ "$handshake_ts" = "0" ]; then
    handshake=""
else
    handshake=$(( now - handshake_ts ))
fi

# Compute handshake state: absent / stale (>= 300s) / recent (< 300s)
if [ -z "$handshake" ]; then
    hs=absent
elif (( handshake >= 300 )); then
    hs=stale
else
    hs=recent
fi

# Compute tx and rx deltas between the two samples
tx=$(( tx_after - tx_before ))
rx=$(( rx_after - rx_before ))

# Decision chain: evaluate all explicit outcomes

# tx regression: tx counter went backward
if (( tx < 0 )); then
    exit 1
# rx regression: rx counter went backward
elif (( rx < 0 )); then
    exit 1
# any rx increase means traffic is flowing in — healthy
elif (( rx > 0 )); then
    exit 0
# idle: tx==0 rx==0 — outcome depends on handshake state
elif (( tx == 0 )) && (( rx == 0 )) && [ "$hs" = recent ]; then
    exit 0
elif (( tx == 0 )) && (( rx == 0 )) && [ "$hs" = absent ]; then
    exit 1
elif (( tx == 0 )) && (( rx == 0 )); then
    exit 1
# tx-only: tx > 0 rx==0 — outcome depends on handshake state
elif (( tx > 0 )) && (( !rx )) && [ "$hs" = recent ]; then
    exit 0
elif (( tx > 0 )) && (( !rx )); then
    exit 1
else
    exit 1
fi
