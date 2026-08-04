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
APP_VERSION="$DEFAULT_APP_VERSION"
GITHUB_OWNER="jimmindev"
FRONTEND_PORT=80
API_PORT=8000
CORS_ORIGINS=""
SKIP_DOCKER_LOGIN=false
STRICT_PORTS=false
NO_START=false

usage() {
  cat <<'EOF'
Usage: ./install-client.sh [options]

Options:
  --install-dir CHEMIN       Dossier cible (defaut: ~/ai-deep-monitor)
  --app-version VERSION      Version applicative (defaut: v0.1.5)
  --github-owner NOM         Proprietaire des images GHCR
  --frontend-port PORT       Port web souhaite (auto: 80 puis 8080)
  --api-port PORT            Port API souhaite
  --cors-origins URLS        Origines CORS separees par des virgules
  --skip-docker-login        Ne pas se connecter a GHCR
  --strict-ports             Echouer si un port demande est occupe
  --no-start                 Preparer les fichiers sans Docker
  -h, --help                 Afficher cette aide
EOF
}

while (($#)); do
  case "$1" in
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    --app-version) APP_VERSION="$2"; shift 2 ;;
    --github-owner) GITHUB_OWNER="$2"; shift 2 ;;
    --frontend-port) FRONTEND_PORT="$2"; shift 2 ;;
    --api-port) API_PORT="$2"; shift 2 ;;
    --cors-origins) CORS_ORIGINS="$2"; shift 2 ;;
    --skip-docker-login) SKIP_DOCKER_LOGIN=true; shift ;;
    --strict-ports) STRICT_PORTS=true; shift ;;
    --no-start) NO_START=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Option inconnue: $1" ;;
  esac
done

[[ "$FRONTEND_PORT" =~ ^[0-9]+$ ]] || die "Port frontend invalide."
[[ "$API_PORT" =~ ^[0-9]+$ ]] || die "Port API invalide."
compose_source="$(kit_source docker-compose.release.yml)" ||
  die "docker-compose.release.yml introuvable."

mkdir -p "$INSTALL_DIR"
INSTALL_DIR="$(cd "$INSTALL_DIR" && pwd)"
ENV_FILE="${INSTALL_DIR}/.env"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.release.yml"
PROJECT_NAME="$(project_name_from_dir "$INSTALL_DIR")"

kit_files=(
  docker-compose.release.yml
  client-common.sh
  client-platform.ps1
  ai-deep-monitor.sh
  ai-deep-monitor.ps1
  install-client.sh
  check-update.sh
  update-client.sh
  backup-client.sh
  backup-maintenance.sh
  restore-client.sh
  uninstall-client.sh
  install-client.ps1
  check-update.ps1
  update-client.ps1
  backup-client.ps1
  backup-maintenance.ps1
  restore-client.ps1
  uninstall-client.ps1
  README_CLIENT.md
  VERSION
)

for file in "${kit_files[@]}"; do
  source_file="$(kit_source "$file" || true)"
  [[ -n "$source_file" ]] || continue
  if [[ "$(cd "$(dirname "$source_file")" && pwd)/$(basename "$source_file")" != "${INSTALL_DIR}/${file}" ]]; then
    cp -f "$source_file" "${INSTALL_DIR}/${file}"
  fi
