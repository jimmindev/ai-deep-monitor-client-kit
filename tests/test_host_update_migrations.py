import importlib.util
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch
import uuid

spec = importlib.util.spec_from_file_location("host_update_agent", Path(__file__).resolve().parents[1] / "host_terminal_agent/agent.py")
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)

class UpdateMigrationTest(unittest.TestCase):
    def scenario(self, migration_ok):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            install = root / "install"
            install.mkdir()
            (install / ".env").write_text("APP_VERSION=v0.1.24\n", encoding="utf-8")
            for name in ["backup-client.sh", "update-client.sh", "backup-client.ps1", "update-client.ps1"]:
                (install / name).write_text("# --skip-agent-install", encoding="utf-8")
            calls = []
            def run(argv, **kwargs):
                calls.append(argv)
                is_migration = argv[-4:] == ["api", "alembic", "upgrade", "head"]
                ok = migration_ok or not is_migration
                return {"ok": ok, "exit_code": 0 if ok else 1, "timed_out": False, "output_tail": "migration refused" if not ok else ""}
            with patch.object(agent.shutil, "which", side_effect=lambda name, **kw: "/test/" + name), patch.object(agent, "run_maintenance_process", side_effect=run):
                host = agent.HostAgent(root / "jobs", install_dir=install, state_dir=root / "state")
                try:
                    job_id = str(uuid.uuid4())
                    payload = {"id":job_id,"action":"application_update","issued_at":time.time(),"nonce":job_id,"current_version":"v0.1.24","target_version":"v0.1.25","requested_by":"test"}
                    job = host.update_processing / (job_id + ".json")
                    job.write_text(json.dumps({"payload":payload,"signature":agent.sign(host.key,payload)}), encoding="utf-8")
                    with patch.object(host, "update_capability", return_value={"supported":True,"current_version":"v0.1.24"}), patch.object(host, "wait_for_api_health", return_value=True), patch.object(host, "rollback_update", return_value=True):
                        host.process_update_job(job)
                    status = json.loads((host.update_status / (job_id + ".json")).read_text(encoding="utf-8"))["payload"]
                    migration_pos = next(i for i,c in enumerate(calls) if "alembic" in c)
                    self.assertTrue(any("pull" in c for c in calls[:migration_pos]))
                    starts = [i for i,c in enumerate(calls) if "up" in c]
                    if migration_ok:
                        self.assertEqual(status["phase"], "completed")
                        self.assertTrue(starts and starts[0] > migration_pos)
                    else:
                        self.assertEqual(status["failure_code"], "database_migration_failed")
                        self.assertEqual(status["phase"], "rolled_back")
                        self.assertEqual(starts, [])
                finally:
                    host.release_lock()
    def test_schema_preparation_precedes_api_restart(self):
        self.scenario(True)
    def test_failed_schema_preparation_prevents_candidate_restart(self):
        self.scenario(False)

    def test_migration_timeout_cleans_only_its_container(self):
        for cleanup_ok in [True, False]:
            with self.subTest(cleanup_ok=cleanup_ok), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                install = root / "install"
                install.mkdir()
                with patch.object(agent.shutil, "which", return_value="/test/docker"):
                    host = agent.HostAgent(root / "jobs", install_dir=install, state_dir=root / "state")
                    try:
                        with patch.object(host, "compose_command", return_value={"ok":False,"timed_out":True}) as compose, patch.object(agent, "run_maintenance_process", return_value={"ok":cleanup_ok}) as cleanup:
                            result = host.migrate_database("test-timeout")
                        self.assertEqual(compose.call_args.kwargs["timeout"], 6 * 60 * 60)
                        self.assertEqual(cleanup.call_args.args[0], ["/test/docker","rm","--force","ai-monitor-schema-test-timeout"])
                        self.assertEqual(result["migration_cleanup_failed"], not cleanup_ok)
                    finally:
                        host.release_lock()

if __name__ == "__main__":
    unittest.main()
