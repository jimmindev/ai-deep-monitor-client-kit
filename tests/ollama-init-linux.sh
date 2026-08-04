#!/usr/bin/env bash

set -Eeuo pipefail

KIT_DIR="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
INSTALL_DIR="$(mktemp -d -t ai-monitor-ollama-test-XXXXXX)"
trap 'rm -rf -- "$INSTALL_DIR"' EXIT

"${KIT_DIR}/scripts/linux/install-client.sh" \
  --install-dir "$INSTALL_DIR" \
  --no-start \
  --skip-docker-login >/dev/null

compose_json="$(docker compose \
  -f "${KIT_DIR}/deploy/docker-compose.release.yml" \
  --env-file "${INSTALL_DIR}/.env" \
  config --format json)"

python3 -c '
import json
import sys

config = json.load(sys.stdin)
api_dependencies = config["services"]["api"].get("depends_on", {})
initializer = config["services"]["ollama-models"]
command = initializer["command"][0]

assert "ollama-models" not in api_dependencies
assert initializer["restart"] == "on-failure:3"
assert "Modele Ollama disponible" in command
assert "Modele Ollama installe" in command
assert "exit 0" in command
assert "exit 1" in command
' <<<"$compose_json"

printf 'OLLAMA_INIT_OK\n'
