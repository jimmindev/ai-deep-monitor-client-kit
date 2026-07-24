#!/usr/bin/env bash

set -Eeuo pipefail

KIT_DIR="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../scripts/linux/client-common.sh
# shellcheck disable=SC1091
source "${KIT_DIR}/scripts/linux/client-common.sh"

available_ports="80 8001 8082"

port_is_available_for_project() {
  local port="$1"
  [[ " ${available_ports} " == *" ${port} "* ]]
}

[[ "$(select_runtime_port 80 8080 test-project)" == "80" ]]
[[ "$(select_runtime_port 8000 8001 test-project 80)" == "8001" ]]

available_ports="8082"
[[ "$(select_runtime_port 80 8080 test-project)" == "8082" ]]

available_ports="8001 8002"
[[ "$(select_runtime_port 8001 8001 test-project 8001)" == "8002" ]]

printf 'PORT_SELECTION_OK\n'
