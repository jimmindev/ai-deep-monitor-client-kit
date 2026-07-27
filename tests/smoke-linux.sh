#!/usr/bin/env bash

set -Eeuo pipefail

KIT_DIR="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
INSTALL_DIR="$(mktemp -d -t ai-monitor-kit-test-XXXXXX)"
trap 'rm -rf -- "$INSTALL_DIR"' EXIT

"${KIT_DIR}/scripts/linux/install-client.sh" \
  --install-dir "$INSTALL_DIR" \
  --no-start \
  --skip-docker-login

grep -Fxq 'KIT_VERSION=v0.1.11' "${INSTALL_DIR}/.env"
grep -Fxq 'APP_VERSION=v0.1.5' "${INSTALL_DIR}/.env"
grep -Fxq 'DOCKER_PLATFORM=linux/amd64' "${INSTALL_DIR}/.env"
grep -Fxq 'OLLAMA_MODEL=llama3.2:3b' "${INSTALL_DIR}/.env"
grep -Fxq 'OLLAMA_FALLBACK_MODEL=llama3.2:1b' "${INSTALL_DIR}/.env"
test -x "${INSTALL_DIR}/update-client.sh"
test -x "${INSTALL_DIR}/backup-maintenance.sh"
test -x "${INSTALL_DIR}/ai-deep-monitor.sh"
test -f "${INSTALL_DIR}/docker-compose.release.yml"
test -f "${INSTALL_DIR}/client-platform.ps1"

sed -i 's/^OLLAMA_MODEL=.*/OLLAMA_MODEL=llama3.1/' "${INSTALL_DIR}/.env"
sed -i 's/^OLLAMA_FALLBACK_MODEL=.*/OLLAMA_FALLBACK_MODEL=llama3.1/' "${INSTALL_DIR}/.env"
"${INSTALL_DIR}/update-client.sh" \
  --install-dir "$INSTALL_DIR" \
  --no-start \
  --app-version v0.1.5

grep -Fxq 'KIT_VERSION=v0.1.11' "${INSTALL_DIR}/.env"
grep -Fxq 'OLLAMA_MODEL=llama3.2:3b' "${INSTALL_DIR}/.env"
grep -Fxq 'OLLAMA_FALLBACK_MODEL=llama3.2:1b' "${INSTALL_DIR}/.env"

BACKUP_DIR="${INSTALL_DIR}/test-backups"
mkdir -p "$BACKUP_DIR"
touch -d '2026-01-01' "${BACKUP_DIR}/ai-deep-monitor-old.tar.gz"
touch -d '2026-01-02' "${BACKUP_DIR}/ai-deep-monitor-middle.tar.gz"
touch -d '2026-01-03' "${BACKUP_DIR}/ai-deep-monitor-new.tar.gz"
"${INSTALL_DIR}/backup-maintenance.sh" \
  --install-dir "$INSTALL_DIR" \
  --backup-dir "$BACKUP_DIR" \
  --action prune \
  --keep 2 \
  --yes
test "$(find "$BACKUP_DIR" -maxdepth 1 -type f | wc -l)" -eq 2
test ! -e "${BACKUP_DIR}/ai-deep-monitor-old.tar.gz"
"${INSTALL_DIR}/backup-maintenance.sh" \
  --install-dir "$INSTALL_DIR" \
  --backup-dir "$BACKUP_DIR" \
  --action delete-selected \
  --file "ai-deep-monitor-middle.tar.gz" \
  --yes
test "$(find "$BACKUP_DIR" -maxdepth 1 -type f | wc -l)" -eq 1
test ! -e "${BACKUP_DIR}/ai-deep-monitor-middle.tar.gz"
test -e "${BACKUP_DIR}/ai-deep-monitor-new.tar.gz"
printf 'LINUX_NO_START_OK\n'
