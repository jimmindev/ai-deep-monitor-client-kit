#!/usr/bin/env bash
set -Eeuo pipefail

KIT_DIR="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/install" "$test_root/network"
printf 'APP_VERSION=v0.1.49\n' > "$test_root/install/.env"
printf 'services: {}\n' > "$test_root/install/docker-compose.release.yml"
cat > "$test_root/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_DOCKER_LOG"
if [[ "$1" == info && "${2:-}" == --format ]]; then
  printf 'linux|amd64\n'
fi
exit 0
EOF
cat > "$test_root/bin/findmnt" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == -M ]]; then
  [[ "$2" == "$TEST_NETWORK_ROOT"/* ]] || exit 1
  printf 'nfs4\n'
elif [[ "$1" == -T ]]; then
  if [[ "$2" == "$TEST_NETWORK_ROOT"/* ]]; then
    printf 'nfs4\n'
  else
    printf 'ext4\n'
  fi
fi
EOF
chmod +x "$test_root/bin/docker" "$test_root/bin/findmnt"
export PATH="$test_root/bin:$PATH"
export TEST_NETWORK_ROOT="$test_root/network"
export TEST_DOCKER_LOG="$test_root/docker.log"
export AI_DEEP_MONITOR_NETWORK_MOUNTS_ROOT="$TEST_NETWORK_ROOT"

first="$TEST_NETWORK_ROOT/aaaaaaaaaaaaaaaaaaaaaaaa"
second="$TEST_NETWORK_ROOT/bbbbbbbbbbbbbbbbbbbbbbbb"
if bash "$KIT_DIR/scripts/linux/backup-client.sh" --install-dir "$test_root/install" >"$test_root/output" 2>&1; then
  exit 1
fi
grep -Fq 'volume Docker' "$test_root/output"
grep -Fq 'volume create --label ai-deep-monitor.purpose=maintenance-backup' "$TEST_DOCKER_LOG"
grep -Fq 'Conteneur MySQL introuvable' "$test_root/output"

printf 'MAINTENANCE_BACKUP_PATH=%s/offline/maintenance\n' "$TEST_NETWORK_ROOT" >> "$test_root/install/.env"
if bash "$KIT_DIR/scripts/linux/backup-client.sh" --install-dir "$test_root/install" >"$test_root/output" 2>&1; then
  exit 1
fi
grep -Fq 'partage de maintenance configure est indisponible' "$test_root/output"
grep -Fq 'volume Docker' "$test_root/output"
sed -i '/^MAINTENANCE_BACKUP_PATH=/d' "$test_root/install/.env"

mkdir "$first"
if bash "$KIT_DIR/scripts/linux/backup-client.sh" --install-dir "$test_root/install" >"$test_root/output" 2>&1; then
  echo 'Expected fake Docker to stop the backup after destination selection.' >&2
  exit 1
fi
[[ -d "$first/maintenance" ]] || { cat "$test_root/output"; exit 1; }
grep -Fq 'Conteneur MySQL introuvable' "$test_root/output"

mkdir "$second"
if bash "$KIT_DIR/scripts/linux/backup-client.sh" --install-dir "$test_root/install" >"$test_root/output" 2>&1; then
  exit 1
fi
grep -Fq 'Plusieurs partages reseau' "$test_root/output"
[[ ! -e "$second/maintenance" ]]

mkdir "$test_root/local"
if bash "$KIT_DIR/scripts/linux/backup-client.sh" --install-dir "$test_root/install" --destination-dir "$test_root/local" >"$test_root/output" 2>&1; then
  exit 1
fi
grep -Fq 'exige un partage reseau' "$test_root/output"

if bash "$KIT_DIR/scripts/linux/restore-client.sh" --install-dir "$test_root/install" \
    --backup-file 'docker-volume://other_project/example.tar.gz' >"$test_root/output" 2>&1; then
  exit 1
fi
grep -Fq "n'appartient pas a cette installation" "$test_root/output"
echo NETWORK_BACKUP_AUTO_SELECT_OK
