#!/usr/bin/env bash
set -Eeuo pipefail
kit="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="$(mktemp -d -t ai-monitor-update-order-XXXXXX)"
trap 'rm -rf -- "$workspace"' EXIT
mkdir "$workspace/bin"
cat > "$workspace/bin/docker" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$UPDATE_ORDER_LOG"
case "$*" in
  'info --format '* ) echo 'linux|amd64' ;;
  'inspect '* ) echo healthy ;;
  *'run --rm --no-deps api alembic upgrade head'* ) exit "$UPDATE_ORDER_MIGRATION_EXIT" ;;
esac
MOCK
chmod +x "$workspace/bin/docker"
printf '#!/usr/bin/env bash\nexit 1\n' > "$workspace/bin/curl"
chmod +x "$workspace/bin/curl"
for result in 0 1; do
  install="$workspace/client-$result"
  "$kit/scripts/linux/install-client.sh" --install-dir "$install" --no-start --skip-docker-login > /dev/null
  export UPDATE_ORDER_LOG="$workspace/calls-$result" UPDATE_ORDER_MIGRATION_EXIT="$result"
  status=0
  PATH="$workspace/bin:$PATH" "$kit/scripts/linux/update-client.sh" --install-dir "$install" --app-version v0.1.99 --yes --skip-backup --skip-agent-install --skip-docker-login --skip-kit-refresh --llama-profile cpu > "$workspace/output-$result" 2>&1 || status=$?
  if ! grep -q 'run --rm --no-deps api alembic upgrade head' "$UPDATE_ORDER_LOG"; then cat "$workspace/output-$result"; cat "$UPDATE_ORDER_LOG"; exit 1; fi
  python3 - "$UPDATE_ORDER_LOG" "$result" "$status" "$install/.env" <<'PY'
import sys
from pathlib import Path
log, result, status, env = sys.argv[1:]
calls=Path(log).read_text().splitlines()
migration=next(i for i,c in enumerate(calls) if 'run --rm --no-deps api alembic upgrade head' in c)
starts=[i for i,c in enumerate(calls) if c.endswith(' up -d')]
if result=='0':
    assert status=='0' and starts and starts[0]>migration
    assert 'APP_VERSION=v0.1.99' in Path(env).read_text()
else:
    assert status!='0' and not starts
    assert 'APP_VERSION=v0.1.99' not in Path(env).read_text()
print('LINUX_UPDATE_ORDER_OK migration_exit='+result)
PY
done
