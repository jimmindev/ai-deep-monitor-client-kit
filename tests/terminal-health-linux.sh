#!/usr/bin/env bash

set -Eeuo pipefail
KIT_DIR="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
TEST_DIR="$(mktemp -d -t ai-monitor-terminal-test-XXXXXX)"
AGENT_PID=""

cleanup() {
  [[ -z "$AGENT_PID" ]] || kill "$AGENT_PID" 2>/dev/null || true
  rm -rf -- "$TEST_DIR"
}
trap cleanup EXIT

mkdir -p "$TEST_DIR/bin" "$TEST_DIR/host_terminal_jobs" "$TEST_DIR/state"
cp "${KIT_DIR}/tests/fixtures/systemctl" "$TEST_DIR/bin/systemctl"
chmod +x "$TEST_DIR/bin/systemctl"
printf 'HOST_TERMINAL_QUEUE_GID=10003\n' >"$TEST_DIR/.env"

python3 "${KIT_DIR}/host_terminal_agent/agent.py" \
  --jobs-dir "$TEST_DIR/host_terminal_jobs" \
  --install-dir "$TEST_DIR" \
  --state-dir "$TEST_DIR/state" &
AGENT_PID=$!

PATH="${TEST_DIR}/bin:${PATH}" \
  "${KIT_DIR}/scripts/linux/repair-terminal.sh" \
  --install-dir "$TEST_DIR" \
  --check-only

printf 'LINUX_TERMINAL_HEALTH_OK\n'
