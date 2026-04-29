#!/bin/sh
# FRR sidecar entrypoint for OSPF injector operator.
# Decodes base64-encoded FRR configuration from environment variables
# into /etc/frr/ and starts FRR.

set -e

# Validate required environment variables
missing=""
for var in FRR_CONF_B64 DAEMONS_B64 VTYSH_CONF_B64; do
    val=$(printenv "$var" 2>/dev/null || true)
    if [ -z "$val" ]; then
        missing="$missing $var"
    fi
done

if [ -n "$missing" ]; then
    echo "FATAL: missing required environment variables:$missing" >&2
    exit 1
fi

# Decode configuration files
echo "$FRR_CONF_B64"   | base64 -d > /etc/frr/frr.conf
echo "$DAEMONS_B64"    | base64 -d > /etc/frr/daemons
echo "$VTYSH_CONF_B64" | base64 -d > /etc/frr/vtysh.conf

# Resolve actual backbone interface name.
if [ -n "${BACKBONE_IP:-}" ]; then
    actual_iface=$(ip -j -4 addr show | python3 -c "
import json, sys
data = json.load(sys.stdin)
ip = '$BACKBONE_IP'
for iface in data:
    for addr in iface.get('addr_info', []):
        if addr.get('local', '') == ip:
            print(iface['ifname'])
            sys.exit(0)
")
    if [ -n "$actual_iface" ] && [ "$actual_iface" != "backbone" ]; then
        echo "backbone interface resolved: backbone -> $actual_iface (IP=$BACKBONE_IP)"
        sed -i "s/^interface backbone$/interface $actual_iface/" /etc/frr/frr.conf
    elif [ -z "$actual_iface" ]; then
        echo "WARNING: could not find interface for BACKBONE_IP=$BACKBONE_IP" >&2
    fi
fi

# Set correct ownership and permissions
chown -R frr:frr /etc/frr
chmod 640 /etc/frr/frr.conf /etc/frr/daemons /etc/frr/vtysh.conf

# Start transit watcher if PBR_TRANSIT_TAG is configured.
# The watcher polls OSPF LSDB for tagged default routes and programs
# the corresponding nexthop into the PBR kernel routing table.
if [ -n "${PBR_TRANSIT_TAG:-}" ]; then
    python3 /usr/lib/frr/transit_watcher.py &
fi

# Start vty HTTP bridge: exposes vtysh to sister containers on 127.0.0.1:7890.
python3 /usr/lib/frr/vty_bridge.py &

# Start FRR via its standard Docker entrypoint
exec /usr/lib/frr/docker-start
