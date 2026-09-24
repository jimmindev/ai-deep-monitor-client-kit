#!/usr/bin/env bash
set -Eeuo pipefail

NO_RECREATE=false
if [[ "${1:-}" == "--no-recreate" ]]; then
  NO_RECREATE=true
  shift
fi
[[ $# -eq 0 ]] || { echo 'Usage : install_linux_service.sh [--no-recreate]' >&2; exit 2; }

[[ ${EUID} -eq 0 ]] || { echo 'Lancer avec sudo.' >&2; exit 1; }
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
INSTALL_ROOT="${PROJECT_ROOT}"
if [[ ! -f "${INSTALL_ROOT}/.env" && -f "${PROJECT_ROOT}/../../.env" ]]; then
  INSTALL_ROOT="$(cd -- "${PROJECT_ROOT}/../.." && pwd -P)"
fi
for command in python3 lsblk mount findmnt docker systemctl; do
  command -v "${command}" >/dev/null || { echo "Commande manquante : ${command}" >&2; exit 1; }
done
[[ -f "${INSTALL_ROOT}/docker-compose.release.yml" && -f "${INSTALL_ROOT}/docker-compose.linux-host-storage.yml" && -f "${INSTALL_ROOT}/.env" ]] || {
  echo 'Fichiers Compose Linux ou .env manquants dans le dossier d’installation.' >&2
  exit 1
}

mkdir -p /media /mnt /run/media /media/ai-deep-monitor /opt/ai-deep-monitor-storage
[[ ! -L /media/ai-deep-monitor ]] || { echo 'Racine de montage non sûre.' >&2; exit 1; }
chown root:root /media/ai-deep-monitor
chmod 0755 /media/ai-deep-monitor
install -m 0755 "${SCRIPT_DIR}/auto_mount.py" /opt/ai-deep-monitor-storage/auto_mount.py
APP_UID="${AI_DEEP_STORAGE_UID:-1000}"
APP_GID="${AI_DEEP_STORAGE_GID:-1000}"
PYTHON_BIN="$(command -v python3)"
[[ "${APP_UID}" =~ ^[0-9]+$ && "${APP_GID}" =~ ^[0-9]+$ ]] || {
  echo 'Les identifiants de stockage doivent être numériques.' >&2
  exit 1
}

cat >/etc/systemd/system/ai-deep-monitor-storage.service <<EOF
[Unit]
Description=AI Deep Monitor - montage automatique des disques de données
After=local-fs.target
Before=docker.service

[Service]
Type=simple
User=root
ExecStart=${PYTHON_BIN} /opt/ai-deep-monitor-storage/auto_mount.py --uid ${APP_UID} --gid ${APP_GID}
Restart=always
RestartSec=5
NoNewPrivileges=true
CapabilityBoundingSet=CAP_SYS_ADMIN CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER
AmbientCapabilities=CAP_SYS_ADMIN CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ai-deep-monitor-storage.service
systemctl is-active --quiet ai-deep-monitor-storage.service || {
  journalctl -u ai-deep-monitor-storage.service -n 30 --no-pager >&2
  exit 1
}

# Recreate only the readers once so their rslave binds use the shared /media
# mount. Future USB hotplug events then appear without restarting containers.
if [[ "$NO_RECREATE" == "false" ]]; then
  docker compose -f "${INSTALL_ROOT}/docker-compose.release.yml" \
    -f "${INSTALL_ROOT}/docker-compose.linux-host-storage.yml" \
    --env-file "${INSTALL_ROOT}/.env" up -d --no-deps --force-recreate api backup-scheduler
fi
echo 'Montage automatique actif. Les disques de données apparaîtront sous /media/ai-deep-monitor.'
