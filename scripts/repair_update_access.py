"""Rotate read-only GHCR access without updating the installed application."""
from __future__ import annotations

import argparse
import base64
import getpass
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

DOCKER_EXECUTABLE = "docker"


class RepairError(RuntimeError):
    pass


def read_env(path: Path) -> dict[str, str]:
    values = {}
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        key, separator, value = line.partition("=")
        if separator and not key.lstrip().startswith("#"):
            values[key.strip()] = value.strip().strip("\"'")
    return values


def request_json(url: str, headers: dict[str, str]) -> tuple[dict, object]:
    request = urllib.request.Request(url, headers={"User-Agent": "AI-Deep-Monitor-access-repair", **headers})
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return json.load(response), response.headers
    except urllib.error.HTTPError as error:
        if error.code in {401, 403}:
            raise RepairError("Accès refusé : vérifiez le jeton et les permissions de lecture des images.") from None
        raise RepairError(f"Le service distant répond HTTP {error.code}.") from None
    except (urllib.error.URLError, TimeoutError):
        raise RepairError("Connexion impossible : vérifiez le réseau, le proxy et les certificats.") from None
    except (ValueError, KeyError):
        raise RepairError("Réponse distante invalide.") from None


def validate_access(username: str, token: str, owner: str) -> None:
    if not re.fullmatch(r"[A-Za-z0-9_-]+", token) or not re.fullmatch(r"[A-Za-z0-9-]+", owner):
        raise RepairError("Jeton ou propriétaire invalide.")
    profile, headers = request_json("https://api.github.com/user", {"Authorization": "Bearer " + token})
    if str(profile.get("login", "")).lower() != username.lower():
        raise RepairError("Le compte GitHub ne correspond pas au propriétaire du jeton.")
    scopes = {scope.strip() for scope in headers.get("X-OAuth-Scopes", "").split(",") if scope.strip()}
    if scopes != {"read:packages"}:
        raise RepairError("Utilisez un jeton GitHub classic avec read:packages uniquement.")
    basic = base64.b64encode((username + ":" + token).encode("ascii")).decode("ascii")
    for image in ("ai-deep-monitor-api", "ai-deep-monitor-frontend"):
        scope = urllib.parse.quote(f"repository:{owner}/{image}:pull", safe="")
        auth, _ = request_json("https://ghcr.io/token?service=ghcr.io&scope=" + scope, {"Authorization": "Basic " + basic})
        bearer = auth.get("token")
        if not bearer:
            raise RepairError("GHCR n’a pas fourni d’autorisation de lecture.")
        payload, _ = request_json(f"https://ghcr.io/v2/{owner}/{image}/tags/list?n=1", {"Authorization": "Bearer " + bearer})
        if not payload.get("tags"):
            raise RepairError("Aucune image disponible pour cette installation.")


def update_text(original: str, username: str, token: str) -> str:
    values = {"UPDATE_CHECK_USER": username, "UPDATE_CHECK_TOKEN": token}
    lines = []
    written = set()
    for line in original.splitlines():
        key = line.partition("=")[0].strip()
        if key in values:
            if key not in written:
                lines.append(key + "=" + values[key])
                written.add(key)
        else:
            lines.append(line)
    for key, value in values.items():
        if key not in written:
            lines.append(key + "=" + value)
    return "\n".join(lines) + "\n"


def private_write(path: Path, text: str) -> None:
    previous = path.stat() if path.exists() else None
    fd, temporary = tempfile.mkstemp(prefix=".update-access-", dir=path.parent)
    try:
        if os.name != "nt":
            os.fchmod(fd, 0o600)
            if previous:
                os.fchown(fd, previous.st_uid, previous.st_gid)
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as output:
            output.write(text)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def docker_run(args: list[str], *, input_text: str | None = None) -> str:
    try:
        result = subprocess.run([DOCKER_EXECUTABLE, *args], input=input_text, text=True, capture_output=True, timeout=180,
                                creationflags=getattr(subprocess,"CREATE_NO_WINDOW",0) if os.name=="nt" else 0)
    except (OSError, subprocess.TimeoutExpired):
        raise RepairError("Docker est indisponible ou la commande a dépassé le délai autorisé.") from None
    if result.returncode:
        # Docker/Compose diagnostics can include expanded environment values.
        raise RepairError(f"La commande Docker a échoué (code {result.returncode}).")
    return result.stdout


def installation_api(install_dir: Path) -> dict:
    ids = docker_run(["ps", "-aq", "--filter", "label=com.docker.compose.service=api"]).split()
    for container_id in ids:
        container = json.loads(docker_run(["inspect", container_id]))[0]
        labels = container.get("Config", {}).get("Labels", {}) or {}
        working_dir = labels.get("com.docker.compose.project.working_dir", "")
        if working_dir and Path(working_dir).resolve() == install_dir.resolve():
            return container
    raise RepairError("Le conteneur API de cette installation est introuvable. Vérifiez --install-dir.")


