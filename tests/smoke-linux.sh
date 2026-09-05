#!/usr/bin/env bash

set -Eeuo pipefail

KIT_DIR="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
INSTALL_DIR="$(mktemp -d -t ai-monitor-kit-test-XXXXXX)"
CLIENT_KIT_RELEASE_DIR="$(mktemp -d -t ai-monitor-kit-release-test-XXXXXX)"
trap 'rm -rf -- "$INSTALL_DIR" "$CLIENT_KIT_RELEASE_DIR"' EXIT

update_source="${KIT_DIR}/scripts/linux/update-client.sh"
agent_repair_line="$(grep -n 'if \[\[ "\$SKIP_AGENT_INSTALL" == "false" \]\]' "$update_source" | head -n 1 | cut -d: -f1)"
same_version_line="$(grep -n 'if \[\[ "\$current_version" == "\$APP_VERSION" \]\]' "$update_source" | head -n 1 | cut -d: -f1)"
test -n "$agent_repair_line"
test -n "$same_version_line"
test "$agent_repair_line" -lt "$same_version_line"
grep -Fq "Mettre a jour l'application, le Client Kit et le terminal" "${KIT_DIR}/ai-deep-monitor.sh"

if "${KIT_DIR}/scripts/linux/install-client.sh" \
  --install-dir "${INSTALL_DIR}/unsafe-login-bypass" \
  --skip-docker-login 2>"${INSTALL_DIR}/unsafe-login-bypass.err"; then
  echo "Le contournement GHCR a ete accepte pour une installation reelle." >&2
  exit 1
fi
grep -Fq -- '--skip-docker-login est reserve' "${INSTALL_DIR}/unsafe-login-bypass.err"

"${KIT_DIR}/scripts/linux/install-client.sh" \
  --install-dir "$INSTALL_DIR" \
  --no-start \
  --skip-docker-login

! grep -q '^KIT_VERSION=' "${INSTALL_DIR}/.env"
grep -Fxq 'APP_VERSION=v0.1.22' "${INSTALL_DIR}/.env"
grep -Fxq 'DOCKER_PLATFORM=linux/amd64' "${INSTALL_DIR}/.env"
grep -Fxq 'LLAMA_CPP_MODEL=Llama-3.2-3B-Instruct-Q4_K_M' "${INSTALL_DIR}/.env"
grep -Fxq 'LLAMA_CPP_RUNTIME_PROFILE=auto' "${INSTALL_DIR}/.env"
grep -Fxq 'LLAMA_CPP_ACCELERATOR=cpu' "${INSTALL_DIR}/.env"
grep -Fxq 'LLAMA_CPP_GPU_LAYERS=0' "${INSTALL_DIR}/.env"
grep -Fxq 'LLAMA_CPP_FLASH_ATTN=off' "${INSTALL_DIR}/.env"
grep -Fxq 'NVIDIA_VISIBLE_DEVICES=all' "${INSTALL_DIR}/.env"
grep -Fxq 'HOST_TERMINAL_QUEUE_GID=10003' "${INSTALL_DIR}/.env"
grep -Fxq 'TERMINAL_SESSION_TTL_SECONDS=300' "${INSTALL_DIR}/.env"
grep -Fxq 'TERMINAL_POLICY_ADMIN_PASSWORD=ysitech1234' "${INSTALL_DIR}/.env"
test -x "${INSTALL_DIR}/update-client.sh"
test -x "${INSTALL_DIR}/backup-maintenance.sh"
test -x "${INSTALL_DIR}/ai-deep-monitor.sh"
grep -Fq 'compose_runtime_exec' "${INSTALL_DIR}/ai-deep-monitor.sh"
grep -Fq 'compose_runtime_exec' "${INSTALL_DIR}/backup-client.sh"
grep -Fq 'compose_runtime_exec' "${INSTALL_DIR}/restore-client.sh"
grep -Fq 'compose_runtime_exec' "${INSTALL_DIR}/uninstall-client.sh"
test -x "${INSTALL_DIR}/repair-terminal.sh"
test -x "${INSTALL_DIR}/verify-llama-gpu.sh"
test -f "${INSTALL_DIR}/repair-terminal.ps1"
test -f "${INSTALL_DIR}/AI-Deep-Monitor.cmd"
test -f "${INSTALL_DIR}/docker-compose.release.yml"
test -f "${INSTALL_DIR}/docker-compose.accel.nvidia.yml"
test -f "${INSTALL_DIR}/docker-compose.accel.jetson.yml"
test -f "${INSTALL_DIR}/Dockerfile.llama-cuda"
test -f "${INSTALL_DIR}/client-platform.ps1"
test -f "${INSTALL_DIR}/host_terminal_agent/agent.py"
test -f "${INSTALL_DIR}/host_terminal_agent/terminal_policy.py"
test -x "${INSTALL_DIR}/host_terminal_agent/install_linux_service.sh"
python3 "${INSTALL_DIR}/host_terminal_agent/agent.py" --help >/dev/null

