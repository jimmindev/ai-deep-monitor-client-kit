"""Signed, narrowly scoped host-folder provisioning for backups."""
import hashlib
import hmac
import json
import os
import re
import secrets
import stat
import subprocess
import time
from pathlib import Path, PurePosixPath

DENIED = {"/etc", "/proc", "/sys", "/dev", "/usr", "/bin", "/sbin", "/lib", "/lib64", "/run", "/var", "/boot", "/root", "/opt"}
MOUNTS = Path("/mnt/ai-deep-monitor-locations")
STATE = Path("/var/lib/ai-deep-monitor-storage")


def sign(key, payload):
    raw = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    return hmac.new(key, raw, hashlib.sha256).hexdigest()


def checked_path(value, install):
    path = Path(str(value))
    if not path.is_absolute() or ".." in path.parts or any(part.startswith(".") for part in path.parts[1:]):
        raise ValueError("Choisissez un chemin absolu sans dossier caché ni '..'.")
    if any(path == Path(p) or path.is_relative_to(p) for p in DENIED):
        raise ValueError("Cet emplacement est réservé au système.")
    if path == install or path.is_relative_to(install) or path == MOUNTS or path.is_relative_to(MOUNTS):
        raise ValueError("Le dossier d’installation et les partages internes sont réservés.")
    if any(part.is_symlink() for part in [path, *path.parents]):
        raise ValueError("Choisissez un dossier réel, pas un lien symbolique.")
    return path


def is_mount(path):
    # os.path.ismount cannot detect bind mounts on the same filesystem.
    for line in Path("/proc/self/mountinfo").read_text().splitlines():
        fields = line.split(" - ", 1)[0].split()
        if len(fields) >= 5:
            mounted = re.sub(r"\\([0-7]{3})", lambda match: chr(int(match.group(1), 8)), fields[4])
            if mounted == str(path):
                return True
    return False


def open_directory(path):
    """Pin every component without following links during privileged operations."""
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in Path(path).parts[1:]:
            next_fd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = next_fd
        return fd
    except BaseException:
        os.close(fd)
        raise


def filesystem_id(path):
    return subprocess.run(["findmnt", "-n", "-o", "UUID", "--target", str(path)], check=True,
                          capture_output=True, text=True, timeout=5).stdout.strip()


