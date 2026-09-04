#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=client-common.sh
source "${SCRIPT_DIR}/client-common.sh"

ENV_FILE="${1:-${SCRIPT_DIR}/.env}"
[[ -f "$ENV_FILE" ]] || die "Configuration introuvable: ${ENV_FILE}"
ensure_docker

profile="$(read_env_value "$ENV_FILE" LLAMA_CPP_RUNTIME_PROFILE)"
image="$(read_env_value "$ENV_FILE" LLAMA_CPP_IMAGE)"
case "$profile" in
  cpu)
    log "Verification de l'image llama.cpp CPU (${DOCKER_PLATFORM})..."
    docker_exec run --rm --platform "$DOCKER_PLATFORM" "$image" --version >/dev/null
    log 'Runtime llama.cpp CPU valide.'
    ;;
  nvidia|jetson)
    log "Verification de llama.cpp CUDA (${profile}, ${DOCKER_PLATFORM})..."
    llama_gpu_probe "$profile" "$image" ||
      die "Le profil ${profile} memorise n'est plus compatible. Relancez update-client avec --redetect-llama-runtime."
    log 'Runtime llama.cpp CUDA valide.'
    ;;
  *)
    die "Profil llama.cpp non resolu: ${profile:-absent}. Relancez l'installation ou la mise a jour."
    ;;
esac
