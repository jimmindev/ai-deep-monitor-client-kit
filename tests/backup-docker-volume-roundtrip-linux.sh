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
case "$1" in
  info)
    [[ "${2:-}" != --format ]] || printf 'linux|amd64\n'
    ;;
  inspect)
    if [[ "$*" == *'.Image'* ]]; then printf 'fake-mysql-image\n';
    else printf 'healthy\n'; fi
    ;;
  compose)
    if [[ " $* " == *' ps -q mysql '* || " $* " == *' ps -a -q mysql '* ]]; then
      printf 'fake-mysql-container\n'
    fi
    ;;
  cp)
    if [[ "$2" == fake-mysql-container:* ]]; then
      printf 'CREATE TABLE test (id INT);\n' > "$3"
    fi
    ;;
  run)
    if [[ " $* " == *' -i '* ]]; then
      cat > "$TEST_DOCKER_ARCHIVE"
    else
      cat "$TEST_DOCKER_ARCHIVE"
    fi
    ;;
esac
exit 0
EOF
cat > "$test_root/bin/findmnt" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$test_root/bin/docker" "$test_root/bin/findmnt"
export PATH="$test_root/bin:$PATH"
export TEST_DOCKER_ARCHIVE="$test_root/archive.tar.gz"
export AI_DEEP_MONITOR_NETWORK_MOUNTS_ROOT="$test_root/network"

bash "$KIT_DIR/scripts/linux/backup-client.sh" --install-dir "$test_root/install" > "$test_root/output"
[[ -s "$TEST_DOCKER_ARCHIVE" ]]
tar -tzf "$TEST_DOCKER_ARCHIVE" | grep -Fq './manifest.json'
tar -tzf "$TEST_DOCKER_ARCHIVE" | grep -Fq './mysql.sql'
reference="$(sed -n 's/^.*Sauvegarde terminee: \(docker-volume:\/\/[^ ]*\).*/\1/p' "$test_root/output")"
[[ "$reference" == docker-volume://* ]]

if printf 'n\n' | bash "$KIT_DIR/scripts/linux/restore-client.sh" \
    --install-dir "$test_root/install" --backup-file "$reference" > "$test_root/restore-output" 2>&1; then
  echo 'The restore should stop at the confirmation prompt.' >&2
  exit 1
fi
grep -Fq 'Restauration annulee' "$test_root/restore-output"
grep -Fq 'mysql.sql: OK' "$test_root/restore-output"
echo DOCKER_VOLUME_BACKUP_ROUNDTRIP_OK
