#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=client-common.sh
source "${SCRIPT_DIR}/client-common.sh"

INSTALL_DIR="${HOME}/ai-deep-monitor"
BACKUP_FILE=""
NO_START=false
ASSUME_YES=false

while (($#)); do
  case "$1" in
    --backup-file) BACKUP_FILE="$2"; shift 2 ;;
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    --no-start) NO_START=true; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    -h|--help)
      printf 'Usage: ./restore-client.sh --backup-file FICHIER [--install-dir CHEMIN] [--no-start] [--yes]\n'
      exit 0
      ;;
    *) die "Option inconnue: $1" ;;
  esac
done

[[ -n "$BACKUP_FILE" && -f "$BACKUP_FILE" ]] || die "Fichier de sauvegarde introuvable."
ENV_FILE="${INSTALL_DIR}/.env"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.release.yml"
[[ -f "$ENV_FILE" && -f "$COMPOSE_FILE" ]] || die "Installation incomplete dans ${INSTALL_DIR}."
ensure_docker

staging_dir="$(mktemp -d -t ai-monitor-restore-XXXXXX)"
trap 'rm -rf -- "$staging_dir"' EXIT

case "$BACKUP_FILE" in
  *.tar.gz|*.tgz)
    require_command tar
    if tar -tzf "$BACKUP_FILE" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
      die "Archive refusee: chemin dangereux detecte."
    fi
    tar -xzf "$BACKUP_FILE" -C "$staging_dir"
    ;;
  *.zip)
    require_command unzip
    if unzip -Z1 "$BACKUP_FILE" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
      die "Archive refusee: chemin dangereux detecte."
    fi
    unzip -q "$BACKUP_FILE" -d "$staging_dir"
    ;;
  *) die "Format non pris en charge. Utilisez .tar.gz, .tgz ou .zip." ;;
esac

[[ -f "${staging_dir}/manifest.json" ]] || die "Manifest de sauvegarde absent."
[[ -f "${staging_dir}/mysql.sql" ]] || die "Dump mysql.sql absent."
if [[ -f "${staging_dir}/mysql.sha256" ]]; then
  (cd "$staging_dir" && sha256sum -c mysql.sha256) || die "Checksum MySQL invalide."
else
  expected_hash="$(sed -n 's/.*"mysqlSha256"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${staging_dir}/manifest.json")"
  actual_hash="$(sha256sum "${staging_dir}/mysql.sql" | awk '{print $1}')"
  [[ -z "$expected_hash" || "${expected_hash,,}" == "${actual_hash,,}" ]] ||
    die "Checksum MySQL invalide."
fi

saved_version="$(sed -n 's/.*"appVersion"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${staging_dir}/manifest.json")"
log "Version sauvegardee: ${saved_version:-inconnue}"
warn "La restauration remplace la base et les donnees applicatives actuelles."
confirm "Continuer la restauration ?" "$ASSUME_YES" || die "Restauration annulee."

project_name="$(project_name_from_dir "$INSTALL_DIR")"
compose_exec -p "$project_name" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" config --quiet
compose_exec -p "$project_name" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d mysql >/dev/null
mysql_container="$(compose_exec -p "$project_name" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps -q mysql)"
[[ -n "$mysql_container" ]] || die "Conteneur MySQL introuvable."
wait_for_container "$mysql_container" 180 || die "MySQL n'est pas pret."

compose_exec -p "$project_name" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" stop frontend api >/dev/null 2>&1 || true
container_dump="/tmp/ai-monitor-restore-$$.sql"
docker_exec cp "${staging_dir}/mysql.sql" "${mysql_container}:${container_dump}"
# shellcheck disable=SC2016
docker_exec exec "$mysql_container" sh -c \
  'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot "$MYSQL_DATABASE" < "$1"' \
  sh "$container_dump"
docker_exec exec "$mysql_container" rm -f "$container_dump"

api_container="$(compose_exec -p "$project_name" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps -a -q api || true)"
if [[ -n "$api_container" ]]; then
  docker_exec start "$api_container" >/dev/null
  sleep 2
  while IFS='|' read -r source target; do
    [[ -d "${staging_dir}/${source}" ]] || continue
    docker_exec exec "$api_container" sh -c "mkdir -p '${target}' && find '${target}' -mindepth 1 -delete"
  done <<'EOF'
api-data|/app/data
uploaded-mibs|/app/uploaded_mibs
generated-backups|/app/generated_backups
EOF
  docker_exec stop "$api_container" >/dev/null
  while IFS='|' read -r source target; do
    [[ -d "${staging_dir}/${source}" ]] || continue
    docker_exec cp "${staging_dir}/${source}/." "${api_container}:${target}"
  done <<'EOF'
api-data|/app/data
uploaded-mibs|/app/uploaded_mibs
generated-backups|/app/generated_backups
EOF
fi

if [[ "$NO_START" == "true" ]]; then
  log "Donnees restaurees. Les services applicatifs restent arretes."
else
  compose_exec -p "$project_name" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
  compose_exec -p "$project_name" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps
fi
log "Restauration terminee."
