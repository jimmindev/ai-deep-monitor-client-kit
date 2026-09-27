import importlib.util
from pathlib import Path
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
