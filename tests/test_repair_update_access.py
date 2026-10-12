import importlib.util
import io
import json
from pathlib import Path
import urllib.error
import unittest
from unittest.mock import patch
import tempfile

MODULE_PATH = Path(__file__).resolve().parents[1] / "scripts" / "repair_update_access.py"
spec = importlib.util.spec_from_file_location("repair_update_access", MODULE_PATH)
repair = importlib.util.module_from_spec(spec)
spec.loader.exec_module(repair)


class AccessRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        self.env = self.root / ".env"
        self.compose = self.root / "docker-compose.release.yml"
        self.compose.write_text("services: {}\n")
        self.override = self.root / "docker-compose.linux-host-storage.yml"
        self.override.write_text("services: {}\n")
        self.image = "sha256:" + "a" * 64
        self.container = {
            "Id": "api-container-id",
            "Image": self.image,
            "Config": {"Labels": {
                "com.docker.compose.project": "existing-client",
                "com.docker.compose.project.working_dir": str(self.root),
                "com.docker.compose.project.config_files": str(self.compose) + "," + str(self.override),
            }},
        }
        self.token = "ghp_new_fake_readonly_token"

    def write_env(self, version="v0.1.77"):
        original = f"APP_VERSION={version}\nMYSQL_PASSWORD=unchanged\nUPDATE_CHECK_USER=reader\nUPDATE_CHECK_TOKEN=old_fake\nCUSTOM_FEATURE=yes\n"
        self.env.write_text(original)
        return original

    def test_old_versions_keep_image_data_project_and_overrides(self):
        for version in ("v0.1.13", "v0.1.56", "v0.1.77", "v0.1.78"):
            with self.subTest(version=version):
                self.write_env(version)
                commands = []

                def fake_docker(args, **kwargs):
                    commands.append(args)
                    pin = Path(args[args.index("up") - 1])
                    self.assertIn(self.image, pin.read_text())
                    return ""

                with patch.object(repair, "validate_access"), patch.object(repair, "installation_api", return_value=self.container), patch.object(repair, "wait_for_api"), patch.object(repair, "docker_run", side_effect=fake_docker), patch("sys.stdout", new_callable=io.StringIO):
                    repair.repair(self.root, "reader", self.token)
                current = repair.read_env(self.env)
                self.assertEqual(current["APP_VERSION"], version)
                self.assertEqual(current["MYSQL_PASSWORD"], "unchanged")
                self.assertEqual(current["CUSTOM_FEATURE"], "yes")
                self.assertEqual(current["UPDATE_CHECK_TOKEN"], self.token)
                self.assertEqual(len(commands), 1)
                self.assertIn("existing-client", commands[0])
                self.assertIn(str(self.override), commands[0])
                self.assertEqual(commands[0][-7:], ["up", "-d", "--no-deps", "--pull", "never", "--force-recreate", "api"])
                self.assertNotIn(self.token, " ".join(commands[0]))
                self.assertFalse(list(self.root.glob(".update-access-*")))

    def test_rejected_token_does_not_change_env_or_start_docker(self):
        original = self.write_env()
        with patch.object(repair, "validate_access", side_effect=repair.RepairError("Access denied")), patch.object(repair, "docker_run") as docker:
            with self.assertRaises(repair.RepairError):
                repair.repair(self.root, "reader", self.token)
        self.assertEqual(self.env.read_text(), original)
        docker.assert_not_called()

    def test_failed_restart_restores_previous_configuration(self):
        original = self.write_env()
        with patch.object(repair, "validate_access"), patch.object(repair, "installation_api", return_value=self.container), patch.object(repair, "wait_for_api"), patch.object(repair, "docker_run", side_effect=[repair.RepairError("restart failed"), ""]) as docker:
            with self.assertRaisesRegex(repair.RepairError, "restaurées"):
                repair.repair(self.root, "reader", self.token)
        self.assertEqual(self.env.read_text(), original)
        self.assertEqual(docker.call_count, 2)
        self.assertFalse(list(self.root.glob(".update-access-*")))

    def test_check_only_leaves_installation_unchanged(self):
        original = self.write_env()
        with patch.object(repair, "validate_access"), patch.object(repair, "docker_run") as docker, patch("sys.stdout", new_callable=io.StringIO):
            repair.repair(self.root, "reader", self.token, check_only=True)
        self.assertEqual(self.env.read_text(), original)
        docker.assert_not_called()

    def test_repeat_repair_ignores_only_its_previous_temporary_override(self):
        stale = self.root / (".update-access-compose-" + "b" * 32 + ".yml")
        self.container["Config"]["Labels"]["com.docker.compose.project.config_files"] += "," + str(stale)
        args = repair.compose_command(self.container, self.root, self.root / "new.yml")
        self.assertNotIn(str(stale), args)
        self.assertIn(str(self.compose), args)
        self.assertIn(str(self.override), args)

    def test_extra_token_permissions_are_rejected(self):
        for scope in ("read:packages, write:packages", "repo, read:packages", ""):
            with self.subTest(scope=scope), patch.object(repair, "request_json", return_value=({"login": "reader"}, {"X-OAuth-Scopes": scope})):
                with self.assertRaisesRegex(repair.RepairError, "uniquement"):
                    repair.validate_access("reader", self.token, "example")

    def test_both_images_must_be_readable(self):
        calls = []

        def response(url, headers):
            calls.append((url, headers))
            if url.endswith("/user"):
                return {"login": "reader"}, {"X-OAuth-Scopes": "read:packages"}
            if "ghcr.io/token" in url:
                return {"token": "fake_bearer"}, {}
            return {"tags": ["v0.1.78"]}, {}

        with patch.object(repair, "request_json", side_effect=response):
            repair.validate_access("reader", self.token, "example")
        self.assertEqual(len(calls), 5)
        self.assertTrue(any("ai-deep-monitor-api/tags/list" in url for url, _ in calls))
        self.assertTrue(any("ai-deep-monitor-frontend/tags/list" in url for url, _ in calls))

    def test_http_errors_do_not_expose_tokens_or_remote_response(self):
        error = urllib.error.HTTPError("https://ghcr.io/?token=" + self.token, 403, self.token, {}, io.BytesIO(self.token.encode()))
        with patch.object(repair.urllib.request, "urlopen", side_effect=error):
            with self.assertRaises(repair.RepairError) as result:
                repair.request_json("https://ghcr.io/token", {})
        self.assertNotIn(self.token, str(result.exception))

    def test_duplicate_credentials_are_replaced_once(self):
        updated = repair.update_text("APP_VERSION=v0.1.56\nUPDATE_CHECK_TOKEN=old\nUPDATE_CHECK_TOKEN=older\n", "reader", self.token)
        self.assertEqual(updated.count("UPDATE_CHECK_TOKEN="), 1)
        self.assertIn("APP_VERSION=v0.1.56\n", updated)


if __name__ == "__main__":
    unittest.main()
