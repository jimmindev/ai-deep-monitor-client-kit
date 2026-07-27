#!/usr/bin/env bash

set -Eeuo pipefail

KIT_DIR="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
TEST_HOME="$(mktemp -d -t ai-monitor-menu-test-XXXXXX)"
trap 'rm -rf -- "$TEST_HOME"' EXIT

output="$(
  printf '3\n0\n' |
    HOME="$TEST_HOME" TERM=dumb \
      "${KIT_DIR}/ai-deep-monitor.sh" \
      --install-dir "${TEST_HOME}/missing-installation" 2>&1
)"

grep -Fq 'Aucune installation trouvee' <<<"$output"
if [[ "$(grep -Fc 'AI Deep Monitor' <<<"$output")" -lt 2 ]]; then
  printf 'Le menu ne s est pas affiche une seconde fois apres l erreur.\n' >&2
  exit 1
fi

printf 'LINUX_MENU_PERSISTENCE_OK\n'
