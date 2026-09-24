"""Mount new data filesystems for backup without shell input or formatting."""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import time
try:
    from .locations import Locations
except ImportError:
    from locations import Locations
from pathlib import Path

MOUNT_ROOT = Path("/media/ai-deep-monitor")
BACKUP_FOLDER = "ai-deep-monitor-backups"
SUPPORTED = {"ext2", "ext3", "ext4", "btrfs", "xfs", "vfat", "exfat", "ntfs", "ntfs3"}
USER_MOUNT_OPTIONS = {"vfat", "exfat", "ntfs", "ntfs3"}
UUID_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9-]{3,63}\Z")
SYSTEM_MOUNTS = {"/", "/boot", "/boot/efi", "/boot/firmware", "/home", "/usr", "/var"}


def data_filesystems(snapshot: dict) -> list[dict]:
    """Exclude a whole disk when any of its partitions hosts Linux itself."""
    result = []

    def system_disk(device: dict) -> bool:
        mount = str(device.get("mountpoint") or "")
        return mount in SYSTEM_MOUNTS or any(system_disk(child) for child in device.get("children") or [])

    def walk(device: dict):
        kind = str(device.get("type") or "")
        filesystem = str(device.get("fstype") or "").lower()
        uuid = str(device.get("uuid") or "")
        if kind in {"part", "disk"} and filesystem in SUPPORTED and UUID_PATTERN.fullmatch(uuid):
            result.append({"uuid": uuid, "filesystem": filesystem,
                           "mountpoint": str(device.get("mountpoint") or "")})
        for child in device.get("children") or []:
            walk(child)

    for device in snapshot.get("blockdevices") or []:
        if device.get("type") == "disk" and not system_disk(device):
            walk(device)
    return result


def scan_once(root: Path = MOUNT_ROOT, uid: int = 1000, gid: int = 1000) -> list[str]:
    if root.is_symlink():
        raise ValueError("Racine de montage non sûre.")
    run = subprocess.run(
        ["lsblk", "--json", "--output", "TYPE,FSTYPE,UUID,TRAN,MOUNTPOINT"],
        capture_output=True, text=True, timeout=8, check=True,
    )
    mounted = []
    for disk in data_filesystems(json.loads(run.stdout)):
        target = root / disk["uuid"]
        if disk["mountpoint"] and disk["mountpoint"] != str(target):
            continue
        if target.is_symlink():
            continue
        target.mkdir(parents=True, exist_ok=True)
        try:
            if not os.path.ismount(target):
                options = "nosuid,nodev,noexec"
                if disk["filesystem"] in USER_MOUNT_OPTIONS:
                    options += f",uid={uid},gid={gid},umask=007"
                source = f"/dev/disk/by-uuid/{disk['uuid']}"
                subprocess.run(["mount", "-o", options, source, str(target)],
                               capture_output=True, text=True, timeout=20, check=True)
                mounted.append(str(target))
            # This service only mounts non-system data disks under its own
            # mount root. Make their top level writable without changing any
            # existing files or directories on the disk.
            if disk["filesystem"] not in USER_MOUNT_OPTIONS:
                os.chown(target, uid, gid)
                os.chmod(target, 0o770)
            backup = target / BACKUP_FOLDER
            backup.mkdir(exist_ok=True)
            os.chown(backup, uid, gid)
            os.chmod(backup, 0o770)
        except (OSError, subprocess.SubprocessError):
            # A failed mount must never make an empty host directory appear
            # to the application as a usable backup disk.
            continue
    return mounted


def ensure_shared_mount_roots() -> None:
    """Allow hotplug mounts to propagate to Docker's rslave binds."""
    for path in ("/mnt", "/media", "/run/media"):
        Path(path).mkdir(parents=True, exist_ok=True)
        source = subprocess.run(["findmnt", "--noheadings", "--output", "TARGET", "--target", path],
                                capture_output=True, text=True, timeout=5, check=True).stdout.strip()
        if source != path:
            subprocess.run(["mount", "--bind", path, path], check=True, timeout=10)
        subprocess.run(["mount", "--make-rshared", path], check=True, timeout=10)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--install-dir", type=Path)
    parser.add_argument("--uid", type=int, default=1000)
    parser.add_argument("--gid", type=int, default=1000)
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise SystemExit("Le montage USB exige le service hôte privilégié.")
    MOUNT_ROOT.mkdir(parents=True, exist_ok=True)
    if MOUNT_ROOT.is_symlink():
        raise SystemExit("Racine de montage non sûre.")
    ensure_shared_mount_roots()
    locations = None
    last_scan = 0
    while True:
        try:
            if time.monotonic() - last_scan > 5:
                scan_once(uid=args.uid, gid=args.gid)
                last_scan = time.monotonic()
                if locations is not None:
                    locations.restore()
            if args.install_dir:
                if locations is None:
                    locations = Locations(args.install_dir / "host_terminal_jobs", args.install_dir, args.uid, args.gid)
                locations.tick()
        except (OSError, ValueError, subprocess.SubprocessError):
            pass
        if args.once:
            break
        time.sleep(0.25)


if __name__ == "__main__":
    main()
