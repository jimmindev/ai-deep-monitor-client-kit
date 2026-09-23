import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "host_network_agent", Path(__file__).resolve().parents[1] / "host_terminal_agent/agent.py"
)
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)


class NetworkAdapterIdentityTest(unittest.TestCase):
    def test_device_tree_identifies_raspberry_wifi_chip(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            device = root / "wlan0" / "device"
            (device / "of_node").mkdir(parents=True)
            (device / "of_node" / "compatible").write_bytes(
                b"brcm,bcm43438-fmac\0brcm,bcm4329-fmac\0"
            )
            with patch.object(agent.subprocess, "run", side_effect=FileNotFoundError):
                identity = agent.linux_adapter_identity("wlan0", root)
            self.assertEqual(identity, {"description": "Broadcom BCM43438", "driver": ""})

    def test_missing_metadata_does_not_invent_model(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "eth0" / "device").mkdir(parents=True)
            with patch.object(agent.subprocess, "run", side_effect=FileNotFoundError):
                identity = agent.linux_adapter_identity("eth0", root)
            self.assertEqual(identity["description"], "")


if __name__ == "__main__":
    unittest.main()
