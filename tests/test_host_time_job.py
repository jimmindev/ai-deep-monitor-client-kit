import importlib.util
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "host_time_agent", Path(__file__).resolve().parents[1] / "host_terminal_agent/agent.py"
)
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)


class HostTimeJobTest(unittest.TestCase):
    def test_signed_time_job_receives_signed_response(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            incoming = root / "incoming"
            outgoing = root / "outgoing"
            incoming.mkdir()
            outgoing.mkdir()
            worker = object.__new__(agent.HostAgent)
            worker.key = b"test-key" * 8
            worker.agent_id = "test-agent"
            worker.outgoing = outgoing
            worker.seen_nonces = {}
            job_id = "a" * 32
            payload = {
                "id": job_id,
                "issued_at": time.time(),
                "nonce": "unique-time-request",
                "operation": {
                    "kind": "configure_time",
                    "timezone": "Europe/Paris",
                    "ntp_server": "pool.ntp.org",
                },
            }
            job = incoming / f"{job_id}.json"
            job.write_text(json.dumps({"payload": payload, "signature": agent.sign(worker.key, payload)}))

            with patch.object(agent, "configure_host_time", return_value={"ok": True}):
                worker.process_job(job)

            response_envelope = json.loads((outgoing / f"{job_id}.json").read_text())
            response = response_envelope["payload"]
            self.assertTrue(response["ok"])
            self.assertEqual(response["id"], job_id)
            self.assertEqual(response["agent_id"], "test-agent")
            self.assertEqual(response_envelope["signature"], agent.sign(worker.key, response))
            self.assertFalse(job.exists())


if __name__ == "__main__":
    unittest.main()
