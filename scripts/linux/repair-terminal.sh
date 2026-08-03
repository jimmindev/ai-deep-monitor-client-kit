#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=client-common.sh
source "${SCRIPT_DIR}/client-common.sh"

INSTALL_DIR="${HOME}/ai-deep-monitor"
CHECK_ONLY=false

usage() {
  cat <<'EOF'
Usage: ./repair-terminal.sh [--install-dir CHEMIN] [--check-only]

Installe, repare puis verifie l'agent du terminal hote Linux/NVIDIA Jetson.
EOF
}

while (($#)); do
  case "$1" in
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    --install-dir=*) INSTALL_DIR="${1#*=}"; shift ;;
    --check-only) CHECK_ONLY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Option inconnue: $1" ;;
  esac
done

[[ -d "$INSTALL_DIR" ]] || die "Installation introuvable: ${INSTALL_DIR}"
INSTALL_DIR="$(cd "$INSTALL_DIR" && pwd -P)"
ENV_FILE="${INSTALL_DIR}/.env"
AGENT_DIR="${INSTALL_DIR}/host_terminal_agent"
INSTALLER="${AGENT_DIR}/install_linux_service.sh"
SERVICE_NAME="ai-deep-monitor-host-terminal.service"
STATUS_FILE="${INSTALL_DIR}/host_terminal_jobs/status.json"
KEY_FILE="${INSTALL_DIR}/host_terminal_jobs/.agent-key"

resolve_terminal_user() {
  local candidate=""
  local owner=""
  owner="$(stat -c '%U' "$INSTALL_DIR" 2>/dev/null || true)"
  for candidate in \
    "${AI_DEEP_TERMINAL_USER:-}" \
    "${SUDO_USER:-}" \
    "$owner" \
    "${USER:-}" \
    "$(logname 2>/dev/null || true)"; do
    [[ -n "$candidate" && "$candidate" != "root" ]] || continue
    if id "$candidate" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

status_is_fresh() {
  [[ -r "$STATUS_FILE" && -r "$KEY_FILE" ]] || return 1
  python3 - "$STATUS_FILE" <<'PY'
import json
import sys
import time

try:
    envelope = json.load(open(sys.argv[1], encoding="utf-8"))
    payload = envelope.get("payload") or {}
    last_seen = float(payload.get("last_seen") or 0)
except (OSError, TypeError, ValueError, json.JSONDecodeError):
    raise SystemExit(1)

if not envelope.get("signature") or payload.get("available") is not True:
    raise SystemExit(1)
raise SystemExit(0 if time.time() - last_seen <= 15 else 1)
PY
}

show_diagnostics() {
  configure_sudo
  warn "Diagnostic du service terminal hote:"
  run_root systemctl --no-pager --full status "$SERVICE_NAME" 2>&1 || true
  warn "Derniers journaux du service:"
  run_root journalctl --no-pager -u "$SERVICE_NAME" -n 60 2>&1 || true
}

verify_terminal_agent() {
  local attempt
  configure_sudo
  for attempt in {1..15}; do
    if run_root systemctl is-active --quiet "$SERVICE_NAME" && status_is_fresh; then
      log "Terminal hote operationnel: service actif et liaison Docker validee."
      return 0
    fi
    sleep 1
  done
  show_diagnostics
  return 1
}

if [[ "$CHECK_ONLY" == "true" ]]; then
  verify_terminal_agent || die "Le terminal hote est hors ligne. Lancez la reparation depuis le menu client."
  exit 0
fi

[[ -f "$ENV_FILE" ]] || die "Configuration introuvable: ${ENV_FILE}"
[[ -f "$INSTALLER" ]] || die "Agent terminal absent du kit: ${INSTALLER}"
command -v systemctl >/dev/null 2>&1 || die "systemd est requis sur Linux/NVIDIA Jetson."
ensure_python3 || die "Python 3 n'a pas pu etre installe."
run_user="$(resolve_terminal_user || true)"
[[ -n "$run_user" ]] || die \
  "Utilisateur non-root introuvable. Relancez avec AI_DEEP_TERMINAL_USER=mon_compte."
queue_gid="$(read_env_value "$ENV_FILE" HOST_TERMINAL_QUEUE_GID)"
queue_gid="${queue_gid:-10003}"

configure_sudo
log "Installation/reparation du terminal hote pour ${run_user}..."
run_root env HOST_TERMINAL_QUEUE_GID="$queue_gid" bash "$INSTALLER" "$run_user"
verify_terminal_agent || die \
  "Le service a ete installe mais n'est pas operationnel. Le diagnostic ci-dessus donne la cause exacte."
