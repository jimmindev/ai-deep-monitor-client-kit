#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BASE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
ASSUME_YES=false

log() {
  printf '[AI Deep Monitor] %s\n' "$*"
}

die() {
  printf '[AI Deep Monitor] ERREUR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./cleanup-old-kits.sh [--base-dir CHEMIN] [--yes]

Supprime uniquement les anciens dossiers et archives du Client Kit.
L'application active, les volumes Docker et les sauvegardes sont conserves.
EOF
}

while (($#)); do
  case "$1" in
    --base-dir)
      [[ $# -ge 2 ]] || die "Valeur manquante apres --base-dir."
      BASE_DIR="$2"
      shift 2
      ;;
    --yes)
      ASSUME_YES=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Option inconnue: $1"
      ;;
  esac
done

[[ -d "$BASE_DIR" ]] || die "Dossier de recherche introuvable: ${BASE_DIR}"
BASE_DIR="$(cd -- "$BASE_DIR" && pwd -P)"

declare -a candidates=()
declare -A seen=()

while IFS= read -r -d '' candidate; do
  name="$(basename -- "$candidate")"

  case "$name" in
    ai-deep-monitor-client-kit)
      continue
      ;;
    ai-deep-monitor-client-kit-v*|ai-deep-monitor-client-kit-release-v*|\
    ai-deep-monitor-client-kit.tar.gz|ai-deep-monitor-client-kit.zip)
      ;;
    *)
      continue
      ;;
  esac

  parent="$(cd -- "$(dirname -- "$candidate")" && pwd -P)"
  [[ "$parent" == "$BASE_DIR" ]] ||
    die "Cible refusee hors du dossier de recherche: ${candidate}"

  if [[ -d "$candidate" ]]; then
    resolved="$(cd -- "$candidate" && pwd -P)"
    [[ "$resolved" != "$SCRIPT_DIR" ]] ||
      die "Suppression du dossier courant refusee: ${candidate}"
  fi

  if [[ -z "${seen[$candidate]:-}" ]]; then
    candidates+=("$candidate")
    seen["$candidate"]=1
  fi
done < <(find "$BASE_DIR" -mindepth 1 -maxdepth 1 -print0)

if ((${#candidates[@]} == 0)); then
  log "Aucun ancien Client Kit a nettoyer dans ${BASE_DIR}."
  exit 0
fi

log "Elements obsoletes detectes dans ${BASE_DIR}:"
for candidate in "${candidates[@]}"; do
  size="$(du -sh -- "$candidate" 2>/dev/null | awk '{print $1}')"
  printf '  - %s (%s)\n' "$(basename -- "$candidate")" "${size:-taille inconnue}"
done

printf '\n'
log "Sont conserves:"
printf '  - %s\n' "${BASE_DIR}/ai-deep-monitor-client-kit"
printf '  - %s\n' "${HOME}/ai-deep-monitor"
printf '  - les volumes Docker, MySQL et les sauvegardes\n'

if [[ "$ASSUME_YES" != "true" ]]; then
  read -r -p "Supprimer uniquement les elements listes ? [o/N] " answer
  [[ "${answer,,}" == "o" || "${answer,,}" == "oui" ]] || {
    log "Nettoyage annule."
    exit 0
  }
fi

for candidate in "${candidates[@]}"; do
  rm -rf -- "$candidate"
  log "Supprime: $(basename -- "$candidate")"
done

log "Nettoyage termine. L'installation AI Deep Monitor est conservee."
