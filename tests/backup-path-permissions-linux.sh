#!/usr/bin/env bash
set -Eeuo pipefail

KIT_DIR="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
! grep -Fq 'prepare_default_backup_path' "${KIT_DIR}/scripts/linux/install-client.sh"
! grep -Fq 'prepare_default_backup_path' "${KIT_DIR}/scripts/linux/update-client.sh"
grep -Fq 'findmnt -T "$DESTINATION_DIR"' "${KIT_DIR}/scripts/linux/backup-client.sh"
grep -Fq 'MAINTENANCE_BACKUP_PATH' "${KIT_DIR}/scripts/linux/backup-client.sh"
grep -Fq 'mktemp -d "${DESTINATION_DIR}/.ai-monitor-backup-staging-XXXXXX"' "${KIT_DIR}/scripts/linux/backup-client.sh"

echo NETWORK_BACKUP_PATH_OK
