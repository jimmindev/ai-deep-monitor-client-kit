"""Root-only, narrowly scoped Linux time configurator for the non-root host agent."""
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import re
import secrets
import shutil
import subprocess
import time
from pathlib import Path

BASE = Path("/var/lib/ai-deep-monitor-host-time")
ZONEINFO = Path("/usr/share/zoneinfo")
ID_RE = re.compile(r"[0-9a-f]{32}\Z")
ZONE_RE = re.compile(r"[A-Za-z0-9_+.-]+(?:/[A-Za-z0-9_+.-]+)*\Z")
NTP_RE = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9.:-]{0,251}[A-Za-z0-9])?\Z")


def signature(key: bytes, payload: dict) -> str:
    data = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    return hmac.new(key, data, hashlib.sha256).hexdigest()


def validate(timezone: str, server: str, zoneinfo: Path = ZONEINFO) -> None:
    if not ZONE_RE.fullmatch(timezone) or any(part in {".", ".."} for part in timezone.split("/")) or not (zoneinfo / timezone).is_file():
        raise ValueError("Fuseau horaire invalide ou absent sur l’hôte.")
    if not NTP_RE.fullmatch(server):
        raise ValueError("Adresse du serveur NTP invalide.")


def apply_time(timezone: str, server: str) -> dict:
    validate(timezone, server)
    if not shutil.which("timedatectl") or not shutil.which("systemctl"):
        raise ValueError("systemd et timedatectl sont nécessaires sur cet hôte.")
    subprocess.run(["systemctl", "cat", "systemd-timesyncd.service"], check=True, capture_output=True, timeout=5)
    subprocess.run(["timedatectl", "set-timezone", timezone], check=True, timeout=8)
    folder = Path("/etc/systemd/timesyncd.conf.d")
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / "ai-deep-monitor.conf"
    temporary = folder / f".ai-deep-monitor-{secrets.token_hex(4)}.tmp"
    try:
        temporary.write_text(f"[Time]\nNTP={server}\n", encoding="ascii")
        temporary.chmod(0o644)
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)
    subprocess.run(["systemctl", "restart", "systemd-timesyncd.service"], check=True, timeout=8)
    subprocess.run(["timedatectl", "set-ntp", "true"], check=True, timeout=8)
    state = subprocess.run(["timedatectl", "show", "-p", "Timezone", "-p", "NTPSynchronized"], check=True, capture_output=True, text=True, timeout=5)
    return {"ok": True, "timezone": timezone, "ntp_server": server, "status": state.stdout.strip()}


def process(path: Path, key: bytes, base: Path = BASE) -> None:
    request_id = path.stem
    try:
        if not ID_RE.fullmatch(request_id):
            return
        envelope = json.loads(path.read_text(encoding="utf-8"))
        payload = envelope.get("payload")
        if not isinstance(payload, dict) or not hmac.compare_digest(str(envelope.get("signature") or ""), signature(key, payload)):
            return
        if payload.get("id") != request_id or abs(time.time() - float(payload.get("issued_at") or 0)) > 30:
            return
        try:
            result = apply_time(str(payload.get("timezone") or ""), str(payload.get("ntp_server") or ""))
        except (ValueError, OSError, subprocess.SubprocessError) as exc:
            result = {"ok": False, "error": str(exc)}
        response = {"id": request_id, **result}
        output = base / "outgoing" / f"{request_id}.json"
        temporary = base / "outgoing" / f".{request_id}.{secrets.token_hex(4)}.tmp"
        temporary.write_text(json.dumps({"payload": response, "signature": signature(key, response)}, ensure_ascii=False), encoding="utf-8")
        temporary.chmod(0o640)
        os.replace(temporary, output)
    finally:
        path.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path, default=BASE)
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise SystemExit("Le service horaire doit être exécuté par root.")
    base = args.base
    key = bytes.fromhex((base / ".agent-key").read_text(encoding="ascii").strip())
    if len(key) < 32:
        raise SystemExit("Clé du service horaire invalide.")
    while True:
        (base / "ready").touch()
        for path in (base / "incoming").glob("*.json"):
            try:
                process(path, key, base)
            except (OSError, ValueError, json.JSONDecodeError):
                path.unlink(missing_ok=True)
        for path in (base / "outgoing").glob("*.json"):
            if time.time() - path.stat().st_mtime > 300:
                path.unlink(missing_ok=True)
        time.sleep(0.25)


if __name__ == "__main__":
    main()
