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
declare -a REQUESTED_FILES=()

usage() {
  cat <<'EOF'
Usage: ./backup-maintenance.sh [options]

Options:
  --install-dir CHEMIN   Dossier de l'application
  --backup-dir CHEMIN    Dossier des sauvegardes
  --action ACTION        list, prune, delete-selected ou delete-all
  --keep N               Nombre d'archives recentes a conserver avec prune
  --file NOM             Archive a supprimer avec delete-selected (repetable)
  --yes                  Confirmer sans interaction
EOF
}

while (($#)); do
  case "$1" in
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    --backup-dir) BACKUP_DIR="$2"; shift 2 ;;
    --action) ACTION="$2"; shift 2 ;;
    --keep) KEEP="$2"; shift 2 ;;
    --file) REQUESTED_FILES+=("$2"); shift 2 ;;
    --yes) ASSUME_YES=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Option inconnue: $1" ;;
  esac
done

[[ "$ACTION" =~ ^(list|prune|delete-selected|delete-all)$ ]] || die "Action invalide: $ACTION"
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

show_numbered_backups() {
  local index file
  printf '\nSauvegardes disponibles\n'
  for index in "${!backup_files[@]}"; do
    file="${backup_files[$index]}"
    printf '  %2d. %-10s %s\n' \
      "$((index + 1))" \
      "$(du -h "$file" | awk '{print $1}')" \
      "$(basename "$file")"
  done
}

resolve_requested_files() {
  local requested file found
  selected_files=()
  for requested in "${REQUESTED_FILES[@]}"; do
    found=false
    for file in "${backup_files[@]}"; do
      if [[ "$(basename "$file")" == "$requested" ]]; then
        selected_files+=("$file")
        found=true
        break
      fi
    done
    [[ "$found" == "true" ]] || die "Sauvegarde introuvable: ${requested}"
  done
}

parse_numeric_selection() {
  local input="$1"
  local part start end index
  local -a parts
  local -a flags=()
  selected_files=()
  input="${input//;/,}"
  IFS=',' read -r -a parts <<<"$input"
  for part in "${parts[@]}"; do
    part="${part//[[:space:]]/}"
    if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start="${BASH_REMATCH[1]}"
      end="${BASH_REMATCH[2]}"
      ((start <= end)) || die "Plage invalide: ${part}"
      for ((index = start; index <= end; index++)); do
        ((index >= 1 && index <= ${#backup_files[@]})) ||
          die "Numero hors liste: ${index}"
        flags[$((index - 1))]=1
      done
    elif [[ "$part" =~ ^[0-9]+$ ]]; then
      index="$part"
      ((index >= 1 && index <= ${#backup_files[@]})) ||
        die "Numero hors liste: ${index}"
      flags[$((index - 1))]=1
    else
      die "Selection invalide: ${part}"
    fi
  done
  for index in "${!backup_files[@]}"; do
    [[ "${flags[$index]:-0}" == "1" ]] && selected_files+=("${backup_files[$index]}")
  done
  return 0
}

select_backups() {
  local input
  selected_files=()
  if ((${#REQUESTED_FILES[@]} > 0)); then
    resolve_requested_files
  else
    show_numbered_backups
    read -r -p 'Numeros a supprimer (exemple: 1,3,5-7; vide pour annuler): ' input
    [[ -n "$input" ]] || return 1
    parse_numeric_selection "$input"
  fi
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
  delete-selected)
    ((${#backup_files[@]} > 0)) || { log "Aucune sauvegarde a supprimer."; exit 0; }
    select_backups || { log "Selection annulee."; exit 0; }
    ((${#selected_files[@]} > 0)) || die "Aucune sauvegarde selectionnee."
    printf '\nSauvegarde(s) selectionnee(s):\n'
    printf '  - %s\n' "${selected_files[@]##*/}"
    confirm "Supprimer definitivement ces ${#selected_files[@]} sauvegarde(s) ?" "$ASSUME_YES" ||
      die "Suppression annulee."
    rm -f -- "${selected_files[@]}"
    log "${#selected_files[@]} sauvegarde(s) supprimee(s)."
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
