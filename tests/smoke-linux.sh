#!/usr/bin/env bash

set -Eeuo pipefail

KIT_DIR="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
INSTALL_DIR="$(mktemp -d -t ai-monitor-kit-test-XXXXXX)"
trap 'rm -rf -- "$INSTALL_DIR"' EXIT

"${KIT_DIR}/scripts/linux/install-client.sh" \
  --install-dir "$INSTALL_DIR" \
  --no-start \
  --skip-docker-login

grep -Fxq 'KIT_VERSION=v0.1.7' "${INSTALL_DIR}/.env"
grep -Fxq 'APP_VERSION=v0.1.5' "${INSTALL_DIR}/.env"
grep -Fxq 'DOCKER_PLATFORM=linux/amd64' "${INSTALL_DIR}/.env"
test -x "${INSTALL_DIR}/update-client.sh"
test -x "${INSTALL_DIR}/ai-deep-monitor.sh"
test -f "${INSTALL_DIR}/docker-compose.release.yml"
test -f "${INSTALL_DIR}/client-platform.ps1"

"${INSTALL_DIR}/update-client.sh" \
  --install-dir "$INSTALL_DIR" \
  --no-start \
  --app-version v0.1.5

grep -Fxq 'KIT_VERSION=v0.1.7' "${INSTALL_DIR}/.env"
printf 'LINUX_NO_START_OK\n'
