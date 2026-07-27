#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=client-common.sh
source "${SCRIPT_DIR}/client-common.sh"

KIT_ROOT="$SCRIPT_DIR"
[[ -f "${SCRIPT_DIR}/../../VERSION" ]] && KIT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

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

INSTALL_DIR="${HOME}/ai-deep-monitor"
APP_VERSION=""
SKIP_DOCKER_LOGIN=false
SKIP_BACKUP=false
NO_START=false
ASSUME_YES=false

usage() {
  cat <<'EOF'
Usage: ./update-client.sh [options]
  --install-dir CHEMIN
  --app-version VERSION
  --skip-docker-login
  --skip-backup
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
    --no-start) NO_START=true; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Option inconnue: $1" ;;
  esac
done

ENV_FILE="${INSTALL_DIR}/.env"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.release.yml"
[[ -f "$ENV_FILE" ]] || die "Installation introuvable: ${ENV_FILE}"
previous_kit_version="$(read_env_value "$ENV_FILE" KIT_VERSION)"

for file in docker-compose.release.yml client-common.sh client-platform.ps1 ai-deep-monitor.sh ai-deep-monitor.ps1 install-client.sh check-update.sh update-client.sh backup-client.sh backup-maintenance.sh restore-client.sh uninstall-client.sh install-client.ps1 check-update.ps1 update-client.ps1 backup-client.ps1 backup-maintenance.ps1 restore-client.ps1 uninstall-client.ps1 README_CLIENT.md VERSION; do
  source_file="$(kit_source "$file" || true)"
  [[ -n "$source_file" ]] || continue
  if [[ "$source_file" != "${INSTALL_DIR}/${file}" ]]; then
    cp -f "$source_file" "${INSTALL_DIR}/${file}"
  fi
done
chmod +x "${INSTALL_DIR}"/*.sh 2>/dev/null || true
write_env_value "$ENV_FILE" KIT_VERSION "$KIT_VERSION"
ensure_auth_config "$ENV_FILE"
ensure_ollama_config "$ENV_FILE"
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
  if [[ "$previous_kit_version" == "$KIT_VERSION" &&
        "$AUTH_CONFIG_CHANGED" == "false" &&
        "$OLLAMA_CONFIG_CHANGED" == "false" ]]; then
    log "L'application est deja en ${APP_VERSION} et le kit en ${KIT_VERSION}."
    exit 0
  fi
  refresh_images=true
  log "L'application reste en ${APP_VERSION}; le deploiement est resynchronise pour ${DOCKER_PLATFORM} avec le kit ${KIT_VERSION}."
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
write_env_value "$ENV_FILE" KIT_VERSION "$KIT_VERSION"

if [[ "$SKIP_DOCKER_LOGIN" == "false" ]]; then
  printf '%s' "$github_token" | docker_exec login ghcr.io -u "$github_user" --password-stdin
  write_env_value "$ENV_FILE" UPDATE_CHECK_USER "$github_user"
  write_env_value "$ENV_FILE" UPDATE_CHECK_TOKEN "$github_token"
fi
unset github_token

project_name="$(project_name_from_dir "$INSTALL_DIR")"
compose_exec -p "$project_name" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" config --quiet
compose_exec -p "$project_name" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull
compose_exec -p "$project_name" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d

wait_for_container ai-monitor-client-api 300 ||
  die "L'API n'est pas operationnelle apres la mise a jour. Le fichier ${ENV_FILE}.before-${APP_VERSION}.bak permet un retour arriere."

log "Mise a jour terminee: ${APP_VERSION} sur ${DOCKER_PLATFORM}."
print_bootstrap_credentials
