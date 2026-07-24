#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=client-common.sh
source "${SCRIPT_DIR}/client-common.sh"

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
  --app-version VERSION      Version applicative (defaut: v0.1.4)
  --github-owner NOM         Proprietaire des images GHCR
  --frontend-port PORT       Port web souhaite
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
[[ -f "${SCRIPT_DIR}/docker-compose.release.yml" ]] || die "docker-compose.release.yml introuvable."

mkdir -p "$INSTALL_DIR"
INSTALL_DIR="$(cd "$INSTALL_DIR" && pwd)"
ENV_FILE="${INSTALL_DIR}/.env"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.release.yml"
PROJECT_NAME="$(project_name_from_dir "$INSTALL_DIR")"

kit_files=(
  docker-compose.release.yml
  client-common.sh
  install-client.sh
  check-update.sh
  update-client.sh
  backup-client.sh
  restore-client.sh
  uninstall-client.sh
  install-client.ps1
  check-update.ps1
  update-client.ps1
  backup-client.ps1
  restore-client.ps1
  uninstall-client.ps1
  README_CLIENT.md
  VERSION
)

for file in "${kit_files[@]}"; do
  [[ -f "${SCRIPT_DIR}/${file}" ]] || continue
  if [[ "$(cd "$(dirname "${SCRIPT_DIR}/${file}")" && pwd)/$(basename "$file")" != "${INSTALL_DIR}/${file}" ]]; then
    cp -f "${SCRIPT_DIR}/${file}" "${INSTALL_DIR}/${file}"
  fi
done
chmod +x "${INSTALL_DIR}"/*.sh 2>/dev/null || true

existing_env=false
[[ -f "$ENV_FILE" ]] && existing_env=true
existing_volumes=""

if [[ "$NO_START" != "true" ]]; then
  ensure_docker
  existing_volumes="$(existing_data_volumes "$PROJECT_NAME")"
fi

if [[ "$existing_env" == "false" && -n "$existing_volumes" ]]; then
  die "Des volumes AI Deep Monitor existent mais .env est absent. Restaurez l'ancien .env ou utilisez la desinstallation complete. Volumes: $(tr '\n' ' ' <<<"$existing_volumes")"
fi

if [[ "$existing_env" == "true" ]]; then
  FRONTEND_PORT="$(read_env_value "$ENV_FILE" FRONTEND_PORT)"
  API_PORT="$(read_env_value "$ENV_FILE" API_PORT)"
  [[ -n "$CORS_ORIGINS" ]] || CORS_ORIGINS="$(read_env_value "$ENV_FILE" CORS_ORIGINS)"
  write_env_value "$ENV_FILE" KIT_VERSION "$KIT_VERSION"
  log "Installation existante detectee: configuration et volumes conserves."
else
  if ! port_is_available "$FRONTEND_PORT"; then
    [[ "$STRICT_PORTS" == "false" ]] || die "Le port frontend ${FRONTEND_PORT} est occupe."
    selected_port="$(available_port "$FRONTEND_PORT")"
    log "Port frontend ${FRONTEND_PORT} occupe; ${selected_port} selectionne."
    FRONTEND_PORT="$selected_port"
  fi
  if [[ "$API_PORT" == "$FRONTEND_PORT" ]] || ! port_is_available "$API_PORT"; then
    [[ "$STRICT_PORTS" == "false" ]] || die "Le port API ${API_PORT} est indisponible."
    selected_port="$(available_port "$API_PORT" "$FRONTEND_PORT")"
    log "Port API ${API_PORT} indisponible; ${selected_port} selectionne."
    API_PORT="$selected_port"
  fi

  if [[ -z "$CORS_ORIGINS" ]]; then
    CORS_ORIGINS="http://localhost"
    [[ "$FRONTEND_PORT" == "80" ]] || CORS_ORIGINS="http://localhost:${FRONTEND_PORT}"
  fi

  cat >"$ENV_FILE" <<EOF
GITHUB_OWNER=${GITHUB_OWNER}
GITHUB_REPOSITORY_NAME=ai-deep-monitor
KIT_VERSION=${KIT_VERSION}
APP_VERSION=${APP_VERSION}
APP_CHANNEL=stable
UPDATE_CHECK_ENABLED=true
UPDATE_CHECK_CHANNEL=stable
UPDATE_CHECK_BRANCH=preprod
UPDATE_CHECK_USER=
UPDATE_CHECK_TOKEN=

OLLAMA_IMAGE=ollama/ollama:latest
OLLAMA_MODEL=llama3.1
OLLAMA_TEMPERATURE=0.2
OLLAMA_NUM_PREDICT=512

MYSQL_ROOT_PASSWORD=$(new_secret)
MYSQL_DATABASE=ai_monitor_prod
MYSQL_USER=ai_user
MYSQL_PASSWORD=$(new_secret)

CORS_ORIGINS=${CORS_ORIGINS}

FRONTEND_PORT=${FRONTEND_PORT}
API_PORT=${API_PORT}
EOF
  chmod 600 "$ENV_FILE"
  log "Configuration creee dans ${ENV_FILE}."
fi

if [[ "$NO_START" == "true" ]]; then
  log "Installation preparee sans lancement Docker."
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
  printf '%s' "$github_token" | docker_exec login ghcr.io -u "$github_user" --password-stdin
  write_env_value "$ENV_FILE" UPDATE_CHECK_ENABLED true
  write_env_value "$ENV_FILE" UPDATE_CHECK_USER "$github_user"
  write_env_value "$ENV_FILE" UPDATE_CHECK_TOKEN "$github_token"
  unset github_token
fi

log "Telechargement des images Docker..."
compose_exec -p "$PROJECT_NAME" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull
compose_exec -p "$PROJECT_NAME" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d

if ! wait_for_container ai-monitor-client-api 300; then
  compose_exec -p "$PROJECT_NAME" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps
  die "L'API n'est pas devenue operationnelle. Consultez les logs Docker."
fi

log "Installation terminee."
printf 'Frontend  : http://localhost'
[[ "$FRONTEND_PORT" == "80" ]] || printf ':%s' "$FRONTEND_PORT"
printf '\nAPI health: http://localhost:%s/health\n' "$API_PORT"
