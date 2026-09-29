#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=client-common.sh
source "${SCRIPT_DIR}/client-common.sh"

INSTALL_DIR="${HOME}/ai-deep-monitor"
DESTINATION_DIR=""
explicit_destination=false
destination_kind="network"

while (($#)); do
  case "$1" in
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    --destination-dir) DESTINATION_DIR="$2"; explicit_destination=true; shift 2 ;;
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
require_command gzip
require_command sha256sum
require_command findmnt

# Older running host agents pass this local path after refreshing the kit.
# Resolve only that legacy default through the selected maintenance destination;
# explicit local destinations remain rejected by findmnt below.
if [[ "$DESTINATION_DIR" == "${INSTALL_DIR}/.host-agent-state/update-backups" ||
      "$DESTINATION_DIR" == "/var/lib/ai-deep-monitor-host-terminal/update-backups" ]]; then
  DESTINATION_DIR=""
fi

if [[ -z "$DESTINATION_DIR" ]]; then
  DESTINATION_DIR="$(read_env_value "$ENV_FILE" MAINTENANCE_BACKUP_PATH)"
fi
if [[ "$explicit_destination" == "false" && -n "$DESTINATION_DIR" ]]; then
  configured_type="$(findmnt -T "$DESTINATION_DIR" --first-only -n -o FSTYPE 2>/dev/null || true)"
  if [[ ! -d "$DESTINATION_DIR" ||
        ( "$configured_type" != "cifs" && "$configured_type" != "nfs" && "$configured_type" != "nfs4" ) ]]; then
    warn "Le partage de maintenance configure est indisponible; recherche d'une autre destination."
    DESTINATION_DIR=""
  fi
fi
if [[ -z "$DESTINATION_DIR" ]]; then
  # A single share already connected in the application is unambiguous.
  # Match the mount itself, not its parent: an offline share must never
  # create a backup directory on the local filesystem.
  network_mounts_root="${AI_DEEP_MONITOR_NETWORK_MOUNTS_ROOT:-/mnt/ai-deep-monitor-network}"
  network_shares=()
  for candidate in "$network_mounts_root"/*; do
    [[ -d "$candidate" && ! -L "$candidate" ]] || continue
    [[ "${candidate##*/}" =~ ^[0-9a-f]{24}$ ]] || continue
    candidate_type="$(findmnt -M "$candidate" --first-only -n -o FSTYPE 2>/dev/null || true)"
    if [[ "$candidate_type" == "cifs" || "$candidate_type" == "nfs" || "$candidate_type" == "nfs4" ]]; then
      network_shares+=("$candidate")
    fi
  done
  if ((${#network_shares[@]} == 1)); then
    DESTINATION_DIR="${network_shares[0]}/maintenance"
    mkdir -p -- "$DESTINATION_DIR" || die "Impossible d'ecrire dans le partage reseau de maintenance."
  elif ((${#network_shares[@]} > 1)); then
    die "Plusieurs partages reseau sont montes. Choisissez MAINTENANCE_BACKUP_PATH dans .env avant la mise a jour."
  else
    destination_kind="docker"
  fi
fi
if [[ "$destination_kind" == "network" ]]; then
  [[ -d "$DESTINATION_DIR" ]] ||
    die "Dossier de maintenance introuvable: configurez MAINTENANCE_BACKUP_PATH sur un partage SMB/NFS monte."
  filesystem_type="$(findmnt -T "$DESTINATION_DIR" --first-only -n -o FSTYPE 2>/dev/null || true)"
  [[ "$filesystem_type" == "cifs" || "$filesystem_type" == "nfs" || "$filesystem_type" == "nfs4" ]] ||
    die "La sauvegarde de maintenance exige un partage reseau SMB ou NFS monte."
fi

project_name="$(project_name_from_dir "$INSTALL_DIR")"
if [[ "$destination_kind" == "docker" ]]; then
  volume_name="${project_name}_maintenance_backups"
  docker_exec volume create --label ai-deep-monitor.purpose=maintenance-backup "$volume_name" >/dev/null
  log "Aucun partage reseau monte : sauvegarde de maintenance dans le volume Docker ${volume_name}."
fi
compose_runtime_exec "$project_name" "$COMPOSE_FILE" "$ENV_FILE" config --quiet
compose_runtime_exec "$project_name" "$COMPOSE_FILE" "$ENV_FILE" up -d mysql >/dev/null
mysql_container="$(compose_runtime_exec "$project_name" "$COMPOSE_FILE" "$ENV_FILE" ps -q mysql)"
[[ -n "$mysql_container" ]] || die "Conteneur MySQL introuvable."
wait_for_container "$mysql_container" 180 || die "MySQL n'est pas pret."

timestamp="$(date -u +%Y%m%d-%H%M%S)"
version="$(read_env_value "$ENV_FILE" APP_VERSION)"
version="${version:-unknown}"
archive_name="ai-deep-monitor-${version}-${timestamp}.tar.gz"
partial_archive=""
if [[ "$destination_kind" == "network" ]]; then
  staging_dir="$(mktemp -d "${DESTINATION_DIR}/.ai-monitor-backup-staging-XXXXXX")"
  archive_path="${DESTINATION_DIR}/${archive_name}"
  partial_archive="${archive_path}.partial"
else
  staging_dir="$(mktemp -d -t ai-monitor-backup-staging-XXXXXX)"
  archive_path="docker-volume://${volume_name}/${archive_name}"
fi
trap 'rm -rf -- "$staging_dir"; if [[ -n "$partial_archive" ]]; then rm -f -- "$partial_archive"; fi' EXIT INT TERM

log "Sauvegarde MySQL..."
container_dump="/tmp/ai-monitor-${timestamp}.sql"
# shellcheck disable=SC2016
docker_exec exec "$mysql_container" sh -c \
  'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysqldump -uroot --single-transaction --routines --triggers --events --hex-blob --default-character-set=utf8mb4 "$MYSQL_DATABASE" > "$1"' \
  sh "$container_dump"
docker_exec cp "${mysql_container}:${container_dump}" "${staging_dir}/mysql.sql"
docker_exec exec "$mysql_container" rm -f "$container_dump"

included_paths=()
api_container="$(compose_runtime_exec "$project_name" "$COMPOSE_FILE" "$ENV_FILE" ps -a -q api || true)"
if [[ -n "$api_container" ]]; then
  while IFS='|' read -r source target; do
    mkdir -p "${staging_dir}/${target}"
    if docker_exec cp "${api_container}:${source}/." "${staging_dir}/${target}" >/dev/null 2>&1; then
      included_paths+=("$target")
    fi
  done <<'EOF'
/app/data|api-data
/app/uploaded_mibs|uploaded-mibs
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
  "createdAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostName": "$(hostname)",
  "mysqlSha256": "$(sha256sum "${staging_dir}/mysql.sql" | awk '{print $1}')",
  "includedPaths": [${included_json}],
  "llamaCppCacheIncluded": false,
  "generatedBackupsIncluded": false
}
EOF

if [[ "$destination_kind" == "network" ]]; then
  tar -C "$staging_dir" -cf - . | gzip -1 >"$partial_archive"
  mv -f -- "$partial_archive" "$archive_path"
  chmod 600 "$archive_path"
else
  helper_image="$(docker_exec inspect --format '{{.Image}}' "$mysql_container")"
  [[ -n "$helper_image" ]] || die "Image MySQL indisponible pour ecrire dans le volume Docker."
  tar -C "$staging_dir" -cf - . | gzip -1 |
    docker_exec run --rm -i --network none \
      --mount "type=volume,source=${volume_name},target=/maintenance" \
      --entrypoint sh "$helper_image" -c \
      'umask 077; partial="/maintenance/$1.partial"; cat > "$partial" && mv -- "$partial" "/maintenance/$1"' \
      sh "$archive_name"
fi
log "Sauvegarde terminee: ${archive_path}"
log "Le cache du modele llama.cpp n'est pas inclus et sera retelcharge si necessaire."
log "Les anciennes archives de sauvegarde ne sont pas imbriquees dans cette sauvegarde."
