#!/usr/bin/env bash
# Run on the Docker host. Compatible with already deployed v0.1.36 images.
set -Eeuo pipefail
if [[ $# -ne 2 ]]; then
  echo 'Usage: bash repair-backup-permissions.sh API_CONTAINER SCHEDULER_CONTAINER' >&2
  exit 2
fi
api="$1"
scheduler="$2"

# Discover the effective users, including deployments overriding Compose user.
api_uid="$(docker exec "$api" id -u)"
api_gid="$(docker exec "$api" id -g)"
scheduler_uid="$(docker exec "$scheduler" id -u)"
[[ "$api_uid" =~ ^[0-9]+$ && "$api_gid" =~ ^[0-9]+$ && "$api_uid" == "$scheduler_uid" ]] || {
  echo 'API and scheduler must use the same numeric UID; no permissions changed.' >&2
  exit 1
}
source_path=''
for container in "$api" "$scheduler"; do
  mount="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/backups"}}{{.Type}}|{{.Source}}|{{.RW}}{{end}}{{end}}' "$container")"
  [[ "$mount" == bind\|*\|true ]] || {
    echo "$container: /backups must be a writable host bind mount; no permissions changed." >&2
    exit 1
  }
  [[ -z "$source_path" || "$mount" == "$source_path" ]] || {
    echo 'API and scheduler have different backup mounts; no permissions changed.' >&2
    exit 1
  }
  source_path="$mount"
done

# Leave an already usable mount alone. Probe with each service's actual user.
probe='import tempfile; f = tempfile.TemporaryFile(dir="/backups"); f.write(b"backup write check"); f.flush(); f.close()'
if docker exec "$api" python -c "$probe" && docker exec "$scheduler" python -c "$probe"; then
  echo '/backups is already writable by both services.'
  exit 0
fi

# Change only the mounted directory, never its contents or other host disks.
# Opening without following links pins the exact directory being repaired.
docker exec -i --user 0:0 "$api" python - "$api_uid" "$api_gid" <<'PY'
import os
import stat
import sys

fd = os.open('/backups', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
try:
    mode = stat.S_IMODE(os.fstat(fd).st_mode)
    os.fchown(fd, int(sys.argv[1]), int(sys.argv[2]))
    os.fchmod(fd, mode | stat.S_IRWXU)
finally:
    os.close(fd)
PY
docker exec "$api" python -c "$probe"
docker exec "$scheduler" python -c "$probe"
echo '/backups: write access verified for API and scheduler.'
