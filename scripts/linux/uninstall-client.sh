#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=client-common.sh
source "${SCRIPT_DIR}/client-common.sh"

INSTALL_DIR="${HOME}/ai-deep-monitor"
MODE="partial"
SKIP_BACKUP=false
REMOVE_IMAGES=false
ASSUME_YES=false

while (($#)); do
  case "$1" in
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    --mode) MODE="${2,,}"; shift 2 ;;
    --skip-backup) SKIP_BACKUP=true; shift ;;
    --remove-images) REMOVE_IMAGES=true; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    -h|--help)
      printf 'Usage: ./uninstall-client.sh [--install-dir CHEMIN] [--mode partial|full] [--skip-backup] [--remove-images] [--yes]\n'
      exit 0
      ;;
    *) die "Option inconnue: $1" ;;
  esac
done
[[ "$MODE" == "partial" || "$MODE" == "full" ]] || die "Mode attendu: partial ou full."

INSTALL_DIR="$(cd "$INSTALL_DIR" 2>/dev/null && pwd)" || die "Dossier d'installation introuvable."
ENV_FILE="${INSTALL_DIR}/.env"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.release.yml"
[[ -f "$ENV_FILE" && -f "$COMPOSE_FILE" ]] || die "Installation incomplete dans ${INSTALL_DIR}."
ensure_docker
project_name="$(project_name_from_dir "$INSTALL_DIR")"
compose_exec -p "$project_name" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" config --quiet

if [[ "$MODE" == "partial" ]]; then
  log "Les conteneurs et le reseau seront supprimes. Volumes, images et fichiers seront conserves."
else
  warn "Les volumes MySQL et applicatifs ainsi que ${INSTALL_DIR} seront supprimes."
fi
confirm "Confirmer la desinstallation ${MODE} ?" "$ASSUME_YES" || die "Desinstallation annulee."

if [[ "$MODE" == "full" && "$SKIP_BACKUP" == "false" ]]; then
  "${INSTALL_DIR}/backup-client.sh" --install-dir "$INSTALL_DIR"
fi

if [[ "$MODE" == "partial" ]]; then
  compose_exec -p "$project_name" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down --remove-orphans
  log "Desinstallation partielle terminee."
  exit 0
fi

down_args=(down --volumes --remove-orphans)
[[ "$REMOVE_IMAGES" == "false" ]] || down_args+=(--rmi all)
compose_exec -p "$project_name" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "${down_args[@]}"

case "$INSTALL_DIR" in
  /|/home|/opt|/usr|"$HOME") die "Suppression refusee pour le chemin sensible ${INSTALL_DIR}." ;;
esac
cd /
rm -rf -- "$INSTALL_DIR"
log "Desinstallation complete terminee. Les sauvegardes externes sont conservees."
