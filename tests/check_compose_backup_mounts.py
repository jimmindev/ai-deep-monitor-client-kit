"""Ensure the published Compose stack exposes backup destinations to both writers."""
import json
import os
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[1]
env = os.environ.copy()
env.update({
    "MYSQL_USER": "test",
    "MYSQL_PASSWORD": "test",
    "MYSQL_ROOT_PASSWORD": "test",
    "MYSQL_DATABASE": "test",
    "AUTH_SECRET_KEY": "test",
    "CORS_ORIGINS": "http://localhost",
})
result = subprocess.run(
    ["docker", "compose", "-f", "deploy/docker-compose.release.yml", "-f",
     "deploy/docker-compose.linux-host-storage.yml", "config", "--format", "json"],
    cwd=ROOT, env=env, capture_output=True, text=True, check=True,
)
services = json.loads(result.stdout)["services"]
backup_sources = []
for service_name in ("api", "backup-scheduler"):
    volumes = {volume["target"]: volume for volume in services[service_name]["volumes"]}
    backup = volumes["/backups"]
    assert backup["type"] == "bind" and backup["source"], service_name
    backup_sources.append(backup["source"])
    for target in ("/host/mnt", "/host/media", "/host/run/media"):
        assert volumes[target]["bind"]["propagation"] == "rslave", (service_name, target)
assert backup_sources[0] == backup_sources[1], backup_sources
print("COMPOSE_BACKUP_MOUNTS_OK")
