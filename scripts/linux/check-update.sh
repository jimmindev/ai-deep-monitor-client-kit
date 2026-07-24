#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=client-common.sh
source "${SCRIPT_DIR}/client-common.sh"

INSTALL_DIR="${HOME}/ai-deep-monitor"
while (($#)); do
  case "$1" in
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    -h|--help)
      printf 'Usage: ./check-update.sh [--install-dir CHEMIN]\n'
      exit 0
      ;;
    *) die "Option inconnue: $1" ;;
  esac
done

ENV_FILE="${INSTALL_DIR}/.env"
[[ -f "$ENV_FILE" ]] || die "Installation introuvable: ${ENV_FILE}"
require_command curl

current_version="$(read_env_value "$ENV_FILE" APP_VERSION)"
owner="$(read_env_value "$ENV_FILE" GITHUB_OWNER)"
github_user="${UPDATE_CHECK_USER:-$(read_env_value "$ENV_FILE" UPDATE_CHECK_USER)}"
github_token="${UPDATE_CHECK_TOKEN:-$(read_env_value "$ENV_FILE" UPDATE_CHECK_TOKEN)}"
owner="${owner:-jimmindev}"

if [[ -z "$github_user" ]]; then
  read -r -p 'Utilisateur GitHub: ' github_user
fi
if [[ -z "$github_token" ]]; then
  read -r -s -p 'Token GitHub avec read:packages: ' github_token
  printf '\n'
fi

latest_version="$(latest_common_app_version "$owner" "$github_user" "$github_token")"
[[ -n "$latest_version" ]] || die "Aucune version commune API/frontend n'a ete trouvee."

printf 'Kit installe        : %s\n' "$(read_env_value "$ENV_FILE" KIT_VERSION)"
printf 'Application installee: %s\n' "$current_version"
printf 'Application disponible: %s\n' "$latest_version"

if [[ "$(printf '%s\n%s\n' "$current_version" "$latest_version" | sort -V | tail -n 1)" == "$latest_version" &&
      "$current_version" != "$latest_version" ]]; then
  printf 'Une mise a jour est disponible. Lancez ./update-client.sh\n'
  exit 10
fi

printf 'L installation applicative est a jour.\n'
