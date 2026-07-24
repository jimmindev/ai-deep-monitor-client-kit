#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=client-common.sh
source "${SCRIPT_DIR}/client-common.sh"

INSTALL_DIR="${HOME}/ai-deep-monitor"
DESTINATION_DIR=""

while (($#)); do
  case "$1" in
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    --destination-dir) DESTINATION_DIR="$2"; shift 2 ;;
    -h|--help)
      printf 'Usage: ./backup-client.sh [--install-dir CHEMIN] [--destination-dir CHEMIN]\n'
      exit 0
      ;;
    *) die "Option inconnue: $1" ;;
  esac
done

ENV_FILE="${INSTALL_DIR}/.env"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.release.yml"
[[ -f "$ENV_FILE" && -f "$COMPOSE_FILE" ]] || die "Installation incomplete dans ${INSTALL_DIR}."
ensure_docker
require_command tar
require_command sha256sum

if [[ -z "$DESTINATION_DIR" ]]; then
  DESTINATION_DIR="$(dirname "$INSTALL_DIR")/ai-deep-monitor-backups"
fi
mkdir -p "$DESTINATION_DIR"

project_name="$(project_name_from_dir "$INSTALL_DIR")"
compose_exec -p "$project_name" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" config --quiet
compose_exec -p "$project_name" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d mysql >/dev/null
mysql_container="$(compose_exec -p "$project_name" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps -q mysql)"
[[ -n "$mysql_container" ]] || die "Conteneur MySQL introuvable."
wait_for_container "$mysql_container" 180 || die "MySQL n'est pas pret."

timestamp="$(date -u +%Y%m%d-%H%M%S)"
version="$(read_env_value "$ENV_FILE" APP_VERSION)"
version="${version:-unknown}"
staging_dir="$(mktemp -d -t ai-monitor-backup-XXXXXX)"
archive_path="${DESTINATION_DIR}/ai-deep-monitor-${version}-${timestamp}.tar.gz"
trap 'rm -rf -- "$staging_dir"' EXIT

log "Sauvegarde MySQL..."
container_dump="/tmp/ai-monitor-${timestamp}.sql"
# shellcheck disable=SC2016
docker_exec exec "$mysql_container" sh -c \
  'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysqldump -uroot --single-transaction --routines --triggers --events --hex-blob --default-character-set=utf8mb4 "$MYSQL_DATABASE" > "$1"' \
  sh "$container_dump"
docker_exec cp "${mysql_container}:${container_dump}" "${staging_dir}/mysql.sql"
docker_exec exec "$mysql_container" rm -f "$container_dump"

included_paths=()
api_container="$(compose_exec -p "$project_name" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps -a -q api || true)"
if [[ -n "$api_container" ]]; then
  while IFS='|' read -r source target; do
    mkdir -p "${staging_dir}/${target}"
    if docker_exec cp "${api_container}:${source}/." "${staging_dir}/${target}" >/dev/null 2>&1; then
      included_paths+=("$target")
    fi
  done <<'EOF'
/app/data|api-data
/app/uploaded_mibs|uploaded-mibs
/app/generated_backups|generated-backups
EOF
else
  warn "Conteneur API absent: seul MySQL sera sauvegarde."
fi

(cd "$staging_dir" && sha256sum mysql.sql >mysql.sha256)
included_json=""
for path in "${included_paths[@]}"; do
  [[ -z "$included_json" ]] || included_json+=", "
  included_json+="\"${path}\""
done
cat >"${staging_dir}/manifest.json" <<EOF
{
  "formatVersion": 2,
  "application": "AI Deep Monitor",
  "appVersion": "${version}",
  "kitVersion": "${KIT_VERSION}",
  "createdAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostName": "$(hostname)",
  "mysqlSha256": "$(sha256sum "${staging_dir}/mysql.sql" | awk '{print $1}')",
  "includedPaths": [${included_json}],
  "ollamaIncluded": false
}
EOF

tar -C "$staging_dir" -czf "$archive_path" .
chmod 600 "$archive_path"
log "Sauvegarde terminee: ${archive_path}"
log "Le modele Ollama n'est pas inclus et sera retelcharge si necessaire."
