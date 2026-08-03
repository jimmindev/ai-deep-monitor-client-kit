from __future__ import annotations

import argparse
import ctypes
import hashlib
import hmac
import importlib.util
import json
import os
import platform
import re
import secrets
import shutil
import signal
import socket
import subprocess
import tempfile
import threading
import time
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent.parent
SOURCE_POLICY_PATH = PROJECT_ROOT / "api" / "terminal_policy.py"
PACKAGED_POLICY_PATH = Path(__file__).resolve().parent / "terminal_policy.py"
DEFAULT_POLICY_PATH = (
    SOURCE_POLICY_PATH if SOURCE_POLICY_PATH.is_file() else PACKAGED_POLICY_PATH
)
POLICY_PATH = Path(
    os.getenv(
        "AI_DEEP_TERMINAL_POLICY_PATH",
        str(DEFAULT_POLICY_PATH),
    )
).resolve()
_POLICY_SPEC = importlib.util.spec_from_file_location("ai_deep_terminal_policy", POLICY_PATH)
if not _POLICY_SPEC or not _POLICY_SPEC.loader:
    raise RuntimeError("La politique de sécurité du terminal est introuvable.")
_POLICY_MODULE = importlib.util.module_from_spec(_POLICY_SPEC)
_POLICY_SPEC.loader.exec_module(_POLICY_MODULE)
POLICY_VERSION = _POLICY_MODULE.POLICY_VERSION
TerminalPolicyViolation = _POLICY_MODULE.TerminalPolicyViolation
validate_terminal_command = _POLICY_MODULE.validate_terminal_command


AGENT_VERSION = "3.0.0"
MAX_COMMAND_BYTES = 4_000
MAX_OUTPUT_BYTES = 400_000
MAX_TIMEOUT_SECONDS = 20.0
MAX_JOB_AGE_SECONDS = 30
STALE_JOB_SECONDS = 300
MAX_UPDATE_SECONDS = 1_800
VERSION_PATTERN = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
STOP = False


