#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INTERNAL_DIR="${SCRIPT_DIR}/scripts/linux"
[[ -d "$INTERNAL_DIR" ]] || INTERNAL_DIR="$SCRIPT_DIR"
# shellcheck source=client-common.sh
source "${INTERNAL_DIR}/client-common.sh"

INSTALL_DIR="${AI_DEEP_MONITOR_DIR:-${HOME}/ai-deep-monitor}"

usage() {
  cat <<'EOF'
Usage: ./ai-deep-monitor.sh [--install-dir CHEMIN] [commande]

Sans commande, ouvre le menu interactif.

Commandes:
  install       Installer ou reparer l'application
  update        Rechercher et installer une mise a jour
  status        Afficher l'etat des services et les ports
  logs          Afficher les journaux de l'API
  backup        Creer une sauvegarde
  restore       Restaurer une sauvegarde
  stop          Arreter l'application sans supprimer les donnees
  start         Demarrer l'application
  uninstall     Desinstallation partielle
  purge         Tout supprimer: conteneurs, volumes SQL, images et fichiers
  help          Afficher cette aide

Le dossier par defaut est ~/ai-deep-monitor. Les ports libres sont choisis
automatiquement et conserves dans le fichier .env de l'installation.
EOF
}

kit_script() {
  local name="$1"
  [[ -x "${INTERNAL_DIR}/${name}" ]] || die "Script introuvable: ${INTERNAL_DIR}/${name}"
  printf '%s\n' "${INTERNAL_DIR}/${name}"
}

require_installation() {
  [[ -f "${INSTALL_DIR}/.env" && -f "${INSTALL_DIR}/docker-compose.release.yml" ]] ||
    die "Aucune installation trouvee dans ${INSTALL_DIR}. Choisissez d'abord Installer."
}

load_installation() {
  require_installation
  ENV_FILE="${INSTALL_DIR}/.env"
  COMPOSE_FILE="${INSTALL_DIR}/docker-compose.release.yml"
  PROJECT_NAME="$(project_name_from_dir "$INSTALL_DIR")"
  ensure_docker
}

show_access() {
  local frontend_port api_port
  frontend_port="$(read_env_value "${INSTALL_DIR}/.env" FRONTEND_PORT)"
  api_port="$(read_env_value "${INSTALL_DIR}/.env" API_PORT)"
  printf '\nApplication : http://localhost'
  [[ "${frontend_port:-80}" == "80" ]] || printf ':%s' "$frontend_port"
  printf '\nAPI         : http://localhost:%s/health\n\n' "${api_port:-8000}"
}

install_app() {
  "$(kit_script install-client.sh)" --install-dir "$INSTALL_DIR"
}

update_app() {
  require_installation
  "$(kit_script update-client.sh)" --install-dir "$INSTALL_DIR"
}

status_app() {
  load_installation
  compose_exec -p "$PROJECT_NAME" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps
  show_access
}

logs_app() {
  load_installation
  compose_exec -p "$PROJECT_NAME" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" \
    logs --tail=200 api mysql sandbox ollama
}

backup_app() {
  require_installation
  "$(kit_script backup-client.sh)" --install-dir "$INSTALL_DIR"
}

restore_app() {
  local backup_file="${1:-}"
  require_installation
  if [[ -z "$backup_file" ]]; then
    read -r -p 'Chemin complet de la sauvegarde: ' backup_file
  fi
  [[ -f "$backup_file" ]] || die "Sauvegarde introuvable: $backup_file"
  "$(kit_script restore-client.sh)" \
    --install-dir "$INSTALL_DIR" \
    --backup-file "$backup_file"
}

stop_app() {
  load_installation
  compose_exec -p "$PROJECT_NAME" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" stop
  log "Application arretee. Les donnees sont conservees."
}

start_app() {
  load_installation
  compose_exec -p "$PROJECT_NAME" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
  if ! wait_for_container ai-monitor-client-api 300; then
    show_startup_diagnostics "$PROJECT_NAME" "$COMPOSE_FILE" "$ENV_FILE"
    die "L'API n'est pas operationnelle."
  fi
  status_app
}

uninstall_partial() {
  require_installation
  "$(kit_script uninstall-client.sh)" \
    --install-dir "$INSTALL_DIR" \
    --mode partial
}

purge_all() {
  local confirmation
  require_installation
  warn "Cette operation supprime aussi MySQL, les volumes applicatifs et les images Docker."
  warn "Une sauvegarde externe sera creee avant la suppression."
  read -r -p 'Saisissez SUPPRIMER pour continuer: ' confirmation
  [[ "$confirmation" == "SUPPRIMER" ]] || die "Suppression totale annulee."
  "$(kit_script uninstall-client.sh)" \
    --install-dir "$INSTALL_DIR" \
    --mode full \
    --remove-images \
    --yes
  exit 0
}

run_command() {
  local command="${1:-menu}"
  shift || true
  case "$command" in
    install) install_app ;;
    update) update_app ;;
    status) status_app ;;
    logs) logs_app ;;
    backup) backup_app ;;
    restore) restore_app "${1:-}" ;;
    stop) stop_app ;;
    start) start_app ;;
    uninstall) uninstall_partial ;;
    purge) purge_all ;;
    help|-h|--help) usage ;;
    *) die "Commande inconnue: $command" ;;
  esac
}

menu() {
  local choice
  while true; do
    cat <<'EOF'

AI Deep Monitor
1. Installer ou reparer
2. Mettre a jour
3. Afficher l'etat et les ports
4. Demarrer
5. Arreter sans supprimer les donnees
6. Creer une sauvegarde
7. Restaurer une sauvegarde
8. Afficher les journaux techniques
9. Desinstaller en conservant les donnees
10. TOUT SUPPRIMER
0. Quitter
EOF
    read -r -p 'Votre choix: ' choice
    case "$choice" in
      1) install_app ;;
      2) update_app ;;
      3) status_app ;;
      4) start_app ;;
      5) stop_app ;;
      6) backup_app ;;
      7) restore_app ;;
      8) logs_app ;;
      9) uninstall_partial ;;
      10) purge_all ;;
      0) exit 0 ;;
      *) warn "Choix invalide." ;;
    esac
  done
}

while (($#)); do
  case "$1" in
    --install-dir)
      [[ $# -ge 2 ]] || die "--install-dir exige un chemin."
      INSTALL_DIR="$2"
      shift 2
      ;;
    --install-dir=*)
      INSTALL_DIR="${1#*=}"
      shift
      ;;
    *)
      break
      ;;
  esac
done

if (($#)); then
  run_command "$@"
else
  menu
fi
