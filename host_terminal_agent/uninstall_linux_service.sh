#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="ai-deep-monitor-host-terminal"
INSTALL_DIR="/opt/ai-deep-monitor-host-terminal"
STATE_DIR="/var/lib/ai-deep-monitor-host-terminal"
UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

if [[ "${EUID}" -ne 0 ]]; then
  printf 'Erreur : la désinstallation doit être lancée avec sudo.\n' >&2
  exit 1
fi

systemctl disable --now "${SERVICE_NAME}.service" 2>/dev/null || true
rm -f -- "${UNIT_PATH}"
rm -rf -- "${INSTALL_DIR}" "${STATE_DIR}"
systemctl daemon-reload
systemctl reset-failed "${SERVICE_NAME}.service" 2>/dev/null || true

printf 'Agent terminal Linux/Jetson désinstallé.\n'
printf 'La file host_terminal_jobs et sa clé ont été conservées.\n'