done
chmod +x "${INSTALL_DIR}"/*.sh 2>/dev/null || true

existing_env=false
[[ -f "$ENV_FILE" ]] && existing_env=true
existing_volumes=""
requested_frontend_port="$FRONTEND_PORT"
requested_api_port="$API_PORT"

if [[ "$NO_START" == "true" ]]; then
  detect_host_platform
else
  ensure_docker
  existing_volumes="$(existing_data_volumes "$PROJECT_NAME")"
fi

if [[ "$existing_env" == "false" && -n "$existing_volumes" ]]; then
  die "Des volumes AI Deep Monitor existent mais .env est absent. Restaurez l'ancien .env ou utilisez la desinstallation complete. Volumes: $(tr '\n' ' ' <<<"$existing_volumes")"
fi

if [[ "$existing_env" == "true" ]]; then
  FRONTEND_PORT="$(read_env_value "$ENV_FILE" FRONTEND_PORT)"
  API_PORT="$(read_env_value "$ENV_FILE" API_PORT)"
  FRONTEND_PORT="${FRONTEND_PORT:-80}"
  API_PORT="${API_PORT:-8000}"
  requested_frontend_port="$FRONTEND_PORT"
  requested_api_port="$API_PORT"
  [[ -n "$CORS_ORIGINS" ]] || CORS_ORIGINS="$(read_env_value "$ENV_FILE" CORS_ORIGINS)"
  write_env_value "$ENV_FILE" KIT_VERSION "$KIT_VERSION"
  write_env_value "$ENV_FILE" DOCKER_PLATFORM "$DOCKER_PLATFORM"
  log "Installation existante detectee: configuration et volumes conserves."
fi

selected_port="$(select_runtime_port "$FRONTEND_PORT" 8080 "$PROJECT_NAME")"
if [[ "$selected_port" != "$FRONTEND_PORT" ]]; then
  [[ "$STRICT_PORTS" == "false" ]] ||
    die "Le port frontend ${FRONTEND_PORT} est occupe par $(describe_port_owner "$FRONTEND_PORT")."
  log "Port frontend ${FRONTEND_PORT} occupe par $(describe_port_owner "$FRONTEND_PORT"); ${selected_port} selectionne."
  FRONTEND_PORT="$selected_port"
fi

selected_port="$(select_runtime_port "$API_PORT" 8001 "$PROJECT_NAME" "$FRONTEND_PORT")"
if [[ "$selected_port" != "$API_PORT" ]]; then
  [[ "$STRICT_PORTS" == "false" ]] ||
    die "Le port API ${API_PORT} est occupe par $(describe_port_owner "$API_PORT")."
  log "Port API ${API_PORT} occupe par $(describe_port_owner "$API_PORT"); ${selected_port} selectionne."
  API_PORT="$selected_port"
fi

if [[ "$existing_env" == "true" ]]; then
  if [[ "$FRONTEND_PORT" != "$requested_frontend_port" || "$API_PORT" != "$requested_api_port" ]]; then
    write_env_value "$ENV_FILE" FRONTEND_PORT "$FRONTEND_PORT"
    write_env_value "$ENV_FILE" API_PORT "$API_PORT"
    if [[ "$CORS_ORIGINS" =~ ^http://localhost(:[0-9]+)?$ ]]; then
      CORS_ORIGINS="http://localhost"
      [[ "$FRONTEND_PORT" == "80" ]] || CORS_ORIGINS="http://localhost:${FRONTEND_PORT}"
      write_env_value "$ENV_FILE" CORS_ORIGINS "$CORS_ORIGINS"
    fi
    log "Configuration des ports actualisee sans modifier les volumes."
  fi
else

  if [[ -z "$CORS_ORIGINS" ]]; then
    CORS_ORIGINS="http://localhost"
    [[ "$FRONTEND_PORT" == "80" ]] || CORS_ORIGINS="http://localhost:${FRONTEND_PORT}"
  fi

  auth_secret="$(new_secret)"
  GENERATED_BOOTSTRAP_PASSWORD="Adm1-$(new_secret)"
  cat >"$ENV_FILE" <<EOF
GITHUB_OWNER=${GITHUB_OWNER}
GITHUB_REPOSITORY_NAME=ai-deep-monitor
KIT_VERSION=${KIT_VERSION}
APP_VERSION=${APP_VERSION}
APP_CHANNEL=stable
DOCKER_PLATFORM=${DOCKER_PLATFORM}
UPDATE_CHECK_ENABLED=true
UPDATE_CHECK_CHANNEL=stable
UPDATE_CHECK_BRANCH=preprod
UPDATE_CHECK_USER=
UPDATE_CHECK_TOKEN=

OLLAMA_IMAGE=ollama/ollama:latest
OLLAMA_MODEL=llama3.2:3b
OLLAMA_FALLBACK_MODEL=llama3.2:1b
OLLAMA_TEMPERATURE=0.2
OLLAMA_NUM_PREDICT=512

MYSQL_ROOT_PASSWORD=$(new_secret)
MYSQL_DATABASE=ai_monitor_prod
MYSQL_USER=ai_user
MYSQL_PASSWORD=$(new_secret)

AUTH_SECRET_KEY=${auth_secret}
AUTH_BOOTSTRAP_USERNAME=admin
AUTH_BOOTSTRAP_PASSWORD=${GENERATED_BOOTSTRAP_PASSWORD}
AUTH_ACCESS_TOKEN_MINUTES=15
AUTH_REFRESH_TOKEN_DAYS=7
AUTH_MAX_FAILED_ATTEMPTS=5
AUTH_LOCK_MINUTES=15
AUTH_COOKIE_SECURE=false
AUTH_COOKIE_SAMESITE=lax

TELEMETRY_RAW_RETENTION_DAYS=7
TELEMETRY_ROLLUP_RETENTION_DAYS=365

CORS_ORIGINS=${CORS_ORIGINS}

FRONTEND_PORT=${FRONTEND_PORT}
API_PORT=${API_PORT}
EOF
  chmod 600 "$ENV_FILE"
  log "Configuration creee dans ${ENV_FILE}."
fi

ensure_auth_config "$ENV_FILE"
ensure_ollama_config "$ENV_FILE"
if [[ "$AUTH_CONFIG_CHANGED" == "true" && "$existing_env" == "true" ]]; then
  log "Configuration d'authentification reparee; les donnees et comptes existants sont conserves."
fi
if [[ "$OLLAMA_CONFIG_CHANGED" == "true" && "$existing_env" == "true" ]]; then
  log "Configuration Ollama adaptee a cette machine; les donnees existantes sont conservees."
fi

if [[ "$NO_START" == "true" ]]; then
  log "Installation preparee sans lancement Docker pour ${DOCKER_PLATFORM}."
  print_bootstrap_credentials
  exit 0
fi

compose_exec -p "$PROJECT_NAME" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" config --quiet
[[ -z "$existing_volumes" ]] || log "Volumes existants reutilises."

if [[ "$SKIP_DOCKER_LOGIN" == "false" ]]; then
  printf 'Utilisateur GitHub: '
  read -r github_user
  printf 'Token GitHub avec read:packages: '
  read -r -s github_token
  printf '\n'
  [[ -n "$github_user" && -n "$github_token" ]] || die "Identifiants GHCR incomplets."
  docker_registry_login ghcr.io "$github_user" "$github_token"
  write_env_value "$ENV_FILE" UPDATE_CHECK_ENABLED true
  write_env_value "$ENV_FILE" UPDATE_CHECK_USER "$github_user"
  write_env_value "$ENV_FILE" UPDATE_CHECK_TOKEN "$github_token"
  unset github_token
fi

log "Telechargement des images Docker..."
compose_exec -p "$PROJECT_NAME" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull
if ! compose_exec -p "$PROJECT_NAME" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d; then
  show_startup_diagnostics "$PROJECT_NAME" "$COMPOSE_FILE" "$ENV_FILE"
  die "Le stack Docker n'a pas demarre correctement. Le diagnostic ci-dessus indique le service bloque."
fi

if ! wait_for_container ai-monitor-client-api 300; then
  show_startup_diagnostics "$PROJECT_NAME" "$COMPOSE_FILE" "$ENV_FILE"
  die "L'API n'est pas devenue operationnelle. Le diagnostic ci-dessus indique le service bloque."
fi

log "Installation terminee."
print_bootstrap_credentials
printf 'Frontend  : http://localhost'
[[ "$FRONTEND_PORT" == "80" ]] || printf ':%s' "$FRONTEND_PORT"
printf '\nAPI health: http://localhost:%s/health\n' "$API_PORT"