def compose_command(container: dict, install_dir: Path, override: Path) -> list[str]:
    labels = container["Config"]["Labels"]
    project = labels.get("com.docker.compose.project")
    config_files = labels.get("com.docker.compose.project.config_files", "").split(",")
    if not project or not all(config_files):
        raise RepairError("Les métadonnées Compose de l’installation sont incomplètes.")
    args = ["compose", "-p", project, "--project-directory", str(install_dir), "--env-file", str(install_dir / ".env")]
    for name in config_files:
        path = Path(name)
        if not path.is_absolute():
            path = install_dir / path
        # Compose records every override in the container labels. A previous
        # successful repair removed its temporary image pin; ignore only our
        # own reserved override so credential rotation remains repeatable.
        if path.parent.resolve() == install_dir.resolve() and re.fullmatch(r"\.update-access-compose-[0-9a-f]{32}\.yml", path.name):
            continue
        if not path.is_file():
            raise RepairError("Un fichier Compose de l’installation est introuvable.")
        args.extend(["-f", str(path)])
    args.extend(["-f", str(override), "up", "-d", "--no-deps", "--pull", "never", "--force-recreate", "api"])
    return args


def wait_for_api(install_dir: Path) -> None:
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        container = installation_api(install_dir)
        state = container.get("State", {})
        status = (state.get("Health") or {}).get("Status")
        if state.get("Running") and status == "healthy":
            return
        if not state.get("Running") or status == "unhealthy":
            raise RepairError("L’API ne redémarre pas correctement.")
        if state.get("Running") and status is None:
            # Legacy APIs without a Docker healthcheck still require a real
            # HTTP check. The Python stdlib is present in all shipped API images.
            try:
                docker_run(["exec", container["Id"], "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=5)"])
                return
            except RepairError:
                pass
        time.sleep(2)
    raise RepairError("La vérification de santé de l’API a expiré.")


def repair(install_dir: Path, username: str, token: str, *, check_only: bool = False) -> None:
    env_path = install_dir / ".env"
    if not env_path.is_file():
        raise RepairError("Le fichier .env de l’installation est introuvable.")
    values = read_env(env_path)
    validate_access(username, token, values.get("GITHUB_OWNER") or "jimmindev")
    if check_only:
        print("Jeton valide, en lecture seule, avec accès aux deux images GHCR.")
        return
    container = installation_api(install_dir)
    image = container.get("Image", "")
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", image):
        raise RepairError("L’image installée ne peut pas être conservée de manière fiable.")
    original = env_path.read_text(encoding="utf-8-sig")
    override = install_dir / (".update-access-compose-" + uuid.uuid4().hex + ".yml")
    try:
        private_write(override, 'services:\n  api:\n    image: "' + image + '"\n')
        args = compose_command(container, install_dir, override)
        private_write(env_path, update_text(original, username, token))
        try:
            docker_run(args)
            wait_for_api(install_dir)
        except RepairError:
            private_write(env_path, original)
            try:
                docker_run(args)
                wait_for_api(install_dir)
            except RepairError:
                raise RepairError("Le fichier .env précédent a été restauré, mais le redémarrage de l’API doit être vérifié.") from None
            raise RepairError("La réparation a échoué. La configuration précédente et son API ont été restaurées.") from None
    finally:
        override.unlink(missing_ok=True)
    print("Accès GHCR remplacé. API saine, version applicative conservée. Relancez la vérification des mises à jour.")


def main() -> int:
    parser = argparse.ArgumentParser(description="Remplacer l’accès GHCR sans changer la version de l’application.")
    parser.add_argument("--install-dir", type=Path, required=True)
    parser.add_argument("--username")
    parser.add_argument("--token-stdin", action="store_true", help="Lire le jeton depuis stdin, jamais depuis un argument.")
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    try:
        values = read_env(args.install_dir / ".env")
        username = args.username or values.get("UPDATE_CHECK_USER") or input("Utilisateur GitHub : ").strip()
        if args.token_stdin:
            import sys
            token = sys.stdin.readline().strip()
        else:
            token = getpass.getpass("Nouveau jeton GitHub classic (read:packages uniquement) : ").strip()
        repair(args.install_dir.resolve(), username, token, check_only=args.check_only)
        return 0
    except (RepairError, OSError, ValueError):
        # Only explicitly sanitized messages may reach stdout/stderr.
        import sys
        error = sys.exc_info()[1]
        print(str(error) if isinstance(error, RepairError) else "Impossible de lire ou d’écrire la configuration de l’installation.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
