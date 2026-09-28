import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch


spec = importlib.util.spec_from_file_location(
    "host_storage_locations", Path(__file__).resolve().parents[1] / "host_storage_agent/locations.py"
)
locations = importlib.util.module_from_spec(spec)
spec.loader.exec_module(locations)


class NetworkMountTest(unittest.TestCase):
    def setUp(self):
        self.agent = locations.Locations.__new__(locations.Locations)
        self.agent.uid = self.agent.gid = 1000
        self.record = {"protocol": "SMB", "host": "192.168.1.97", "share": "SMB-Test"}
        self.target = Mock()
        self.target.is_symlink.return_value = False
        self.target.stat.return_value.st_uid = 1000

    def test_existing_matching_mount_can_be_owned_by_smb_user(self):
        with patch.object(locations, "NETWORK_MOUNTS") as root, patch.object(
            locations, "mount_details", return_value=("cifs", "//192.168.1.97/SMB-Test")
        ):
            root.__truediv__.return_value = self.target
            self.assertIs(self.agent.mount_network("share-id", self.record), self.target)
        self.target.stat.assert_not_called()

    def test_unmounted_target_must_still_belong_to_root(self):
        with patch.object(locations, "NETWORK_MOUNTS") as root, patch.object(
            locations, "mount_details", return_value=None
        ), patch.object(locations.socket, "create_connection") as connect:
            root.__truediv__.return_value = self.target
            with self.assertRaisesRegex(ValueError, "non sûr"):
                self.agent.mount_network("share-id", self.record)
            connect.assert_not_called()

    def test_nfs3_fallback_when_server_does_not_support_nfs4(self):
        self.target.stat.return_value.st_uid = 0
        record = {"protocol": "NFS", "host": "192.168.1.97", "share": "/srv/nfs-test"}
        unsupported = subprocess.CalledProcessError(32, "mount", stderr=b"mount.nfs: Protocol not supported")
        with patch.object(locations, "NETWORK_MOUNTS") as root, patch.object(
            locations, "mount_details", side_effect=[None, ("nfs", "192.168.1.97:/srv/nfs-test")]
        ), patch.object(locations.socket, "create_connection"), patch.object(
            locations.subprocess, "run", side_effect=[unsupported, Mock()]
        ) as run:
            root.__truediv__.return_value = self.target
            self.assertIs(self.agent.mount_network("share-id", record), self.target)
        self.assertIn("vers=4,", run.call_args_list[0].args[0][4])
        self.assertIn("vers=3,", run.call_args_list[1].args[0][4])

    def test_nfs_permission_failure_does_not_downgrade(self):
        self.target.stat.return_value.st_uid = 0
        record = {"protocol": "NFS", "host": "192.168.1.97", "share": "/srv/nfs-test"}
        denied = subprocess.CalledProcessError(32, "mount", stderr=b"mount.nfs: access denied by server")
        with patch.object(locations, "NETWORK_MOUNTS") as root, patch.object(
            locations, "mount_details", return_value=None
        ), patch.object(locations.socket, "create_connection"), patch.object(
            locations.subprocess, "run", side_effect=denied
        ) as run:
            root.__truediv__.return_value = self.target
            with self.assertRaises(subprocess.CalledProcessError):
                self.agent.mount_network("share-id", record)
            run.assert_called_once()

    def test_share_identifier_does_not_replace_signed_request_identifier(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(
            self.agent, "mount_network", return_value=Path(temporary)
        ), patch.object(self.agent, "probe_containers"):
            self.agent.records = {}
            self.agent.registry = Path(temporary) / "locations.json"
            result = self.agent.create_network({"protocol": "NFS", "host": "nas.example", "share": "/backups"})
        self.assertIn("location_id", result)
        self.assertNotIn("id", result)

    def test_service_grants_mount_cifs_required_capability(self):
        service = (Path(__file__).resolve().parents[1] / "host_storage_agent/install_linux_service.sh").read_text()
        for line in service.splitlines():
            if line.startswith(("CapabilityBoundingSet=", "AmbientCapabilities=")):
                self.assertIn("CAP_DAC_READ_SEARCH", line)


if __name__ == "__main__":
    unittest.main()


class NetworkRemovalTest(unittest.TestCase):
    def test_admin_can_forget_maintenance_share_without_deleting_archives(self):
        import json
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            identifier = "a"*24
            target = base / identifier
            target.mkdir()
            (target / "full.admb").write_bytes(b"keep")
            credentials = base / f"{identifier}.credentials"
            credentials.write_text("secret")
            worker = locations.Locations.__new__(locations.Locations)
            worker.jobs = base / "jobs"
            worker.key = b"k"*32
            worker.install = base / "install"
            worker.install.mkdir()
            configured = f"MAINTENANCE_BACKUP_PATH={target}/maintenance"
            (worker.install / ".env").write_text(configured)
            worker.records = {identifier: {"kind": "network", "protocol": "SMB", "host": "nas", "share": "demo"}}
            worker.registry = base / "locations.json"
            worker.registry.write_text(json.dumps(worker.records))
            with patch.object(locations, "NETWORK_MOUNTS", base), patch.object(locations, "STATE", base), patch.object(locations, "mount_details", return_value=("cifs", "//nas/demo")), patch.object(locations.subprocess, "run") as run:
                worker.remove_network({"location_id": identifier})
                self.assertEqual(run.call_args.args[0], ["umount", str(target)])
            self.assertEqual(worker.records, {})
            self.assertFalse(credentials.exists())
            self.assertEqual((target / "full.admb").read_bytes(), b"keep")
            self.assertEqual((worker.install / ".env").read_text(), configured)
