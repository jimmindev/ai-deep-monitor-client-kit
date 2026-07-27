#!/usr/bin/env bash

set -Eeuo pipefail

KIT_DIR="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
TEST_DIR="$(mktemp -d -t ai-monitor-backup-selection-XXXXXX)"
trap 'rm -rf -- "$TEST_DIR"' EXIT

touch "${TEST_DIR}/ai-deep-monitor-a.tar.gz"
touch "${TEST_DIR}/ai-deep-monitor-ab.tar.gz"
touch "${TEST_DIR}/ai-deep-monitor-b.tar.gz"

"${KIT_DIR}/scripts/linux/backup-maintenance.sh" \
  --install-dir "${TEST_DIR}/install" \
  --backup-dir "$TEST_DIR" \
  --action delete-selected \
  --file "ai-deep-monitor-a.tar.gz" \
  --yes

test ! -e "${TEST_DIR}/ai-deep-monitor-a.tar.gz"
test -e "${TEST_DIR}/ai-deep-monitor-ab.tar.gz"
test -e "${TEST_DIR}/ai-deep-monitor-b.tar.gz"
test "$(find "$TEST_DIR" -maxdepth 1 -type f | wc -l)" -eq 2

touch "${TEST_DIR}/ai-deep-monitor-c.tar.gz"
touch -d '2026-01-01' "${TEST_DIR}/ai-deep-monitor-ab.tar.gz"
touch -d '2026-01-02' "${TEST_DIR}/ai-deep-monitor-b.tar.gz"
touch -d '2026-01-03' "${TEST_DIR}/ai-deep-monitor-c.tar.gz"

printf '1,3\n' |
  "${KIT_DIR}/scripts/linux/backup-maintenance.sh" \
    --install-dir "${TEST_DIR}/install" \
    --backup-dir "$TEST_DIR" \
    --action delete-selected \
    --yes

test ! -e "${TEST_DIR}/ai-deep-monitor-c.tar.gz"
test -e "${TEST_DIR}/ai-deep-monitor-b.tar.gz"
test ! -e "${TEST_DIR}/ai-deep-monitor-ab.tar.gz"
test "$(find "$TEST_DIR" -maxdepth 1 -type f | wc -l)" -eq 1

printf 'LINUX_NUMERIC_SELECTION_OK\n'
