#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=client-common.sh
source "${SCRIPT_DIR}/client-common.sh"

KIT_ROOT="$SCRIPT_DIR"
[[ -f "${SCRIPT_DIR}/../../ai-deep-monitor.sh" ]] && KIT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

kit_source() {
  local name="$1"
  local candidate
  for candidate in \
    "${SCRIPT_DIR}/${name}" \
    "${SCRIPT_DIR}/../windows/${name}" \
    "${KIT_ROOT}/${name}" \
    "${KIT_ROOT}/deploy/${name}"; do
    [[ -f "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
  done
  if [[ "$name" == "README_CLIENT.md" && -f "${KIT_ROOT}/docs/installation.md" ]]; then
    printf '%s\n' "${KIT_ROOT}/docs/installation.md"
    return 0
  fi
  return 1
}

sync_host_terminal_agent() {
  local source_dir="${KIT_ROOT}/host_terminal_agent"
  local target_dir="${INSTALL_DIR}/host_terminal_agent"
  local file
  [[ -d "$source_dir" ]] || return 0
  [[ "$(cd "$source_dir" && pwd)" == "$(mkdir -p "$target_dir" && cd "$target_dir" && pwd)" ]] && return 0
  for file in agent.py terminal_policy.py install_linux_service.sh uninstall_linux_service.sh install_windows_task.ps1 uninstall_windows_task.ps1 README.md; do
    [[ -f "${source_dir}/${file}" ]] && cp -f "${source_dir}/${file}" "${target_dir}/${file}"
  done
  chmod +x "${target_dir}"/*.sh 2>/dev/null || true
}

install_host_terminal_agent() {
  local repair_script="${INSTALL_DIR}/repair-terminal.sh"
  [[ -x "$repair_script" ]] || die "Outil de reparation du terminal absent: ${repair_script}"
  "$repair_script" --install-dir "$INSTALL_DIR"
}

INSTALL_DIR="${HOME}/ai-deep-monitor"
APP_VERSION=""
SKIP_DOCKER_LOGIN=false
SKIP_BACKUP=false
SKIP_AGENT_INSTALL=false
NO_START=false
ASSUME_YES=false

usage() {
  cat <<'EOF'
Usage: ./update-client.sh [options]
  --install-dir CHEMIN
  --app-version VERSION
  --skip-docker-login
  --skip-backup
  --skip-agent-install
  --no-start
  --yes
EOF
}

while (($#)); do
  case "$1" in
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    --app-version) APP_VERSION="$2"; shift 2 ;;
    --skip-docker-login) SKIP_DOCKER_LOGIN=true; shift ;;
    --skip-backup) SKIP_BACKUP=true; shift ;;
    --skip-agent-install) SKIP_AGENT_INSTALL=true; shift ;;
    --no-start) NO_START=true; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Option inconnue: $1" ;;
  esac
done

ENV_FILE="${INSTALL_DIR}/.env"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.release.yml"
[[ -f "$ENV_FILE" ]] || die "Installation introuvable: ${ENV_FILE}"
for file in docker-compose.release.yml client-common.sh client-platform.ps1 ai-deep-monitor.sh ai-deep-monitor.ps1 AI-Deep-Monitor.cmd install-client.sh check-update.sh update-client.sh backup-client.sh backup-maintenance.sh restore-client.sh uninstall-client.sh repair-terminal.sh install-client.ps1 check-update.ps1 update-client.ps1 backup-client.ps1 backup-maintenance.ps1 restore-client.ps1 uninstall-client.ps1 repair-terminal.ps1 README_CLIENT.md; do
  source_file="$(kit_source "$file" || true)"
  [[ -n "$source_file" ]] || continue
  if [[ "$source_file" != "${INSTALL_DIR}/${file}" ]]; then
    cp -f "$source_file" "${INSTALL_DIR}/${file}"
  fi
done
rm -f -- "${INSTALL_DIR}/VERSION"
chmod +x "${INSTALL_DIR}"/*.sh 2>/dev/null || true
sync_host_terminal_agent
remove_env_value "$ENV_FILE" KIT_VERSION
ensure_auth_config "$ENV_FILE"
ensure_ollama_config "$ENV_FILE"
[[ -n "$(read_env_value "$ENV_FILE" HOST_TERMINAL_QUEUE_GID)" ]] ||
  write_env_value "$ENV_FILE" HOST_TERMINAL_QUEUE_GID 10003
[[ -n "$(read_env_value "$ENV_FILE" TERMINAL_SESSION_TTL_SECONDS)" ]] ||
  write_env_value "$ENV_FILE" TERMINAL_SESSION_TTL_SECONDS 300
[[ -n "$(read_env_value "$ENV_FILE" TERMINAL_POLICY_ADMIN_PASSWORD)" ]] ||
  write_env_value "$ENV_FILE" TERMINAL_POLICY_ADMIN_PASSWORD ysitech1234
if [[ "$AUTH_CONFIG_CHANGED" == "true" ]]; then
  log "Configuration d'authentification reparee; les volumes SQL et les comptes existants restent inchanges."
fi
if [[ "$OLLAMA_CONFIG_CHANGED" == "true" ]]; then
  log "Configuration Ollama adaptee a cette machine; les donnees existantes sont conservees."
fi

if [[ "$NO_START" == "true" ]]; then
  detect_host_platform
  write_env_value "$ENV_FILE" DOCKER_PLATFORM "$DOCKER_PLATFORM"
  [[ -z "$APP_VERSION" ]] || write_env_value "$ENV_FILE" APP_VERSION "$APP_VERSION"
  log "Fichiers du kit actualises sans lancement Docker pour ${DOCKER_PLATFORM}."
  print_bootstrap_credentials
  exit 0
fi

ensure_docker
write_env_value "$ENV_FILE" DOCKER_PLATFORM "$DOCKER_PLATFORM"

# La version Docker peut deja etre a jour alors que l'agent hote provient
# encore d'un ancien kit. Reparer l'agent avant tout retour anticipe garantit
# que l'action normale "Mettre a jour" maintient aussi le terminal.
if [[ "$SKIP_AGENT_INSTALL" == "false" ]]; then
  install_host_terminal_agent
fi

require_command curl
owner="$(read_env_value "$ENV_FILE" GITHUB_OWNER)"
owner="${owner:-jimmindev}"
github_user="${UPDATE_CHECK_USER:-$(read_env_value "$ENV_FILE" UPDATE_CHECK_USER)}"
github_token="${UPDATE_CHECK_TOKEN:-$(read_env_value "$ENV_FILE" UPDATE_CHECK_TOKEN)}"

if [[ "$SKIP_DOCKER_LOGIN" == "false" || -z "$APP_VERSION" ]]; then
  [[ -n "$github_user" ]] || read -r -p 'Utilisateur GitHub: ' github_user
  if [[ -z "$github_token" ]]; then
    read -r -s -p 'Token GitHub avec read:packages: ' github_token
    printf '\n'
  fi
fi

if [[ -z "$APP_VERSION" ]]; then
  APP_VERSION="$(latest_common_app_version "$owner" "$github_user" "$github_token")"
fi
[[ "$APP_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Version applicative invalide: ${APP_VERSION}"

current_version="$(read_env_value "$ENV_FILE" APP_VERSION)"
refresh_images=false
if [[ "$current_version" == "$APP_VERSION" ]]; then
  if [[ "$AUTH_CONFIG_CHANGED" == "false" &&
        "$OLLAMA_CONFIG_CHANGED" == "false" ]]; then
    log "L'application est deja en ${APP_VERSION}; les outils de maintenance sont synchronises."
    exit 0
  fi
  refresh_images=true
  log "L'application reste en ${APP_VERSION}; le deploiement est resynchronise pour ${DOCKER_PLATFORM}."
fi

if [[ "$refresh_images" == "false" ]]; then
  confirm "Mettre a jour l'application de ${current_version} vers ${APP_VERSION} ?" "$ASSUME_YES" ||
    die "Mise a jour annulee."
fi

if [[ "$SKIP_BACKUP" == "false" && "$refresh_images" == "false" ]]; then
  "${INSTALL_DIR}/backup-client.sh" --install-dir "$INSTALL_DIR"
fi

cp -f "$ENV_FILE" "${ENV_FILE}.before-${APP_VERSION}.bak"
write_env_value "$ENV_FILE" APP_VERSION "$APP_VERSION"

if [[ "$SKIP_DOCKER_LOGIN" == "false" ]]; then
  docker_registry_login ghcr.io "$github_user" "$github_token"
  write_env_value "$ENV_FILE" UPDATE_CHECK_USER "$github_user"
  write_env_value "$ENV_FILE" UPDATE_CHECK_TOKEN "$github_token"
fi
unset github_token

project_name="$(project_name_from_dir "$INSTALL_DIR")"
compose_exec -p "$project_name" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" config --quiet
compose_exec -p "$project_name" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull
if ! compose_exec -p "$project_name" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d; then
  show_startup_diagnostics "$project_name" "$COMPOSE_FILE" "$ENV_FILE"
  die "Le stack Docker n'a pas redemarre. Le fichier ${ENV_FILE}.before-${APP_VERSION}.bak permet un retour arriere."
fi

if ! wait_for_container ai-monitor-client-api 300; then
  show_startup_diagnostics "$project_name" "$COMPOSE_FILE" "$ENV_FILE"
  die "L'API n'est pas operationnelle apres la mise a jour. Le fichier ${ENV_FILE}.before-${APP_VERSION}.bak permet un retour arriere."
fi

log "Mise a jour terminee: ${APP_VERSION} sur ${DOCKER_PLATFORM}."
print_bootstrap_credentials
