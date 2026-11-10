"""Exercise the helper against a stub gateway and a stub busctl.

Nothing here talks to a real Capsem service or raises a real notification.
"""
import http.server
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
import unittest

HELPER = Path(os.environ.get("CAPSEM_OMARCHY_TEST_HELPER", Path(__file__).resolve().parents[1] / "bin/capsem-omarchy"))

BUSCTL = """#!/usr/bin/env python3
import json, os, sys
with open(os.environ["FAKE_CALLS"], "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
"""

VM = "9b810b1a-f4b7-45a0-9aa7-6036a4881fe4"


class Gateway(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _reply(self):
        world = self.server.world
        world["requests"].append((self.command, self.path))
        if self.headers.get("Authorization") != "Bearer test-token":
            self.send_response(401)
            self.end_headers()
            return
        body = world["routes"].get(self.path, {})
        raw = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    do_GET = do_POST = do_DELETE = _reply


def vm(**over):
    base = {"id": VM, "name": "vm-1", "status": "Running", "pending_approval_count": 0,
            "allowed_requests": 4, "denied_requests": 0}
    base.update(over)
    return base


class HelperTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.world = {"requests": [], "routes": {}}
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Gateway)
        self.server.world = self.world
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

        run = root / "run"
        run.mkdir()
        (run / "gateway.port").write_text(str(self.server.server_address[1]))
        (run / "gateway.token").write_text("test-token")
        stubs = root / "bin"
        stubs.mkdir()
        # Every program the helper may start is stubbed, so a test can never
        # reach the real desktop.
        for name in ("busctl", "omarchy-shell", "systemctl", "uwsm-app", "xdg-terminal-exec"):
            (stubs / name).write_text(BUSCTL)
            (stubs / name).chmod(0o755)
        self.calls = root / "calls"
        self.calls.write_text("")
        self.env = {
            "PATH": f"{stubs}:/usr/bin:/bin",
            "HOME": str(root),
            "CAPSEM_RUN_DIR": str(run),
            "XDG_STATE_HOME": str(root / "state"),
            "FAKE_CALLS": str(self.calls),
        }

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.tmp.cleanup()

    def run_helper(self, *args):
        out = subprocess.run([str(HELPER), *args], env=self.env, capture_output=True, text=True, timeout=20)
        return out

    def notifications(self):
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        return [c for c in calls if "Notify" in c]

    def set_status(self, *vms):
        self.world["routes"]["/status"] = {"service": "running", "gateway_version": "9.9.9", "vms": list(vms)}

    def test_status_reports_stopped_without_a_gateway(self):
        (Path(self.env["CAPSEM_RUN_DIR"]) / "gateway.port").unlink()
        status = json.loads(self.run_helper("status").stdout)
        self.assertFalse(status["ready"])
        self.assertEqual(status["version"], "")

    def test_an_idle_tick_is_one_request(self):
        self.set_status(vm(denied_requests=3))
        status = json.loads(self.run_helper("poll").stdout)
        self.assertTrue(status["ready"])
        self.assertEqual(status["version"], "9.9.9")
        self.assertEqual(status["deniedRequests"], 3)
        self.assertEqual(self.world["requests"], [("GET", "/status")])

    def test_the_first_poll_never_notifies_about_what_was_already_there(self):
        self.set_status(vm(denied_requests=7))
        self.run_helper("poll")
        self.assertEqual(self.notifications(), [])

    def test_a_new_block_notifies_once(self):
        self.set_status(vm(denied_requests=1))
        self.run_helper("poll")
        self.set_status(vm(denied_requests=2))
        self.world["routes"][f"/vms/{VM}/timeline"] = {
            "events": [{"layer": "net", "status": 403, "summary": "GET https://example.invalid/x"}]}
        self.run_helper("poll")
        self.run_helper("poll")
        sent = self.notifications()
        self.assertEqual(len(sent), 1)
        self.assertIn("Blocked Network Request (vm-1)", sent[0])

    def test_a_new_approval_notifies_with_actions(self):
        self.set_status(vm())
        self.run_helper("poll")
        self.set_status(vm(pending_approval_count=1))
        self.world["routes"][f"/vms/{VM}/security/asks"] = {
            "generation": "g7",
            "requests": [{"ask_id": "ask-1", "status": "pending", "rule_name": "github", "summary": "git push"}]}
        status = json.loads(self.run_helper("poll").stdout)
        self.assertEqual(status["pendingAsksCount"], 1)
        sent = self.notifications()
        self.assertEqual(len(sent), 1)
        self.assertIn("Approval Required (vm-1)", sent[0])
        actions = json.loads(sent[0][sent[0].index("omarchy-actions") + 2])
        self.assertEqual([a["label"] for a in actions], ["Approve", "Deny", "Inspect VM"])
        self.assertEqual(actions[0]["argv"][1:], ["action", "ask-approve", VM, "ask-1", "g7"])

    def test_sandbox_text_cannot_put_markup_or_a_link_in_a_notification(self):
        self.set_status(vm())
        self.run_helper("poll")
        self.set_status(vm(name='<img src="https://evil.invalid/t">', pending_approval_count=1))
        self.world["routes"][f"/vms/{VM}/security/asks"] = {
            "generation": "g1",
            "requests": [{"ask_id": "a", "status": "pending", "rule_name": "<b>r</b>",
                          "summary": 'see <a href="https://evil.invalid">https://evil.invalid</a>\nline two ' + "x" * 900}]}
        status = json.loads(self.run_helper("poll").stdout)
        sent = self.notifications()[0]
        body = sent[sent.index("capsem") + 2]
        self.assertNotIn("<", body)
        self.assertNotIn("https://", body)
        self.assertNotIn("\n", body)
        self.assertLessEqual(len(body), 400)
        self.assertLessEqual(len(status["pendingAsks"][0]["summary"]), 200)
        self.assertLessEqual(len(status["vms"][0]["label"]), 40)

    def test_approve_posts_the_decision(self):
        self.assertEqual(self.run_helper("action", "ask-approve", VM, "ask-1", "g7").returncode, 0)
        self.assertIn(("POST", f"/vms/{VM}/security/asks/ask-1/resolve"), self.world["requests"])

    def test_actions_refuse_identifiers_that_are_not_plain(self):
        for bad in ("../status", "a/b", "x?y=1", "a b", "-rf"):
            self.world["requests"].clear()
            self.assertEqual(self.run_helper("action", "vm-delete", bad).returncode, 1, bad)
            self.assertEqual(self.run_helper("action", "ask-approve", VM, bad, "g").returncode, 1, bad)
            self.assertEqual(self.world["requests"], [], bad)

    def test_new_shell_opens_a_terminal_on_a_fresh_session_and_deletes_it_after(self):
        stub = Path(self.tmp.name) / "bin" / "capsem"
        stub.write_text(BUSCTL + 'if sys.argv[1:] == ["create"]:\n    print("vm-new")\n')
        stub.chmod(0o755)
        self.assertEqual(self.run_helper("action", "new-shell").returncode, 0)
        launch = None
        for _ in range(100):
            calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
            launch = next((c for c in calls if "-e" in c), None)
            if launch:
                break
            time.sleep(0.05)
        self.assertIsNotNone(launch, "no terminal was started")
        command = launch[launch.index("-e") + 1 :]
        self.calls.write_text("")
        subprocess.run(command, env=self.env, timeout=20, check=True)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual(calls, [["create"], ["shell", "vm-new"], ["delete", "vm-new"]])


if __name__ == "__main__":
    unittest.main()
