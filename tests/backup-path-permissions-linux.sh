#!/usr/bin/env bash
set -Eeuo pipefail

KIT_DIR="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
TEST_DIR="$(mktemp -d -t ai-monitor-backup-path-XXXXXX)"
trap 'rm -rf -- "$TEST_DIR"' EXIT

# shellcheck source=../scripts/linux/client-common.sh
source "${KIT_DIR}/scripts/linux/client-common.sh"
configure_sudo() { :; }
run_root() { printf '%s\n' "$*" >>"${TEST_DIR}/commands"; }

touch "${TEST_DIR}/.env"
prepare_default_backup_path "$TEST_DIR" "${TEST_DIR}/.env"
grep -Fxq "install -d -o 1000 -g 1000 -m 0770 ${TEST_DIR}/backups" "${TEST_DIR}/commands"

: >"${TEST_DIR}/commands"
printf 'BACKUP_HOST_PATH=/mnt/external\n' >"${TEST_DIR}/.env"
prepare_default_backup_path "$TEST_DIR" "${TEST_DIR}/.env"
test ! -s "${TEST_DIR}/commands"

printf 'BACKUP_HOST_PATH=./backups\n' >"${TEST_DIR}/.env"
mkdir "${TEST_DIR}/other"
ln -s "${TEST_DIR}/other" "${TEST_DIR}/backups"
if [[ -L "${TEST_DIR}/backups" ]]; then
  if (prepare_default_backup_path "$TEST_DIR" "${TEST_DIR}/.env") 2>/dev/null; then
    echo 'A symbolic link must be rejected.' >&2
    exit 1
  fi
fi

echo BACKUP_PATH_PERMISSIONS_OK
