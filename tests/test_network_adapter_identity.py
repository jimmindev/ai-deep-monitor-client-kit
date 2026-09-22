import importlib.util
from pathlib import Path
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "host_network_agent", Path(__file__).resolve().parents[1] / "host_terminal_agent/agent.py"
)
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)


def test_linux_adapter_identity_uses_device_tree_when_udev_has_no_model(tmp_path):
    device = tmp_path / "wlan0" / "device"
    (device / "of_node").mkdir(parents=True)
    (device / "of_node" / "compatible").write_bytes(b"brcm,bcm43438-fmac\0brcm,bcm4329-fmac\0")
    with patch.object(agent.subprocess, "run", side_effect=FileNotFoundError):
        identity = agent.linux_adapter_identity("wlan0", tmp_path)
    assert identity["description"] == "Broadcom BCM43438"
    assert identity["driver"] == ""


def test_linux_adapter_identity_does_not_invent_a_model(tmp_path):
    (tmp_path / "eth0" / "device").mkdir(parents=True)
    with patch.object(agent.subprocess, "run", side_effect=FileNotFoundError):
        identity = agent.linux_adapter_identity("eth0", tmp_path)
    assert identity["description"] == ""
