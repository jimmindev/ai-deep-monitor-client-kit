#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="ai-deep-monitor-host-terminal"
INSTALL_DIR="/opt/ai-deep-monitor-host-terminal"
STATE_DIR="/var/lib/ai-deep-monitor-host-terminal"
UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
QUEUE_GID="${HOST_TERMINAL_QUEUE_GID:-10003}"
QUEUE_GROUP_NAME="${HOST_TERMINAL_QUEUE_GROUP:-ai-deep-terminal-queue}"

fail() {
  printf 'Erreur : %s\n' "$1" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || fail "l'installation doit être lancée avec sudo."
command -v systemctl >/dev/null 2>&1 || fail "systemd est requis sur cet hôte."
command -v python3 >/dev/null 2>&1 || fail "python3 est requis sur cet hôte."
command -v docker >/dev/null 2>&1 || fail "Docker est requis sur cet hôte."

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
JOBS_DIR="${PROJECT_ROOT}/host_terminal_jobs"
RUN_USER="${AI_DEEP_TERMINAL_USER:-${1:-${SUDO_USER:-}}}"
POLICY_SOURCE="${PROJECT_ROOT}/api/terminal_policy.py"
if [[ ! -f "${POLICY_SOURCE}" ]]; then
  POLICY_SOURCE="${SCRIPT_DIR}/terminal_policy.py"
fi

[[ -n "${RUN_USER}" && "${RUN_USER}" != "root" ]] || fail \
  "indiquez un utilisateur Linux non-root : sudo bash ./host_terminal_agent/install_linux_service.sh <utilisateur>."
id "${RUN_USER}" >/dev/null 2>&1 || fail "l'utilisateur ${RUN_USER} n'existe pas."
[[ -f "${SCRIPT_DIR}/agent.py" ]] || fail "agent.py est introuvable."
[[ -f "${POLICY_SOURCE}" ]] || fail "terminal_policy.py est introuvable."

RUN_GROUP="$(id -gn "${RUN_USER}")"
PYTHON_BIN="$(command -v python3)"
DOCKER_SOCKET="/var/run/docker.sock"
[[ -S "${DOCKER_SOCKET}" ]] || fail "le socket Docker ${DOCKER_SOCKET} est introuvable."
DOCKER_GID="$(stat -c '%g' "${DOCKER_SOCKET}")"
DOCKER_GROUP="$(getent group "${DOCKER_GID}" | cut -d: -f1 || true)"
[[ -n "${DOCKER_GROUP}" ]] || fail "aucun groupe système ne correspond au socket Docker."

QUEUE_GROUP="$(getent group "${QUEUE_GID}" | cut -d: -f1 || true)"
if [[ -z "${QUEUE_GROUP}" ]]; then
  if getent group "${QUEUE_GROUP_NAME}" >/dev/null 2>&1; then
    EXISTING_GID="$(getent group "${QUEUE_GROUP_NAME}" | cut -d: -f3)"
    [[ "${EXISTING_GID}" == "${QUEUE_GID}" ]] || fail \
      "le groupe ${QUEUE_GROUP_NAME} existe avec le GID ${EXISTING_GID}, attendu ${QUEUE_GID}."
  else
    groupadd --gid "${QUEUE_GID}" "${QUEUE_GROUP_NAME}"
  fi
  QUEUE_GROUP="${QUEUE_GROUP_NAME}"
fi

usermod --append --groups "${QUEUE_GROUP},${DOCKER_GROUP}" "${RUN_USER}"

install -d -o root -g root -m 0755 "${INSTALL_DIR}"
install -o root -g root -m 0755 "${SCRIPT_DIR}/agent.py" "${INSTALL_DIR}/agent.py"
install -o root -g root -m 0644 "${POLICY_SOURCE}" "${INSTALL_DIR}/terminal_policy.py"
install -d -o "${RUN_USER}" -g "${QUEUE_GROUP}" -m 0770 "${STATE_DIR}"
install -d -o "${RUN_USER}" -g "${QUEUE_GROUP}" -m 2770 "${JOBS_DIR}"

# Le bit setgid garantit que l'agent et l'API Docker partagent toujours le groupe
# de la file, même après un redémarrage ou la création de nouveaux sous-dossiers.
chown -R "${RUN_USER}:${QUEUE_GROUP}" "${JOBS_DIR}"
find "${JOBS_DIR}" -type d -exec chmod 2770 {} +
find "${JOBS_DIR}" -type f -exec chmod 0660 {} +

cat >"${UNIT_PATH}" <<EOF
[Unit]
Description=AI-Deep Monitor - agent terminal hote protege
After=local-fs.target docker.service
Wants=docker.service

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_GROUP}
SupplementaryGroups=${QUEUE_GROUP} ${DOCKER_GROUP}
WorkingDirectory=${STATE_DIR}
Environment="AI_DEEP_TERMINAL_POLICY_PATH=${INSTALL_DIR}/terminal_policy.py"
Environment="PYTHONUNBUFFERED=1"
ExecStart="${PYTHON_BIN}" "${INSTALL_DIR}/agent.py" --jobs-dir "${JOBS_DIR}" --install-dir "${PROJECT_ROOT}" --state-dir "${STATE_DIR}"
Restart=always
RestartSec=3
TimeoutStopSec=10
UMask=0007

# Confinement : aucun root, aucune capacité, système en lecture seule. Seuls la
# file signée, le répertoire d'état et l'installation à mettre à jour peuvent
# être modifiés par ce service. Le protocole signé n'accepte aucune commande
# Docker arbitraire : uniquement l'action de mise à jour validée.
NoNewPrivileges=true
CapabilityBoundingSet=
AmbientCapabilities=
ProtectSystem=strict
ProtectHome=read-only
ReadOnlyPaths="${INSTALL_DIR}"
ReadWritePaths="${STATE_DIR}" "${JOBS_DIR}" "${PROJECT_ROOT}"
PrivateTmp=true
PrivateDevices=true
ProtectClock=true
ProtectHostname=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
RestrictSUIDSGID=true
RestrictRealtime=true
LockPersonality=true
MemoryDenyWriteExecute=true
RemoveIPC=true

[Install]
WantedBy=multi-user.target
EOF

chmod 0644 "${UNIT_PATH}"
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}.service"
systemctl restart "${SERVICE_NAME}.service"

printf '\nAgent terminal installé pour %s.\n' "${RUN_USER}"
printf "Type d'hôte détecté : "
if [[ -f /etc/nv_tegra_release ]] || grep -Eiq 'jetson|nvidia' /proc/device-tree/model 2>/dev/null; then
  printf 'NVIDIA Jetson\n'
else
  printf 'Linux\n'
fi
printf 'État : systemctl status %s.service\n' "${SERVICE_NAME}"
printf 'Journaux : journalctl -u %s.service\n' "${SERVICE_NAME}"