def canonical(payload: dict) -> bytes:
    return json.dumps(
        payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def sign(key: bytes, payload: dict) -> str:
    return hmac.new(key, canonical(payload), hashlib.sha256).hexdigest()


def write_atomic(path: Path, data: dict) -> None:
    temporary = path.with_name(f".{path.name}.{secrets.token_hex(4)}.tmp")
    temporary.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    os.replace(temporary, path)


def load_or_create_key(base: Path) -> bytes:
    key_path = base / ".agent-key"
    if key_path.exists():
        raw = key_path.read_text(encoding="ascii").strip()
        key = bytes.fromhex(raw)
        if len(key) < 32:
            raise RuntimeError("La clé de l'agent hôte est invalide.")
        return key

    key = secrets.token_bytes(48)
    descriptor = os.open(key_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o640)
    with os.fdopen(descriptor, "w", encoding="ascii") as handle:
        handle.write(key.hex())
    return key


def is_privileged() -> bool:
    if os.name == "nt":
        try:
            return bool(ctypes.windll.shell32.IsUserAnAdmin())
        except Exception:
            return False
    return hasattr(os, "geteuid") and os.geteuid() == 0


def detect_host_family() -> str:
    if os.name == "nt":
        return "windows"
    model = ""
    try:
        model = (Path("/proc/device-tree/model").read_bytes()).decode(
            "utf-8", errors="ignore"
        ).replace("\x00", " ").lower()
    except OSError:
        pass
    if Path("/etc/nv_tegra_release").is_file() or any(
        marker in model for marker in ("jetson", "nvidia")
    ):
        return "jetson"
    return "linux"


def platform_label(host_family: str) -> str:
    base = f"{platform.system()} {platform.release()}"
    if host_family == "jetson":
        return f"NVIDIA Jetson · {base}"
    return base


def available_shells() -> list[str]:
    if os.name == "nt":
        if shutil.which("pwsh") or shutil.which("powershell.exe"):
            return ["powershell"]
        return []
    shells = []
    if shutil.which("bash"):
        shells.append("bash")
    if shutil.which("sh"):
        shells.append("sh")
    return shells


def shell_argv(shell: str, command: str) -> list[str]:
    if os.name == "nt":
        if shell == "powershell":
            executable = shutil.which("pwsh") or shutil.which("powershell.exe")
            if not executable:
                raise ValueError("PowerShell n'est pas disponible sur cet hôte.")
            return [
                executable,
                "-NoLogo",
                "-NoProfile",
                "-NonInteractive",
                "-Command",
                command,
            ]
    elif shell == "bash" and shutil.which("bash"):
        return [shutil.which("bash"), "--noprofile", "--norc", "-c", command]
    elif shell == "sh" and shutil.which("sh"):
        return [shutil.which("sh"), "-c", command]
    raise ValueError("Shell demandé non disponible.")


def trusted_search_path() -> str:
    if os.name != "nt":
        return "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    system_root = Path(os.environ.get("SystemRoot", r"C:\Windows"))
    program_files = Path(os.environ.get("ProgramFiles", r"C:\Program Files"))
    candidates = [
        system_root / "System32",
        system_root,
        system_root / "System32" / "Wbem",
        system_root / "System32" / "WindowsPowerShell" / "v1.0",
        program_files / "Docker" / "Docker" / "resources" / "bin",
    ]
    return os.pathsep.join(str(path) for path in candidates if path.is_dir())


def trusted_powershell_module_path() -> str:
    if os.name != "nt":
        return ""
    system_root = Path(os.environ.get("SystemRoot", r"C:\Windows"))
    program_files = Path(os.environ.get("ProgramFiles", r"C:\Program Files"))
    candidates = [
        system_root / "System32" / "WindowsPowerShell" / "v1.0" / "Modules",
        program_files / "WindowsPowerShell" / "Modules",
        program_files / "PowerShell" / "7" / "Modules",
    ]
    return os.pathsep.join(str(path) for path in candidates if path.is_dir())


def child_environment() -> dict[str, str]:
    allowed = (
        "COMSPEC",
        "LANG",
        "LC_ALL",
        "PATHEXT",
        "PROGRAMDATA",
        "PROGRAMFILES",
        "PROGRAMFILES(X86)",
        "SYSTEMROOT",
        "TEMP",
        "TMP",
        "WINDIR",
    )
    environment = {
        key: value
        for key, value in os.environ.items()
        if key.upper() in allowed
    }
    workdir = str(safe_working_directory())
    environment["PATH"] = trusted_search_path()
    environment["HOME"] = workdir
    environment["USERPROFILE"] = workdir
    if os.name == "nt":
        environment["PSMODULEPATH"] = trusted_powershell_module_path()
    return environment


def safe_working_directory() -> Path:
    directory = Path(tempfile.gettempdir()) / "ai-deep-terminal"
    directory.mkdir(parents=True, exist_ok=True)
    return directory


def hardened_execution_command(command: str, host_family: str) -> str:
    words = command.strip().split()
    lowered = [item.lower() for item in words]
    if len(lowered) >= 2 and lowered[0] in {"docker", "docker.exe"} and lowered[1] == "ps":
        all_flag = " -a" if any(item in {"-a", "--all"} for item in lowered[2:]) else ""
        return (
            f'docker ps{all_flag} --format '
            '"table {{.ID}}\\t{{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}"'
        )
    if host_family in {"linux", "jetson"} and lowered in (["ps", "-ef"], ["ps", "aux"]):
        # Ne jamais exposer argv : un secret transmis à un processus hôte ou à
        # un conteneur pourrait sinon apparaître dans la colonne COMMAND.
        return "ps -eo pid=PID,ppid=PPID,user=USER,stat=STAT,comm=PROCESS --sort=comm"
    if host_family == "jetson" and command.strip().lower() == "jetson-info":
        return (
            "printf 'Modèle : '; tr -d '\\000' < /proc/device-tree/model; printf '\\n'; "
            "printf 'Version L4T : '; head -n 1 /etc/nv_tegra_release; "
            "printf 'Noyau : '; uname -r"
        )
    if host_family == "jetson" and command.strip().lower() == "jetson-stats":
        return (
            "command -v tegrastats >/dev/null || { "
            "echo 'tegrastats est indisponible sur cet hôte.' >&2; exit 127; }; "
            "tegrastats --interval 1000 & stats_pid=$!; sleep 3; "
            "kill \"$stats_pid\" 2>/dev/null; wait \"$stats_pid\" 2>/dev/null; exit 0"
        )
    return command


def terminate_process(process: subprocess.Popen) -> None:
    if process.poll() is not None:
        return
    if os.name == "nt":
        subprocess.run(
            ["taskkill", "/PID", str(process.pid), "/T", "/F"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
    else:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            process.kill()


def run_limited(
    shell: str,
    command: str,
    timeout: float,
    host_family: str | None = None,
) -> dict:
    command = validate_terminal_command(shell, command)
    effective_family = host_family or detect_host_family()
    if command.lower() in {"jetson-info", "jetson-stats"} and effective_family != "jetson":
        raise TerminalPolicyViolation(
            "jetson",
            "Cette commande est disponible uniquement sur un hôte NVIDIA Jetson.",
        )
    execution_command = hardened_execution_command(command, effective_family)
    creationflags = 0
    if os.name == "nt":
        creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0) | getattr(
            subprocess, "CREATE_NEW_PROCESS_GROUP", 0
        )
    process = subprocess.Popen(
        shell_argv(shell, execution_command),
        cwd=safe_working_directory(),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=child_environment(),
        creationflags=creationflags,
        start_new_session=os.name != "nt",
    )
    buckets = {"stdout": bytearray(), "stderr": bytearray()}
    state = {"total": 0, "limit_reached": False}
    lock = threading.Lock()

    def drain(name: str, stream) -> None:
        while True:
            chunk = stream.read(4096)
            if not chunk:
                return
            with lock:
                remaining = MAX_OUTPUT_BYTES - state["total"]
                if remaining > 0:
                    accepted = chunk[:remaining]
                    buckets[name].extend(accepted)
                    state["total"] += len(accepted)
                if len(chunk) > remaining or state["total"] >= MAX_OUTPUT_BYTES:
                    state["limit_reached"] = True
                    return

    readers = [
        threading.Thread(target=drain, args=("stdout", process.stdout), daemon=True),
        threading.Thread(target=drain, args=("stderr", process.stderr), daemon=True),
    ]
    for reader in readers:
        reader.start()

    deadline = time.monotonic() + timeout
    timed_out = False
    while process.poll() is None:
        if state["limit_reached"]:
            terminate_process(process)
            break
        if time.monotonic() >= deadline:
            timed_out = True
            terminate_process(process)
            break
        time.sleep(0.02)

    try:
        process.wait(timeout=1)
    except subprocess.TimeoutExpired:
        terminate_process(process)
    for reader in readers:
        reader.join(timeout=1)

    encoding = "utf-8"
    return {
        "ok": process.returncode == 0 and not timed_out and not state["limit_reached"],
        "stdout": bytes(buckets["stdout"]).decode(encoding, errors="replace"),
        "stderr": bytes(buckets["stderr"]).decode(encoding, errors="replace"),
        "exit_code": process.returncode,
        "timed_out": timed_out,
        "truncated": state["limit_reached"],
        "shell": shell,
    }


def read_env_value(path: Path, key: str) -> str:
    try:
        for line in path.read_text(encoding="utf-8-sig").splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#") or "=" not in stripped:
                continue
            name, value = stripped.split("=", 1)
            if name.strip() == key:
                return value.strip().strip('"').strip("'")
    except OSError:
        return ""
    return ""


def version_tuple(value: str) -> tuple[int, int, int] | None:
    match = VERSION_PATTERN.fullmatch(str(value or "").strip())
    return tuple(int(part) for part in match.groups()) if match else None


def write_env_value(path: Path, key: str, value: str) -> None:
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    replaced = False
    updated: list[str] = []
    for line in lines:
        if not line.lstrip().startswith("#") and "=" in line:
            name = line.split("=", 1)[0].strip()
            if name == key:
                updated.append(f"{key}={value}")
                replaced = True
                continue
        updated.append(line)
    if not replaced:
        updated.insert(0, f"{key}={value}")
    temporary = path.with_name(f".{path.name}.{secrets.token_hex(4)}.tmp")
    temporary.write_text("\n".join(updated) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def maintenance_environment() -> dict[str, str]:
    environment = dict(os.environ)
    environment["PATH"] = trusted_search_path()
    environment["PYTHONUNBUFFERED"] = "1"
    return environment


def run_maintenance_process(
    argv: list[str],
    *,
    cwd: Path,
    timeout: float = MAX_UPDATE_SECONDS,
) -> dict:
    creationflags = 0
    if os.name == "nt":
        creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0) | getattr(
            subprocess, "CREATE_NEW_PROCESS_GROUP", 0
        )
    process = subprocess.Popen(
        argv,
        cwd=str(cwd),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=maintenance_environment(),
        creationflags=creationflags,
        start_new_session=os.name != "nt",
    )
    try:
        stdout, stderr = process.communicate(timeout=timeout)
        timed_out = False
    except subprocess.TimeoutExpired:
        timed_out = True
        terminate_process(process)
        stdout, stderr = process.communicate()
    combined = (stdout or b"") + b"\n" + (stderr or b"")
    return {
        "ok": process.returncode == 0 and not timed_out,
        "exit_code": process.returncode,
        "timed_out": timed_out,
        # Never sent to the API or browser; useful only for local debugging.
        "output_tail": combined[-MAX_OUTPUT_BYTES:].decode("utf-8", errors="replace"),
    }


class HostAgent:
    def __init__(
        self,
        base: Path,
        *,
        install_dir: Path | None = None,
        state_dir: Path | None = None,
    ):
        self.base = base.resolve()
        self.incoming = self.base / "incoming"
        self.processing = self.base / "processing"
        self.outgoing = self.base / "outgoing"
        self.lock_path = self.base / ".agent.lock"
        self.updates = self.base / "updates"
        self.update_incoming = self.updates / "incoming"
        self.update_processing = self.updates / "processing"
        self.update_status = self.updates / "status"
        self.agent_id = secrets.token_hex(12)
        self.host_family = detect_host_family()
        self.install_dir = (install_dir or PROJECT_ROOT).resolve()
        self.state_dir = (
            state_dir or (self.install_dir / ".host-agent-state")
        ).resolve()
        self.update_thread: threading.Thread | None = None
        self.seen_nonces: dict[str, float] = {}
        for directory in (
            self.base,
            self.incoming,
            self.processing,
            self.outgoing,
            self.update_incoming,
            self.update_processing,
            self.update_status,
            self.state_dir,
        ):
            directory.mkdir(parents=True, exist_ok=True)
        if os.name != "nt":
            os.chmod(self.state_dir, 0o700)
        # If the host rebooted during maintenance, let the signed job resume.
        # Terminal jobs are short lived and keep their existing cleanup rules.
        for interrupted in self.update_processing.glob("*.json"):
            pending = self.update_incoming / interrupted.name
            if not pending.exists():
                os.replace(interrupted, pending)
            else:
                interrupted.unlink(missing_ok=True)
        self.key = load_or_create_key(self.base)
        self.shells = available_shells()
        if not self.shells:
            raise RuntimeError("Aucun shell compatible n'est disponible.")
        self.acquire_lock()

    def acquire_lock(self) -> None:
        try:
            descriptor = os.open(
                self.lock_path,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                0o640,
            )
        except FileExistsError as exc:
            status_path = self.base / "status.json"
            try:
                status_age = time.time() - status_path.stat().st_mtime
            except OSError:
                status_age = float("inf")
            if status_age <= 10:
                raise RuntimeError("Un agent terminal hôte est déjà actif.") from exc
            self.lock_path.unlink(missing_ok=True)
            descriptor = os.open(
                self.lock_path,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                0o640,
            )
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(json.dumps({"pid": os.getpid(), "agent_id": self.agent_id}))

    def release_lock(self) -> None:
        try:
            lock = json.loads(self.lock_path.read_text(encoding="utf-8"))
            if lock.get("agent_id") == self.agent_id:
                self.lock_path.unlink(missing_ok=True)
        except (OSError, ValueError, json.JSONDecodeError):
            pass

    def status_payload(self) -> dict:
        update = self.update_capability()
        return {
            "available": True,
            "target": "host",
            "agent_id": self.agent_id,
            "agent_version": AGENT_VERSION,
            "policy_version": POLICY_VERSION,
            "restricted": True,
            "hostname": socket.gethostname(),
            "host_family": self.host_family,
            "platform": platform_label(self.host_family),
            "shells": self.shells,
            "privileged": is_privileged(),
            "update_supported": update["supported"],
            "update_reason": update["reason"],
            "installed_version": update["current_version"],
            "update_running": bool(self.update_thread and self.update_thread.is_alive()),
            "last_seen": time.time(),
        }

    def update_capability(self) -> dict:
        env_path = self.install_dir / ".env"
        compose_path = self.install_dir / "docker-compose.release.yml"
        if os.name == "nt":
            update_script = self.install_dir / "update-client.ps1"
            backup_script = self.install_dir / "backup-client.ps1"
            marker = "SkipAgentInstall"
        else:
            update_script = self.install_dir / "update-client.sh"
            backup_script = self.install_dir / "backup-client.sh"
            marker = "skip-agent-install"
        required = (env_path, compose_path, update_script, backup_script)
        current = read_env_value(env_path, "APP_VERSION")
        if not all(path.is_file() for path in required):
            return {
                "supported": False,
                "reason": "Le kit client de maintenance est incomplet ou trop ancien.",
                "current_version": current,
            }
        try:
            script_content = update_script.read_text(encoding="utf-8-sig")
        except OSError:
            script_content = ""
        if marker not in script_content:
            return {
                "supported": False,
                "reason": "Mettez à jour le kit client pour activer les mises à jour intégrées.",
                "current_version": current,
            }
        if not shutil.which("docker", path=trusted_search_path()):
            return {
                "supported": False,
                "reason": "Docker n’est pas accessible depuis l’agent de maintenance.",
                "current_version": current,
            }
        owner = read_env_value(env_path, "GITHUB_OWNER") or "jimmindev"
        expected_owner = os.getenv("AI_DEEP_MONITOR_GITHUB_OWNER", "jimmindev")
        if owner.lower() != expected_owner.lower():
            return {
                "supported": False,
                "reason": "Le registre d’images configuré n’est pas autorisé.",
                "current_version": current,
            }
        if not version_tuple(current):
            return {
                "supported": False,
                "reason": "La version installée ne permet pas une mise à jour automatique sûre.",
                "current_version": current,
            }
        return {"supported": True, "reason": None, "current_version": current}

    def write_status(self) -> None:
        payload = self.status_payload()
        write_atomic(
            self.base / "status.json",
            {"payload": payload, "signature": sign(self.key, payload)},
        )

    def cleanup(self) -> None:
        cutoff = time.time() - STALE_JOB_SECONDS
        self.seen_nonces = {
            nonce: timestamp
            for nonce, timestamp in self.seen_nonces.items()
            if timestamp >= cutoff
        }
        for directory in (self.incoming, self.processing, self.outgoing):
            for path in directory.glob("*.json"):
                try:
                    if path.stat().st_mtime < cutoff:
                        path.unlink(missing_ok=True)
                except FileNotFoundError:
                    continue

        update_cutoff = time.time() - (30 * 24 * 60 * 60)
        for path in self.update_status.glob("*.json"):
            try:
                if path.stat().st_mtime < update_cutoff:
                    path.unlink(missing_ok=True)
            except FileNotFoundError:
                continue

    def verify_job(self, envelope: dict, *, max_age: float = MAX_JOB_AGE_SECONDS) -> dict:
        payload = envelope.get("payload")
        signature = str(envelope.get("signature") or "")
        if not isinstance(payload, dict) or not hmac.compare_digest(
            signature, sign(self.key, payload)
        ):
            raise ValueError("Signature de travail invalide.")
        issued_at = float(payload.get("issued_at") or 0)
        if abs(time.time() - issued_at) > max_age:
            raise ValueError("Travail expiré.")
        nonce = str(payload.get("nonce") or "")
        if not nonce or nonce in self.seen_nonces:
            raise ValueError("Travail déjà traité ou nonce invalide.")
        self.seen_nonces[nonce] = time.time()
        return payload

    def process_job(self, job_path: Path) -> None:
        job_id = job_path.stem
        started = time.monotonic()
        try:
            envelope = json.loads(job_path.read_text(encoding="utf-8"))
            payload = self.verify_job(envelope)
            if str(payload.get("id")) != job_id:
                raise ValueError("Identifiant de travail incohérent.")
            command = str(payload.get("command") or "")
            if not command.strip():
                raise ValueError("La commande est vide.")
            if len(command.encode("utf-8")) > MAX_COMMAND_BYTES:
                raise ValueError("La commande dépasse 4 Ko.")
            shell = str(payload.get("shell") or self.shells[0])
            if shell not in self.shells:
                raise ValueError("Shell demandé non disponible.")
            timeout = min(
                max(float(payload.get("timeout") or 10.0), 1.0),
                MAX_TIMEOUT_SECONDS,
            )
            response = run_limited(shell, command, timeout, self.host_family)
        except TerminalPolicyViolation as exc:
            response = {
                "ok": False,
                "error": str(exc),
                "error_code": "terminal_policy_denied",
                "policy_category": exc.category,
                "shell": str(payload.get("shell") or "") if "payload" in locals() else "",
            }
        except Exception as exc:
            response = {"ok": False, "error": str(exc)}
        finally:
            job_path.unlink(missing_ok=True)

        response.update(
            {
                "id": job_id,
                "agent_id": self.agent_id,
                "duration_ms": int((time.monotonic() - started) * 1000),
            }
        )
        write_atomic(
            self.outgoing / f"{job_id}.json",
            {"payload": response, "signature": sign(self.key, response)},
        )

    def write_update_status(
        self,
        context: dict,
        *,
        phase: str,
        progress: int,
        message: str,
        error_code: str | None = None,
        backup_created: bool | None = None,
        rollback_performed: bool | None = None,
    ) -> None:
        now = time.time()
        payload = {
            **context,
            "phase": phase,
            "progress": min(max(int(progress), 0), 100),
            "message": message[:500],
            "updated_at": now,
        }
        if error_code:
            payload["error_code"] = error_code
        if backup_created is not None:
            payload["backup_created"] = backup_created
        if rollback_performed is not None:
            payload["rollback_performed"] = rollback_performed
        if phase in {"completed", "failed", "rolled_back"}:
            payload["finished_at"] = now
        write_atomic(
            self.update_status / f"{context['id']}.json",
            {"payload": payload, "signature": sign(self.key, payload)},
        )

    def maintenance_commands(self) -> tuple[Path, Path, list[str], list[str]]:
        if os.name == "nt":
            powershell = shutil.which("pwsh") or shutil.which("powershell.exe")
            if not powershell:
                raise RuntimeError("PowerShell est indisponible sur l’hôte.")
            backup = self.install_dir / "backup-client.ps1"
            update = self.install_dir / "update-client.ps1"
            common = [
                powershell,
                "-NoLogo",
                "-NoProfile",
                "-NonInteractive",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
            ]
            return backup, update, common + [
                str(backup),
                "-InstallDir",
                str(self.install_dir),
            ], common + [str(update)]

        bash = shutil.which("bash")
        if not bash:
            raise RuntimeError("Bash est indisponible sur l’hôte.")
        backup = self.install_dir / "backup-client.sh"
        update = self.install_dir / "update-client.sh"
        return backup, update, [
            bash,
            str(backup),
            "--install-dir",
            str(self.install_dir),
        ], [bash, str(update)]

    def rollback_update(self, env_backup: Path) -> bool:
        env_path = self.install_dir / ".env"
        compose_path = self.install_dir / "docker-compose.release.yml"
        shutil.copy2(env_backup, env_path)
        docker = shutil.which("docker", path=trusted_search_path())
        if not docker:
            return False
        result = run_maintenance_process(
            [
                docker,
                "compose",
                "-f",
                str(compose_path),
                "--env-file",
                str(env_path),
                "up",
                "-d",
            ],
            cwd=self.install_dir,
            timeout=600,
        )
        return bool(result["ok"] and self.wait_for_api_health(300))

    def compose_command(self, *arguments: str, timeout: float = 600) -> dict:
        docker = shutil.which("docker", path=trusted_search_path())
        if not docker:
            return {"ok": False, "exit_code": 127, "timed_out": False}
        return run_maintenance_process(
            [
                docker,
                "compose",
                "-f",
                str(self.install_dir / "docker-compose.release.yml"),
                "--env-file",
                str(self.install_dir / ".env"),
                *arguments,
            ],
            cwd=self.install_dir,
            timeout=timeout,
        )

    def wait_for_api_health(self, timeout: float) -> bool:
        docker = shutil.which("docker", path=trusted_search_path())
        if not docker:
            return False
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                result = subprocess.run(
                    [
                        docker,
                        "inspect",
                        "--format",
                        "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}",
                        "ai-monitor-client-api",
                    ],
                    cwd=str(self.install_dir),
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    env=maintenance_environment(),
                    timeout=10,
                    check=False,
                    creationflags=(
                        getattr(subprocess, "CREATE_NO_WINDOW", 0)
                        if os.name == "nt"
                        else 0
                    ),
                )
                state = result.stdout.decode("utf-8", errors="replace").strip().lower()
                if result.returncode == 0 and state in {"healthy", "running"}:
                    return True
                if state in {"unhealthy", "exited", "dead"}:
                    return False
            except (OSError, subprocess.TimeoutExpired):
                pass
            time.sleep(2)
        return False

    def process_update_job(self, job_path: Path) -> None:
        job_id = job_path.stem
        env_backup: Path | None = None
        env_changed = False
        keep_env_backup = False
        context = {
            "id": job_id,
            "current_version": "",
            "target_version": "",
            "requested_by": "",
            "backup_created": False,
            "rollback_performed": False,
            "created_at": time.time(),
        }
        try:
            envelope = json.loads(job_path.read_text(encoding="utf-8"))
            payload = self.verify_job(
                envelope,
                max_age=MAX_UPDATE_SECONDS + 600,
            )
            if str(payload.get("id")) != job_id:
                raise ValueError("Identifiant de mise à jour incohérent.")
            if payload.get("action") != "application_update":
                raise ValueError("Action de maintenance non autorisée.")
            context.update(
                {
                    "current_version": str(payload.get("current_version") or ""),
                    "target_version": str(payload.get("target_version") or ""),
                    "requested_by": str(payload.get("requested_by") or "")[:100],
                    "created_at": float(payload.get("issued_at") or time.time()),
                }
            )
            self.write_update_status(
                context,
                phase="validating",
                progress=5,
                message="Validation de l’installation et de la version cible.",
            )
            capability = self.update_capability()
            if not capability["supported"]:
                raise RuntimeError(capability["reason"])
            current = capability["current_version"]
            target = context["target_version"]
            if not version_tuple(target) or not version_tuple(current):
                raise ValueError("Version de mise à jour invalide.")
            requested_current = context["current_version"]
            recovering = bool(
                current == target
                and version_tuple(requested_current)
                and version_tuple(requested_current) < version_tuple(target)
            )
            if not recovering:
                if version_tuple(target) <= version_tuple(current):
                    raise ValueError("Une rétrogradation ou réinstallation n’est pas autorisée.")
                if requested_current != current:
                    raise ValueError("La version installée a changé depuis la demande.")

            env_path = self.install_dir / ".env"
            rollback_dir = self.state_dir / "update-rollbacks"
            rollback_dir.mkdir(parents=True, exist_ok=True)
            if os.name != "nt":
                os.chmod(rollback_dir, 0o700)
            env_backup = rollback_dir / f"{job_id}.env"
            if recovering:
                if not env_backup.is_file():
                    raise RuntimeError(
                        "La maintenance interrompue ne peut pas être reprise sans son état privé."
                    )
                context["backup_created"] = True
            else:
                shutil.copy2(env_path, env_backup)
                if os.name != "nt":
                    os.chmod(env_backup, 0o600)

            backup_script, update_script, backup_argv, update_prefix = (
                self.maintenance_commands()
            )
            if not backup_script.is_file() or not update_script.is_file():
                raise RuntimeError("Scripts de maintenance introuvables.")
            if not recovering:
                self.write_update_status(
                    context,
                    phase="backing_up",
                    progress=15,
                    message="Création de la sauvegarde de sécurité.",
                )
                backup_result = run_maintenance_process(
                    backup_argv,
                    cwd=self.install_dir,
                    timeout=MAX_UPDATE_SECONDS,
                )
                if not backup_result["ok"]:
                    raise RuntimeError("La sauvegarde de sécurité a échoué.")
                context["backup_created"] = True

            self.write_update_status(
                context,
                phase="downloading",
                progress=45,
                message=f"Téléchargement et installation de {target}.",
                backup_created=True,
            )
            if not recovering:
                write_env_value(env_path, "APP_VERSION", target)
            env_changed = True
            config_result = self.compose_command("config", "--quiet", timeout=60)
            pull_result = (
                self.compose_command("pull", timeout=MAX_UPDATE_SECONDS)
                if config_result["ok"]
                else config_result
            )
            deployment_ok = bool(pull_result["ok"])
            if deployment_ok:
                self.write_update_status(
                    context,
                    phase="restarting",
                    progress=75,
                    message="Redémarrage des services avec la nouvelle version.",
                    backup_created=True,
                )
                deployment_ok = bool(
                    self.compose_command("up", "-d", timeout=900)["ok"]
                )
            if deployment_ok:
                self.write_update_status(
                    context,
                    phase="health_check",
                    progress=92,
                    message="Vérification du bon fonctionnement de la nouvelle version.",
                    backup_created=True,
                )
                deployment_ok = self.wait_for_api_health(300)

            if not deployment_ok:
                self.write_update_status(
                    context,
                    phase="rolling_back",
                    progress=90,
                    message="Échec détecté : restauration de la version précédente.",
                    error_code="update_failed",
                    backup_created=True,
                )
                rollback_ok = self.rollback_update(env_backup)
                context["rollback_performed"] = rollback_ok
                keep_env_backup = not rollback_ok
                self.write_update_status(
                    context,
                    phase="rolled_back" if rollback_ok else "failed",
                    progress=100,
                    message=(
                        "La mise à jour a échoué et la version précédente a été restaurée."
                        if rollback_ok
                        else "La mise à jour et la restauration ont échoué. Intervention requise."
                    ),
                    error_code="update_rolled_back" if rollback_ok else "rollback_failed",
                    backup_created=True,
                    rollback_performed=rollback_ok,
                )
                return

            self.write_update_status(
                context,
                phase="completed",
                progress=100,
                message=f"Mise à jour vers {target} terminée avec succès.",
                backup_created=True,
            )
        except Exception as exc:
            if env_changed and env_backup and context["backup_created"]:
                rollback_ok = self.rollback_update(env_backup)
                context["rollback_performed"] = rollback_ok
                keep_env_backup = not rollback_ok
                self.write_update_status(
                    context,
                    phase="rolled_back" if rollback_ok else "failed",
                    progress=100,
                    message=(
                        "Une erreur inattendue est survenue ; la version précédente a été restaurée."
                        if rollback_ok
                        else "Une erreur inattendue empêche la mise à jour et sa restauration automatique."
                    ),
                    error_code="update_rolled_back" if rollback_ok else "rollback_failed",
                    backup_created=True,
                    rollback_performed=rollback_ok,
                )
            else:
                self.write_update_status(
                    context,
                    phase="failed",
                    progress=100,
                    message=str(exc)[:500] or "La mise à jour a échoué.",
                    error_code="update_validation_failed",
                    backup_created=context["backup_created"],
                    rollback_performed=context["rollback_performed"],
                )
        finally:
            job_path.unlink(missing_ok=True)
            # A failed rollback is the one case where the private .env copy is
            # still required for manual recovery. It never enters the shared
            # Docker/API queue and remains protected by the agent state ACLs.
            if env_backup and not keep_env_backup:
                env_backup.unlink(missing_ok=True)

    def run(self) -> None:
        global STOP
        last_maintenance = 0.0
        while not STOP:
            now = time.monotonic()
            if now - last_maintenance >= 2:
                self.write_status()
                self.cleanup()
                last_maintenance = now
            jobs = sorted(
                self.incoming.glob("*.json"),
                key=lambda item: item.stat().st_mtime,
            )
            for job in jobs[:5]:
                claimed = self.processing / job.name
                try:
                    os.replace(job, claimed)
                except FileNotFoundError:
                    continue
                self.process_job(claimed)

            if not self.update_thread or not self.update_thread.is_alive():
                update_jobs = sorted(
                    self.update_incoming.glob("*.json"),
                    key=lambda item: item.stat().st_mtime,
                )
                if update_jobs:
                    job = update_jobs[0]
                    claimed = self.update_processing / job.name
                    try:
                        os.replace(job, claimed)
                    except FileNotFoundError:
                        continue
                    self.update_thread = threading.Thread(
                        target=self.process_update_job,
                        args=(claimed,),
                        name="ai-deep-update",
                        daemon=True,
                    )
                    self.update_thread.start()
            if not jobs:
                time.sleep(0.05)


def request_stop(*_args) -> None:
    global STOP
    STOP = True


def main() -> None:
    parser = argparse.ArgumentParser(description="Agent terminal local AI-Deep Monitor")
    parser.add_argument(
        "--jobs-dir",
        default=str(Path(__file__).resolve().parent.parent / "host_terminal_jobs"),
        help="Dossier de communication local partagé avec Docker.",
    )
    parser.add_argument(
        "--install-dir",
        default=str(PROJECT_ROOT),
        help="Dossier de l’installation AI-Deep Monitor à maintenir.",
    )
    parser.add_argument(
        "--state-dir",
        default="",
        help="Dossier privé utilisé pour les états de restauration.",
    )
    args = parser.parse_args()
    signal.signal(signal.SIGINT, request_stop)
    if hasattr(signal, "SIGTERM"):
        signal.signal(signal.SIGTERM, request_stop)

    agent = HostAgent(
        Path(args.jobs_dir),
        install_dir=Path(args.install_dir),
        state_dir=Path(args.state_dir) if args.state_dir else None,
    )
    try:
        agent.run()
    finally:
        agent.release_lock()


if __name__ == "__main__":
    main()
