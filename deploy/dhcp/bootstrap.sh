#!/bin/sh
set -eu

CONFIG=/etc/kea/kea-dhcp4.conf
mkdir -p /etc/kea /dhcp/control /var/lib/kea
if [ ! -s "$CONFIG" ]; then
  cat > "$CONFIG" <<'JSON'
{
  "Dhcp4": {
    "interfaces-config": { "interfaces": [], "dhcp-socket-type": "raw" },
    "control-socket": { "socket-type": "unix", "socket-name": "/dhcp/control/kea4-ctrl-socket" },
    "lease-database": { "type": "memfile", "persist": true, "name": "/var/lib/kea/kea-leases4.csv" },
    "valid-lifetime": 3600,
    "max-valid-lifetime": 86400,
    "authoritative": true,
    "subnet4": []
  }
}
JSON
fi
exec kea-dhcp4 -c "$CONFIG"
