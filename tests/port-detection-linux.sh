#!/usr/bin/env bash

set -Eeuo pipefail

KIT_DIR="${1:-/kit}"

# shellcheck disable=SC1091
source "${KIT_DIR}/client-common.sh"

port_is_available 80
selected_port="$(available_port 80)"
[[ "$selected_port" == "80" ]]
printf 'NON_ROOT_PORT_OK selected=%s\n' "$selected_port"

python3 -m http.server 18080 >/tmp/ai-monitor-port-test.log 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
sleep 1

if port_is_available 18080; then
  die "Le port de test 18080 aurait du etre detecte comme occupe."
fi

port_is_available 18081
selected_port="$(available_port 18080)"
[[ "$selected_port" == "18081" ]]
printf 'OCCUPIED_PORT_OK selected=%s\n' "$selected_port"
