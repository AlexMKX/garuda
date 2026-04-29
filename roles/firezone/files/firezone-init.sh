#!/bin/sh
# Firezone-local policy init. Runs inside the firezone container after startup.
#
# Scope: only firezone-local policies that travel with the container image.
# Transit PBR (iif wg-firezone -> transit routing table) is owned by transit_watcher.py
# in the FRR sidecar and MUST NOT be duplicated here.
set -e

FZ_CLIENT_IF="wg-firezone"

# Fail-closed leak prevention: when the transit table has no default route
# (transit provider down), prevent wg-firezone ingress from falling through
# to the host's main default route, which would bypass the geo-router.
# suppress_prefixlength 0 means "main table entries with prefix 0 (default)
# are ignored" — more specific routes in main (connected/internal) still apply.
ip rule add pref 200 iif "${FZ_CLIENT_IF}" lookup main suppress_prefixlength 0 \
    2>/dev/null || true

# MSS clamping on the wg-firezone forward path: clamp TCP SYN/SYN-ACK so the
# negotiated MSS never exceeds the effective tunnel MTU. Without this, large
# TCP segments silently black-hole inside the VPN tunnel.
nft add table inet mss_clamp_fz 2>/dev/null || true
nft delete table inet mss_clamp_fz 2>/dev/null || true
nft -f - <<EOF
table inet mss_clamp_fz {
    chain forward {
        type filter hook forward priority mangle; policy accept;
        iifname "${FZ_CLIENT_IF}" tcp flags syn tcp option maxseg size set rt mtu
    }
}
EOF
