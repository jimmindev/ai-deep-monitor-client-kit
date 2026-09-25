"""Signed, narrowly scoped host-folder provisioning for backups."""
import hashlib
import hmac
import json
import os
import re
import secrets
import socket
import stat
import subprocess
import time
from pathlib import Path, PurePosixPath

DENIED = {"/etc", "/proc", "/sys", "/dev", "/usr", "/bin", "/sbin", "/lib", "/lib64", "/run", "/var", "/boot", "/root", "/opt"}
MOUNTS = Path("/mnt/ai-deep-monitor-locations")
NETWORK_MOUNTS = Path("/mnt/ai-deep-monitor-network")
STATE = Path("/var/lib/ai-deep-monitor-storage")
HOST_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9.-]{0,252}\Z")
SHARE_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9_. -]{0,127}\Z")


def sign(key, payload):
    raw = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    return hmac.new(key, raw, hashlib.sha256).hexdigest()


def checked_path(value, install):
    path = Path(str(value))
    if not path.is_absolute() or ".." in path.parts or any(part.startswith(".") for part in path.parts[1:]):
        raise ValueError("Choisissez un chemin absolu sans dossier caché ni '..'.")
    if any(path == Path(p) or path.is_relative_to(p) for p in DENIED):
        raise ValueError("Cet emplacement est réservé au système.")
    if (path == install or path.is_relative_to(install) or path == MOUNTS or path.is_relative_to(MOUNTS)
            or path == NETWORK_MOUNTS or path.is_relative_to(NETWORK_MOUNTS)):
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


