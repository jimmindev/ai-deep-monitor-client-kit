#!/bin/sh
set -eu
umask 0007

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
# Kea 2.6.3 requires its control directory to have mode 0750.
export KEA_CONTROL_SOCKET_DIR=/dhcp/control
kea-dhcp4 -c "$CONFIG" &
server_pid=$!
trap 'kill -TERM "$server_pid" 2>/dev/null || true' TERM INT
# Share only the private socket with the application group; never open it to others.
while kill -0 "$server_pid" 2>/dev/null; do
  if [ -S /dhcp/control/kea4-ctrl-socket ]; then
    chmod 0660 /dhcp/control/kea4-ctrl-socket
  fi
  sleep 1 &
  wait $! || true
done
wait "$server_pid"