# Simule la release permanente avec un marqueur absent de l'installation,
# puis verifie que l'ancien updater se remplace et synchronise tout le kit.
fixture_parent="${CLIENT_KIT_RELEASE_DIR}/package"
fixture_root="${fixture_parent}/ai-deep-monitor-client-kit"
mkdir -p "$fixture_root"
for directory in deploy docs host_terminal_agent scripts; do
  cp -a "${KIT_DIR}/${directory}" "$fixture_root/"
done
for file in AI-Deep-Monitor.cmd ai-deep-monitor.ps1 ai-deep-monitor.sh CHANGELOG.md README.md; do
  cp -a "${KIT_DIR}/${file}" "$fixture_root/"
done
printf '\nCLIENT_KIT_SELF_REFRESH_OK\n' >>"${fixture_root}/docs/installation.md"
(
  cd "$fixture_parent"
  tar -czf "${CLIENT_KIT_RELEASE_DIR}/ai-deep-monitor-client-kit.tar.gz" \
    ai-deep-monitor-client-kit
)
(
  cd "$CLIENT_KIT_RELEASE_DIR"
  sha256sum ai-deep-monitor-client-kit.tar.gz >ai-deep-monitor-client-kit-SHA256.txt
)
printf 'ANCIEN_CLIENT_KIT\n' >"${INSTALL_DIR}/README_CLIENT.md"
AI_DEEP_MONITOR_CLIENT_KIT_RELEASE_BASE="$CLIENT_KIT_RELEASE_DIR" \
  "${INSTALL_DIR}/update-client.sh" \
  --install-dir "$INSTALL_DIR" \
  --refresh-kit-only \
  --skip-agent-install
grep -Fq 'CLIENT_KIT_SELF_REFRESH_OK' "${INSTALL_DIR}/README_CLIENT.md"
grep -Fq 'stage_latest_client_kit' "${INSTALL_DIR}/update-client.sh"

printf '%064d  ai-deep-monitor-client-kit.tar.gz\n' 0 \
  >"${CLIENT_KIT_RELEASE_DIR}/ai-deep-monitor-client-kit-SHA256.txt"
printf 'FICHIER_A_CONSERVER\n' >"${INSTALL_DIR}/README_CLIENT.md"
if AI_DEEP_MONITOR_CLIENT_KIT_RELEASE_BASE="$CLIENT_KIT_RELEASE_DIR" \
  "${INSTALL_DIR}/update-client.sh" \
  --install-dir "$INSTALL_DIR" \
  --refresh-kit-only \
  --skip-agent-install 2>"${INSTALL_DIR}/invalid-kit.err"; then
  echo "Une archive Client Kit avec une somme invalide a ete acceptee." >&2
  exit 1
fi
grep -Fq 'corrompue' "${INSTALL_DIR}/invalid-kit.err"
grep -Fxq 'FICHIER_A_CONSERVER' "${INSTALL_DIR}/README_CLIENT.md"

sed -i '/^LLAMA_CPP_/d; /^NVIDIA_VISIBLE_DEVICES=/d' "${INSTALL_DIR}/.env"
printf 'OLLAMA_MODEL=llama3.1\nOLLAMA_FALLBACK_MODEL=llama3.1\n' >>"${INSTALL_DIR}/.env"
sed -i 's/^HOST_TERMINAL_QUEUE_GID=.*/HOST_TERMINAL_QUEUE_GID=12003/' "${INSTALL_DIR}/.env"
sed -i 's/^TERMINAL_SESSION_TTL_SECONDS=.*/TERMINAL_SESSION_TTL_SECONDS=420/' "${INSTALL_DIR}/.env"
printf 'KIT_VERSION=v0.1.15\n' >>"${INSTALL_DIR}/.env"
"${INSTALL_DIR}/update-client.sh" \
  --install-dir "$INSTALL_DIR" \
  --skip-kit-refresh \
  --no-start \
  --app-version v0.1.9