def mount_details(path):
    for line in Path("/proc/self/mountinfo").read_text().splitlines():
        left, separator, right = line.partition(" - ")
        fields = left.split()
        if separator and len(fields) >= 5 and len(right.split()) >= 2:
            mounted = re.sub(r"\\([0-7]{3})", lambda match: chr(int(match.group(1), 8)), fields[4])
            if mounted == str(path):
                return right.split()[0], right.split()[1]
    return None


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
        if STATE.is_symlink() or MOUNTS.is_symlink() or NETWORK_MOUNTS.is_symlink():
            raise ValueError("État du stockage non sûr.")
        MOUNTS.mkdir(mode=0o755, exist_ok=True)
        NETWORK_MOUNTS.mkdir(mode=0o755, exist_ok=True)
        if MOUNTS.stat().st_uid != 0 or NETWORK_MOUNTS.stat().st_uid != 0 or STATE.stat().st_uid != 0:
            raise ValueError("Les répertoires de gestion doivent appartenir à root.")
        os.chmod(STATE, 0o700)
        os.chmod(MOUNTS, 0o755)
        os.chmod(NETWORK_MOUNTS, 0o755)
        self.registry = STATE / "locations.json"
        self.records = json.loads(self.registry.read_text()) if self.registry.exists() else {}
        self.restore()
        self.last_status = 0
        self.last_restore = time.monotonic()

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

    def restore(self, *, include_network=True):
        for identifier, record in self.records.items():
            try:
                if record.get("kind") == "network":
                    if include_network:
                        self.mount_network(identifier, record)
                    continue
                source = checked_path(record["host_path"], self.install)
                if source.is_dir() and filesystem_id(source) == record["filesystem"]:
                    self.bind(source, MOUNTS / identifier)
            except (OSError, ValueError, subprocess.SubprocessError):
                continue

    @staticmethod
    def network_fields(payload):
        protocol = str(payload.get("protocol") or "").upper()
        host = str(payload.get("host") or "").strip()
        share = str(payload.get("share") or "").strip()
        if protocol not in {"SMB", "NFS"} or not HOST_PATTERN.fullmatch(host):
            raise ValueError("Indiquez un protocole et un serveur réseau valides.")
        if protocol == "SMB":
            share = share.strip("/\\")
            if not SHARE_PATTERN.fullmatch(share):
                raise ValueError("Indiquez le nom du partage SMB, sans chemin de dossier.")
        elif not share.startswith("/") or ".." in Path(share).parts or any(c in share for c in "\x00\r\n, :\\"):
            raise ValueError("Indiquez un export NFS absolu valide.")
        return protocol, host, share

    def mount_network(self, identifier, record):
        target = NETWORK_MOUNTS / identifier
        if target.is_symlink():
            raise ValueError("Point de montage réseau non sûr.")
        target.mkdir(mode=0o755, exist_ok=True)
        if target.stat().st_uid != 0:
            raise ValueError("Point de montage réseau non sûr.")
        protocol, host, share = self.network_fields(record)
        expected = ("cifs", f"//{host}/{share}") if protocol == "SMB" else ("nfs4", f"{host}:{share}")
        current = mount_details(target)
        if current:
            if current[1] != expected[1] or (current[0] not in {"nfs", "nfs4"} if protocol == "NFS" else current[0] != "cifs"):
                raise ValueError("Un autre volume occupe ce point de montage.")
            return target
        with socket.create_connection((host, 445 if protocol == "SMB" else 2049), timeout=2):
            pass
        if protocol == "SMB":
            credentials = STATE / f"{identifier}.credentials"
            if not credentials.is_file() or credentials.is_symlink():
                raise ValueError("Identifiants SMB indisponibles.")
            options = (f"credentials={credentials},vers=3.0,uid={self.uid},gid={self.gid},"
                       "file_mode=0660,dir_mode=0770,nosuid,nodev,noexec")
            command = ["mount", "-t", "cifs", "-o", options, f"//{host}/{share}", str(target)]
        else:
            command = ["mount", "-t", "nfs", "-o", "vers=4,soft,timeo=100,retrans=2,nosuid,nodev,noexec",
                       f"{host}:{share}", str(target)]
        subprocess.run(command, check=True, capture_output=True, timeout=30)
        current = mount_details(target)
        if not current or current[1] != expected[1] or (current[0] not in {"nfs", "nfs4"} if protocol == "NFS" else current[0] != "cifs"):
            raise ValueError("Le partage réseau n’a pas été monté.")
        return target

    def create_network(self, payload):
        protocol, host, share = self.network_fields(payload)
        identifier = hashlib.sha256(f"{protocol}:{host.lower()}:{share}".encode()).hexdigest()[:24]
        existing = self.records.get(identifier)
        if existing and existing.get("kind") != "network":
            raise ValueError("Identifiant de partage déjà utilisé.")
        if protocol == "SMB":
            username = str(payload.get("username") or "")
            password = str(payload.get("password") or "")
            domain = str(payload.get("domain") or "")
            if (not username or not password or any("\n" in value or "\r" in value or "\x00" in value
                                                    for value in (username, password, domain))):
                raise ValueError("Indiquez un utilisateur et un mot de passe SMB valides.")
            credentials = STATE / f"{identifier}.credentials"
            contents = f"username={username}\npassword={password}\n" + (f"domain={domain}\n" if domain else "")
            if existing:
                if credentials.is_symlink() or not credentials.is_file() or credentials.read_text() != contents:
                    raise ValueError("Ce partage SMB est déjà configuré avec d’autres identifiants. Sélectionnez-le dans la liste.")
            else:
                fd = os.open(credentials, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
                with os.fdopen(fd, "w") as output:
                    output.write(contents)
        record = existing or {"kind": "network", "protocol": protocol, "host": host, "share": share}
        try:
            target = self.mount_network(identifier, record)
        except (OSError, ValueError, subprocess.SubprocessError):
            if not existing:
                (STATE / f"{identifier}.credentials").unlink(missing_ok=True)
            raise ValueError("Montage réseau impossible. Vérifiez le serveur, le partage, les droits et les utilitaires CIFS/NFS.") from None
        if not existing:
            self.records[identifier] = record
            temporary = self.registry.with_suffix(".tmp")
            temporary.write_text(json.dumps(self.records))
            os.chmod(temporary, 0o600)
            temporary.replace(self.registry)
        container_path = f"/host/mnt/ai-deep-monitor-network/{identifier}"
        try:
            self.probe_containers(container_path)
        except (OSError, ValueError, subprocess.SubprocessError) as exc:
            raise ValueError("Le partage est monté sur l’hôte, mais l’API ou le planificateur ne peut pas y écrire. Vérifiez la propagation Docker et les droits réseau, puis réessayez.") from exc
        return {"path": container_path, "protocol": protocol,
                "host": host, "share": share, "id": identifier, "host_path": str(target)}

    def probe_containers(self, container_path):
        compose = ["docker", "compose", "--project-directory", str(self.install),
                   "-f", str(self.install / "docker-compose.release.yml"),
                   "-f", str(self.install / "docker-compose.linux-host-storage.yml"),
                   "--env-file", str(self.install / ".env")]
        containers = subprocess.run(compose + ["ps", "-q", "api", "backup-scheduler"],
                                    check=True, capture_output=True, text=True, timeout=5).stdout.split()
        if len(containers) != 2:
            raise ValueError("L’API et le planificateur doivent être démarrés pour vérifier le partage.")
        probe = "import sys,tempfile; f=tempfile.TemporaryFile(dir=sys.argv[1]); f.write(b'check'); f.flush(); f.close()"
        for container in containers:
            subprocess.run(["docker", "exec", container, "python", "-c", probe, container_path],
                           check=True, capture_output=True, timeout=5)

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
        if payload.get("action") == "network_create":
            return self.create_network(payload)
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
        self.probe_containers(container_path)
        return {"host_path": str(source), "path": container_path}

    def publish_status(self):
        self.write(self.base / "status.json", {"last_seen": time.time(), "locations": self.records})
        self.last_status = time.monotonic()

    def tick(self):
        if time.monotonic() - self.last_restore > 60:
            self.restore()
            self.last_restore = time.monotonic()
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
                    if payload.get("action") in {"create", "delete", "network_create"}:
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
