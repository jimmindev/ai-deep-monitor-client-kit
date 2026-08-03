from __future__ import annotations

import argparse
import ctypes
import hashlib
import hmac
import importlib.util
import json
import os
import platform
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


AGENT_VERSION = "2.1.0"
MAX_COMMAND_BYTES = 4_000
MAX_OUTPUT_BYTES = 400_000
MAX_TIMEOUT_SECONDS = 20.0
MAX_JOB_AGE_SECONDS = 30
STALE_JOB_SECONDS = 300
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


class HostAgent:
    def __init__(self, base: Path):
        self.base = base.resolve()
        self.incoming = self.base / "incoming"
        self.processing = self.base / "processing"
        self.outgoing = self.base / "outgoing"
        self.lock_path = self.base / ".agent.lock"
        self.agent_id = secrets.token_hex(12)
        self.host_family = detect_host_family()
        self.seen_nonces: dict[str, float] = {}
        for directory in (self.base, self.incoming, self.processing, self.outgoing):
            directory.mkdir(parents=True, exist_ok=True)
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
            "last_seen": time.time(),
        }

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

    def verify_job(self, envelope: dict) -> dict:
        payload = envelope.get("payload")
        signature = str(envelope.get("signature") or "")
        if not isinstance(payload, dict) or not hmac.compare_digest(
            signature, sign(self.key, payload)
        ):
            raise ValueError("Signature de travail invalide.")
        issued_at = float(payload.get("issued_at") or 0)
        if abs(time.time() - issued_at) > MAX_JOB_AGE_SECONDS:
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
            if not jobs:
                time.sleep(0.05)
                continue
            for job in jobs[:5]:
                claimed = self.processing / job.name
                try:
                    os.replace(job, claimed)
                except FileNotFoundError:
                    continue
                self.process_job(claimed)


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
    args = parser.parse_args()
    signal.signal(signal.SIGINT, request_stop)
    if hasattr(signal, "SIGTERM"):
        signal.signal(signal.SIGTERM, request_stop)

    agent = HostAgent(Path(args.jobs_dir))
    try:
        agent.run()
    finally:
        agent.release_lock()


if __name__ == "__main__":
    main()