class Locations:
    def __init__(self, jobs, install, uid=1000, gid=1000):
        self.jobs, self.install, self.uid, self.gid = jobs, install.resolve(), uid, gid
        self.base = jobs / "storage"
        self.key = bytes.fromhex((jobs / ".agent-key").read_text().strip())
        if len(self.key) < 32:
            raise ValueError("Clé hôte indisponible.")
        for directory in [self.base, self.base / "incoming", self.base / "outgoing"]:
            if directory.is_symlink():
                raise ValueError("File de stockage non sûre.")
            directory.mkdir(exist_ok=True)
            os.chown(directory, 0, gid)
            os.chmod(directory, 0o2770)
        STATE.mkdir(mode=0o700, exist_ok=True)
        if STATE.is_symlink() or MOUNTS.is_symlink():
            raise ValueError("État du stockage non sûr.")
        MOUNTS.mkdir(mode=0o755, exist_ok=True)
        if MOUNTS.stat().st_uid != 0 or STATE.stat().st_uid != 0:
            raise ValueError("Les répertoires de gestion doivent appartenir à root.")
        os.chmod(STATE, 0o700)
        os.chmod(MOUNTS, 0o755)
        self.registry = STATE / "locations.json"
        self.records = json.loads(self.registry.read_text()) if self.registry.exists() else {}
        self.restore()
        self.last_status = 0

    def write(self, path, payload):
        directory = open_directory(path.parent)
        temporary = f".{secrets.token_hex(16)}.tmp"
        try:
            fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                         0o600, dir_fd=directory)
            with os.fdopen(fd, "w") as output:
                json.dump({"payload": payload, "signature": sign(self.key, payload)}, output, ensure_ascii=False)
                os.fchown(output.fileno(), 0, self.gid)
                os.fchmod(output.fileno(), 0o640)
            os.replace(temporary, path.name, src_dir_fd=directory, dst_dir_fd=directory)
        finally:
            os.close(directory)

    def bind(self, source, target):
        if target.is_symlink():
            raise ValueError("Partage non sûr.")
        target.mkdir(mode=0o755, exist_ok=True)
        if not is_mount(target):
            if target.stat().st_uid != 0:
                raise ValueError("Le point de partage doit appartenir à root.")
            fd = open_directory(source)
            try:
                subprocess.run(["mount", "--bind", f"/proc/self/fd/{fd}", str(target)],
                               pass_fds=(fd,), check=True, capture_output=True, timeout=10)
            finally:
                os.close(fd)

    def restore(self):
        for identifier, record in self.records.items():
            try:
                source = checked_path(record["host_path"], self.install)
                if source.is_dir() and filesystem_id(source) == record["filesystem"]:
                    self.bind(source, MOUNTS / identifier)
            except (OSError, ValueError, subprocess.SubprocessError):
                continue

    def remove(self, source, files):
        """Remove only registered archives from one managed folder, then its bind."""
        identifier = hashlib.sha256(str(source).encode()).hexdigest()[:24]
        record = self.records.get(identifier)
        if not record or record.get("host_path") != str(source):
            raise ValueError("Cet emplacement n’est pas géré par l’application.")
        if any(Path(other.get("host_path", "")).is_relative_to(source) for key, other in self.records.items() if key != identifier):
            raise ValueError("Supprimez d’abord les emplacements de sauvegarde créés dans ce dossier.")
        if filesystem_id(source) != record["filesystem"]:
            raise ValueError("Le support d’origine n’est plus accessible.")
        if not isinstance(files, list) or len(files) > 5000:
            raise ValueError("Liste des archives invalide.")
        allowed = set()
        for raw in files:
            if not isinstance(raw, str) or not raw or len(raw) > 2048:
                raise ValueError("Chemin d’archive invalide.")
            relative = PurePosixPath(raw)
            if relative.is_absolute() or "\\" in raw or any(part in (".", "..") or part.startswith(".") for part in relative.parts):
                raise ValueError("Chemin d’archive invalide.")
            if relative.suffix.lower() not in {".admb", ".aibak", ".zip", ".json"}:
                raise ValueError("Format d’archive non reconnu.")
            allowed.add(relative.as_posix())
        found = set()
        directories = []
        def inspect(directory):
            for child in directory.iterdir():
                mode = child.lstat().st_mode
                if stat.S_ISLNK(mode) or is_mount(child):
                    raise ValueError("Un lien ou un montage empêche la suppression de cet emplacement.")
                if stat.S_ISDIR(mode):
                    inspect(child)
                    directories.append(child)
                elif stat.S_ISREG(mode):
                    relative = child.relative_to(source).as_posix()
                    if relative not in allowed:
                        raise ValueError("Ce dossier contient une archive non répertoriée ou un fichier étranger. Déplacez-le avant de supprimer l’emplacement.")
                    found.add(relative)
                else:
                    raise ValueError("Ce dossier contient un élément spécial qui empêche sa suppression.")
        inspect(source)
        for relative in sorted(found):
            target = source / relative
            if not target.is_file() or target.is_symlink():
                raise ValueError("L’archive a changé pendant la suppression.")
            target.unlink()
        for directory in directories:
            directory.rmdir()
        target = MOUNTS / identifier
        if is_mount(target):
            subprocess.run(["umount", str(target)], check=True, capture_output=True, timeout=10)
        source.rmdir()
        if target.exists():
            target.rmdir()
        del self.records[identifier]
        temp = self.registry.with_suffix(".tmp")
        temp.write_text(json.dumps(self.records))
        temp.replace(self.registry)
        return {"host_path": str(source), "removed_archives": len(found)}

    def execute(self, payload):
        parent = checked_path(payload.get("path", "/"), self.install)
        if not parent.is_dir():
            raise ValueError("Le dossier parent n’existe pas ou le disque est débranché.")
        if payload.get("action") == "delete":
            return self.remove(parent, payload.get("files"))
        if payload.get("action") == "browse":
            folders = []
            for child in sorted(parent.iterdir()):
                try:
                    if checked_path(str(child), self.install).is_dir():
                        folders.append(child.name)
                except ValueError:
                    continue
                if len(folders) >= 300:
                    break
            return {"path": str(parent), "folders": folders}
        if payload.get("action") != "create":
            raise ValueError("Action de stockage inconnue.")
        name = str(payload.get("name", "")).strip()
        if not name or len(name) > 128 or name.startswith(".") or any(c in name for c in "/\\\x00\r\n"):
            raise ValueError("Donnez un nom simple au nouveau dossier, sans slash.")
        source = checked_path(str(parent / name), self.install)
        identifier = hashlib.sha256(str(source).encode()).hexdigest()[:24]
        if identifier not in self.records:
            fs = filesystem_id(parent)
            if not fs:
                raise ValueError("Ce système de fichiers ne permet pas un partage persistant. Choisissez un disque local.")
            fd = open_directory(parent)
            try:
                os.mkdir(name, mode=0o770, dir_fd=fd)
                child_fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
                try:
                    os.fchown(child_fd, self.uid, self.gid)
                    os.fchmod(child_fd, 0o770)
                finally:
                    os.close(child_fd)
            finally:
                os.close(fd)
            self.records[identifier] = {"host_path": str(source), "filesystem": fs}
            temp = self.registry.with_suffix(".tmp")
            temp.write_text(json.dumps(self.records))
            temp.replace(self.registry)
        if not source.is_dir() or filesystem_id(source) != self.records[identifier]["filesystem"]:
            raise ValueError("Le support d’origine n’est plus accessible.")
        self.bind(source, MOUNTS / identifier)
        container_path = f"/host/mnt/ai-deep-monitor-locations/{identifier}"
        compose = ["docker", "compose", "--project-directory", str(self.install),
                   "-f", str(self.install / "docker-compose.release.yml"),
                   "-f", str(self.install / "docker-compose.linux-host-storage.yml"),
                   "--env-file", str(self.install / ".env")]
        containers = subprocess.run(compose + ["ps", "-q", "api", "backup-scheduler"],
                                    check=True, capture_output=True, text=True, timeout=5).stdout.split()
        if len(containers) != 2:
            raise ValueError("Dossier créé et partagé, mais l’API et le planificateur doivent être démarrés. Réessayez ensuite avec le même nom.")
        probe = "import sys,tempfile; f=tempfile.TemporaryFile(dir=sys.argv[1]); f.write(b'check'); f.close()"
        for container in containers:
            subprocess.run(["docker", "exec", container, "python", "-c", probe, container_path],
                           check=True, capture_output=True, timeout=5)
        return {"host_path": str(source), "path": container_path}

    def publish_status(self):
        self.write(self.base / "status.json", {"last_seen": time.time(), "locations": self.records})
        self.last_status = time.monotonic()

    def tick(self):
        if time.monotonic() - self.last_status > 2:
            self.publish_status()
        for request in (self.base / "incoming").glob("*.json"):
            if not re.fullmatch(r"[a-f0-9]{32}\.json", request.name) or request.is_symlink():
                continue
            try:
                directory = open_directory(request.parent)
                try:
                    fd = os.open(request.name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=directory)
                    with os.fdopen(fd) as input_file:
                        envelope = json.loads(input_file.read(12_000_001))
                    os.unlink(request.name, dir_fd=directory)
                finally:
                    os.close(directory)
                payload = envelope["payload"]
                if not hmac.compare_digest(envelope.get("signature", ""), sign(self.key, payload)):
                    continue
                if payload.get("id") != request.stem or abs(time.time() - payload.get("created_at", 0)) > 30:
                    continue
                # The response itself is a replay marker for this signed request.
                response = self.base / "outgoing" / request.name
                if response.exists():
                    continue
                try:
                    result = {"id": request.stem, "ok": True, **self.execute(payload)}
                    if payload.get("action") in {"create", "delete"}:
                        self.publish_status()
                except (OSError, ValueError, subprocess.SubprocessError) as error:
                    result = {"id": request.stem, "ok": False, "error": "Ce dossier existe déjà. Choisissez un nouveau nom." if isinstance(error, FileExistsError) else str(error)}
                self.write(response, result)
            except (OSError, ValueError, KeyError, TypeError):
                continue
        for response in (self.base / "outgoing").glob("*.json"):
            directory = open_directory(response.parent)
            try:
                if time.time() - os.stat(response.name, dir_fd=directory, follow_symlinks=False).st_mtime > 300:
                    os.unlink(response.name, dir_fd=directory)
            finally:
                os.close(directory)
