#!/bin/bash
# WireGuard entrypoint: reconstruct ephemeral config from env vars and bring interface up.

set -e

handle_interrupt() {
    wg-quick down "/run/wireguard/${WG_INTERFACE}.conf"
    exit 1
}
trap 'handle_interrupt' SIGTERM

# Keepalive is mandatory for the peer-state healthcheck (see spec §6.1)
if [ -z "${WG_PEER_PERSISTENT_KEEPALIVE:-}" ]; then
    echo "WG_PEER_PERSISTENT_KEEPALIVE is required" >&2
    exit 1
fi
case "${WG_PEER_PERSISTENT_KEEPALIVE}" in
    *[!0-9]*)
        echo "WG_PEER_PERSISTENT_KEEPALIVE must be numeric" >&2
        exit 1
        ;;
esac
if [ "${WG_PEER_PERSISTENT_KEEPALIVE}" -le 0 ]; then
    echo "WG_PEER_PERSISTENT_KEEPALIVE must be > 0" >&2
    exit 1
fi

# Build ephemeral WireGuard config at /run/wireguard/<interface>.conf
mkdir -p /run/wireguard
conf="/run/wireguard/${WG_INTERFACE}.conf"

cat > "$conf" << EOF
[Interface]
Address = ${WG_ADDRESS}
PrivateKey = ${WG_PRIVATE_KEY}
Table = ${WG_TABLE}
EOF

# Append optional interface fields
if [ -n "${WG_LISTEN_PORT:-}" ]; then
    printf 'ListenPort = %s\n' "${WG_LISTEN_PORT}" >> "$conf"
fi
if [ -n "${WG_POST_UP:-}" ]; then
    printf 'PostUp = %s\n' "${WG_POST_UP}" >> "$conf"
fi
if [ -n "${WG_PRE_DOWN:-}" ]; then
    printf 'PreDown = %s\n' "${WG_PRE_DOWN}" >> "$conf"
fi

# Always inject postup/predown hooks: masquerade is needed on all wg_uk nodes.
# The scripts themselves check WG_NIC_ATTACH to gate border-specific logic (RPDB).
printf 'PostUp = /usr/local/bin/postup.sh\n' >> "$conf"
printf 'PreDown = /usr/local/bin/predown.sh\n' >> "$conf"

# Append peer section
cat >> "$conf" << EOF

[Peer]
PublicKey = ${WG_PEER_PUBLIC_KEY}
AllowedIPs = ${WG_PEER_ALLOWED_IPS}
EOF

# Append optional peer fields
if [ -n "${WG_PEER_PRESHARED_KEY:-}" ]; then
    printf 'PresharedKey = %s\n' "${WG_PEER_PRESHARED_KEY}" >> "$conf"
fi
if [ -n "${WG_PEER_ENDPOINT:-}" ]; then
    printf 'Endpoint = %s\n' "${WG_PEER_ENDPOINT}" >> "$conf"
fi
if [ -n "${WG_PEER_PERSISTENT_KEEPALIVE:-}" ]; then
    printf 'PersistentKeepalive = %s\n' "${WG_PEER_PERSISTENT_KEEPALIVE}" >> "$conf"
fi

chmod 0600 "$conf"

# Remove pre-existing interface if present
if ip link show "$WG_INTERFACE" &>/dev/null; then
    echo "Interface $WG_INTERFACE already exists, removing..."
    wg-quick down "$conf" 2>/dev/null || ip link delete "$WG_INTERFACE" 2>/dev/null || true
fi

wg-quick up "$conf"

# Keep container running indefinitely, allowing SIGTERM trap to fire
tail -f /dev/null &
wait $!
