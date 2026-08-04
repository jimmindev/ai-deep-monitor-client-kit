#!/usr/bin/env bash

set -Eeuo pipefail

KIT_DIR="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
TEST_DIR="$(mktemp -d -t ai-monitor-registry-test-XXXXXX)"
trap 'rm -rf -- "$TEST_DIR"' EXIT

export HOME="${TEST_DIR}/home"
export PATH="${TEST_DIR}/bin:${PATH}"
export REGISTRY_TEST_LOG="${TEST_DIR}/registry.log"
mkdir -p "${HOME}" "${TEST_DIR}/bin"

cat >"${TEST_DIR}/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'ARGS:%s\n' "$*" >>"${REGISTRY_TEST_LOG}"
printf 'CONFIG:%s\n' "${DOCKER_CONFIG:-}" >>"${REGISTRY_TEST_LOG}"
printf 'TOKEN:' >>"${REGISTRY_TEST_LOG}"
cat >>"${REGISTRY_TEST_LOG}"
printf '\n' >>"${REGISTRY_TEST_LOG}"
EOF
cat >"${TEST_DIR}/bin/sudo" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
chmod +x "${TEST_DIR}/bin/docker" "${TEST_DIR}/bin/sudo"

# shellcheck source=../scripts/linux/client-common.sh
source "${KIT_DIR}/scripts/linux/client-common.sh"

# Simulate a host where Compose requires sudo. The helper must authenticate
# both clients, and the first login must always target the non-root profile
# used by the protected host agent.
DOCKER_CMD=(sudo docker)
docker_registry_login ghcr.io client-reader super-secret-test-token

test "$(grep -c '^ARGS:' "$REGISTRY_TEST_LOG")" -eq 2
grep -Fxq "CONFIG:${HOME}/.docker" "$REGISTRY_TEST_LOG"
test "$(grep -c '^TOKEN:super-secret-test-token$' "$REGISTRY_TEST_LOG")" -eq 2
! grep '^ARGS:' "$REGISTRY_TEST_LOG" | grep -q 'super-secret-test-token'
test "$(stat -c '%a' "${HOME}/.docker")" = "700"

printf 'REGISTRY_LOGIN_OK\n'