! grep -q '^KIT_VERSION=' "${INSTALL_DIR}/.env"
! grep -q '/app/generated_backups' "${INSTALL_DIR}/backup-client.sh"
grep -Fq '"generatedBackupsIncluded": false' "${INSTALL_DIR}/backup-client.sh"
grep -Fq 'gzip -1' "${INSTALL_DIR}/backup-client.sh"
grep -Fq 'MAX_UPDATE_SECONDS = 3_600' "${INSTALL_DIR}/host_terminal_agent/agent.py"
grep -Fq 'def refresh_client_kit' "${INSTALL_DIR}/host_terminal_agent/agent.py"
grep -Fq 'client_kit_update_failed' "${INSTALL_DIR}/host_terminal_agent/agent.py"
! grep -q '^OLLAMA_' "${INSTALL_DIR}/.env"
grep -Fxq 'LLAMA_CPP_MODEL=Llama-3.2-3B-Instruct-Q4_K_M' "${INSTALL_DIR}/.env"
grep -Fxq 'LLAMA_CPP_RUNTIME_PROFILE=auto' "${INSTALL_DIR}/.env"
grep -Fxq 'LLAMA_CPP_ACCELERATOR=cpu' "${INSTALL_DIR}/.env"
grep -Fxq 'LLAMA_CPP_GPU_LAYERS=0' "${INSTALL_DIR}/.env"
grep -Fxq 'NVIDIA_VISIBLE_DEVICES=all' "${INSTALL_DIR}/.env"
grep -Fxq 'HOST_TERMINAL_QUEUE_GID=12003' "${INSTALL_DIR}/.env"
grep -Fxq 'TERMINAL_SESSION_TTL_SECONDS=420' "${INSTALL_DIR}/.env"

BACKUP_DIR="${INSTALL_DIR}/test-backups"
mkdir -p "$BACKUP_DIR"
touch -d '2026-01-01' "${BACKUP_DIR}/ai-deep-monitor-old.tar.gz"
touch -d '2026-01-02' "${BACKUP_DIR}/ai-deep-monitor-middle.tar.gz"
touch -d '2026-01-03' "${BACKUP_DIR}/ai-deep-monitor-new.tar.gz"
"${INSTALL_DIR}/backup-maintenance.sh" \
  --install-dir "$INSTALL_DIR" \
  --backup-dir "$BACKUP_DIR" \
  --action prune \
  --keep 2 \
  --yes
test "$(find "$BACKUP_DIR" -maxdepth 1 -type f | wc -l)" -eq 2
test ! -e "${BACKUP_DIR}/ai-deep-monitor-old.tar.gz"
"${INSTALL_DIR}/backup-maintenance.sh" \
  --install-dir "$INSTALL_DIR" \
  --backup-dir "$BACKUP_DIR" \
  --action delete-selected \
  --file "ai-deep-monitor-middle.tar.gz" \
  --yes
test "$(find "$BACKUP_DIR" -maxdepth 1 -type f | wc -l)" -eq 1
test ! -e "${BACKUP_DIR}/ai-deep-monitor-middle.tar.gz"
test -e "${BACKUP_DIR}/ai-deep-monitor-new.tar.gz"

if [[ "${SKIP_COMPOSE_TEST:-false}" != "true" ]]; then
  docker compose \
    -f "${KIT_DIR}/deploy/docker-compose.release.yml" \
    --env-file "${INSTALL_DIR}/.env" \
    config --format json |
    python3 -c '
import json, sys
config = json.load(sys.stdin)
service = config["services"]["llama-cpp"]
command = service["command"]
assert "--n-gpu-layers" in command and command[command.index("--n-gpu-layers") + 1] == "0"
assert "--flash-attn" in command and command[command.index("--flash-attn") + 1] == "off"
assert service["image"].startswith("ghcr.io/ggml-org/llama.cpp:server@sha256:")
assert not service.get("gpus")
assert any(volume.get("target") == "/root/.cache/llama.cpp" for volume in service["volumes"])
assert "llama-cpp" in config["services"]["api"]["depends_on"]
mysql_health = config["services"]["mysql"]["healthcheck"]["test"]
assert "--protocol=tcp" in mysql_health[1]
assert "127.0.0.1" in mysql_health[1]
api_command = " ".join(config["services"]["api"]["command"])
assert "until alembic upgrade head" in api_command
assert "DB_INIT_RETRIES" in api_command
'
  docker compose \
    -f "${KIT_DIR}/deploy/docker-compose.release.yml" \
    --env-file "${INSTALL_DIR}/.env" \
    config --services | grep -Fxq collector
  docker compose \
    -f "${KIT_DIR}/deploy/docker-compose.release.yml" \
    -f "${KIT_DIR}/deploy/docker-compose.accel.nvidia.yml" \
    --env-file "${INSTALL_DIR}/.env" \
    config --format json |
    python3 -c '
import json, sys
service = json.load(sys.stdin)["services"]["llama-cpp"]
assert service.get("gpus")
'
fi
printf 'LINUX_NO_START_OK\n'
