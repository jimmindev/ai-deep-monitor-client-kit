#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=client-common.sh
source "${SCRIPT_DIR}/client-common.sh"

INSTALL_DIR="${HOME}/ai-deep-monitor"
BACKUP_DIR=""
ACTION="list"
KEEP=5
ASSUME_YES=false

usage() {
  cat <<'EOF'
Usage: ./backup-maintenance.sh [options]

Options:
  --install-dir CHEMIN   Dossier de l'application
  --backup-dir CHEMIN    Dossier des sauvegardes
  --action ACTION        list, prune ou delete-all
  --keep N               Nombre d'archives recentes a conserver avec prune
  --yes                  Confirmer sans interaction
EOF
}

while (($#)); do
  case "$1" in
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    --backup-dir) BACKUP_DIR="$2"; shift 2 ;;
    --action) ACTION="$2"; shift 2 ;;
    --keep) KEEP="$2"; shift 2 ;;
    --yes) ASSUME_YES=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Option inconnue: $1" ;;
  esac
done

[[ "$ACTION" =~ ^(list|prune|delete-all)$ ]] || die "Action invalide: $ACTION"
[[ "$KEEP" =~ ^[0-9]+$ ]] || die "--keep exige un entier positif ou nul."
[[ -n "$BACKUP_DIR" ]] || BACKUP_DIR="$(dirname "$INSTALL_DIR")/ai-deep-monitor-backups"

mapfile -d '' backup_files < <(
  find "$BACKUP_DIR" -maxdepth 1 -type f \
    \( -name 'ai-deep-monitor-*.tar.gz' -o -name 'ai-deep-monitor-*.zip' \) \
    -printf '%T@ %p\0' 2>/dev/null |
    sort -z -nr |
    while IFS= read -r -d '' entry; do
      printf '%s\0' "${entry#* }"
    done
)

show_backups() {
  if ((${#backup_files[@]} == 0)); then
    log "Aucune sauvegarde dans ${BACKUP_DIR}."
    return
  fi
  printf '\nSauvegardes (%s) - %s\n' "${#backup_files[@]}" "$BACKUP_DIR"
  printf '%-20s %-10s %s\n' "DATE" "TAILLE" "FICHIER"
  local file
  for file in "${backup_files[@]}"; do
    printf '%-20s %-10s %s\n' \
      "$(date -r "$file" '+%Y-%m-%d %H:%M:%S')" \
      "$(du -h "$file" | awk '{print $1}')" \
      "$(basename "$file")"
  done
  printf '\n'
}

case "$ACTION" in
  list)
    show_backups
    ;;
  prune)
    if ((${#backup_files[@]} <= KEEP)); then
      log "${#backup_files[@]} sauvegarde(s): rien a supprimer (conservation: ${KEEP})."
      exit 0
    fi
    show_backups
    delete_count=$((${#backup_files[@]} - KEEP))
    confirm "Supprimer les ${delete_count} sauvegarde(s) les plus anciennes ?" "$ASSUME_YES" ||
      die "Nettoyage annule."
    for ((index = KEEP; index < ${#backup_files[@]}; index++)); do
      rm -f -- "${backup_files[$index]}"
    done
    log "Nettoyage termine. ${KEEP} sauvegarde(s) recente(s) conservee(s)."
    ;;
  delete-all)
    ((${#backup_files[@]} > 0)) || { log "Aucune sauvegarde a supprimer."; exit 0; }
    show_backups
    if [[ "$ASSUME_YES" != "true" ]]; then
      read -r -p 'Saisissez SUPPRIMER SAUVEGARDES pour confirmer: ' confirmation
      [[ "$confirmation" == "SUPPRIMER SAUVEGARDES" ]] || die "Suppression annulee."
    fi
    rm -f -- "${backup_files[@]}"
    log "Toutes les sauvegardes AI Deep Monitor ont ete supprimees."
    ;;
esac
