"""Build the Client Kit archives on Windows or Linux without external zip tools."""

from __future__ import annotations

import hashlib
import io
import os
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGE_ROOT = "ai-deep-monitor-client-kit"
INCLUDED_DIRS = {"deploy", "docs", "host_terminal_agent", "host_storage_agent", "scripts"}
INCLUDED_FILES = {
    "AI-Deep-Monitor.cmd", "ai-deep-monitor.ps1", "ai-deep-monitor.sh",
    "CHANGELOG.md", "README.md",
}


def package_files() -> list[tuple[str, bytes, int]]:
    tracked = subprocess.check_output(("git", "ls-files", "-z"), cwd=ROOT).split(b"\0")
    result = []
    for raw_path in tracked:
        if not raw_path:
            continue
        relative = raw_path.decode("utf-8").replace("\\", "/")
        parts = Path(relative).parts
        if relative not in INCLUDED_FILES and parts[0] not in INCLUDED_DIRS:
            continue
        if relative.startswith("docs/release-notes/") or "__pycache__" in parts:
            continue
        if relative.endswith((".pyc", ".pyo")):
            continue
        data = (ROOT / relative).read_bytes()
        if relative.endswith((".sh", ".py")):
            data = data.replace(b"\r\n", b"\n")
        mode = 0o755 if relative.endswith(".sh") else 0o644
        result.append((relative, data, mode))
    return result


def build(output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    files = package_files()
    with tempfile.TemporaryDirectory(prefix="client-kit-package-", dir=output_dir) as scratch:
        scratch_path = Path(scratch)
        zip_path = scratch_path / f"{PACKAGE_ROOT}.zip"
        tar_path = scratch_path / f"{PACKAGE_ROOT}.tar.gz"
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as archive:
            for relative, data, mode in files:
                entry = zipfile.ZipInfo(f"{PACKAGE_ROOT}/{relative}")
                entry.external_attr = (0o100000 | mode) << 16
                entry.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(entry, data)
        with tarfile.open(tar_path, "w:gz") as archive:
            for relative, data, mode in files:
                entry = tarfile.TarInfo(f"{PACKAGE_ROOT}/{relative}")
                entry.size = len(data)
                entry.mode = mode
                archive.addfile(entry, io.BytesIO(data))
        checksum_path = scratch_path / f"{PACKAGE_ROOT}-SHA256.txt"
        checksum_path.write_text(
            "".join(
                f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n"
                for path in (zip_path, tar_path)
            ),
            encoding="utf-8",
        )
        for path in (zip_path, tar_path, checksum_path):
            os.replace(path, output_dir / path.name)
    print(f"Client Kit construit dans {output_dir}")


if __name__ == "__main__":
    build(Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "artifacts")
