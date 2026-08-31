#!/usr/bin/env python3
"""Behavioural tests for the hook scripts.

These drive the real scripts with synthetic payloads against a local HTTP
server, so they exercise the shipped code rather than a copy of its logic.
Run: python3 test/test_hooks.py
"""
import http.server
import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import threading
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "plugin" / "scripts"


class Recorder(http.server.BaseHTTPRequestHandler):
    posts: list = []
    get_payload: dict = {"namespaces": []}

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        Recorder.posts.append((self.headers, json.loads(self.rfile.read(n) or b"{}")))
        self.send_response(201)
        self.end_headers()
        self.wfile.write(b"{}")

    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(Recorder.get_payload).encode())

    def log_message(self, *a):
        pass


class HookTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srv = http.server.HTTPServer(("127.0.0.1", 0), Recorder)
        cls.port = cls.srv.server_address[1]
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()

    def setUp(self):
        Recorder.posts.clear()
        Recorder.get_payload = {"namespaces": []}
        self.home = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)

    def env(self, **extra):
        e = {k: v for k, v in os.environ.items()
             if not k.startswith("KEMORY_")}
        e.update({"HOME": self.home,
                  "KEMORY_URL": f"http://127.0.0.1:{self.port}"})
        e.update(extra)
        return e

    def run_script(self, name, payload, **env):
        return subprocess.run([str(SCRIPTS / name)], input=json.dumps(payload),
                              text=True, capture_output=True, env=self.env(**env))

    def transcript(self, *messages):
        p = pathlib.Path(tempfile.mktemp(suffix=".jsonl", dir=self.home))
        p.write_text("".join(
            json.dumps({"type": "user", "message": {"content": m}}) + "\n"
            for m in messages))
        return str(p)

    # --- capture ----------------------------------------------------------
    def test_capture_disabled_by_default(self):
        r = self.run_script("capture.sh",
                            {"session_id": "s", "transcript_path": self.transcript("hi")},
                            KEMORY_API_KEY="k")
        self.assertEqual(r.stdout, "")
        self.assertEqual(len(Recorder.posts), 0, "capture must be opt-in")

    def test_capture_uploads_when_enabled(self):
        self.run_script("capture.sh",
                        {"session_id": "s", "transcript_path": self.transcript("add retries")},
                        KEMORY_API_KEY="k", KEMORY_AUTO_CAPTURE="1")
        self.assertEqual(len(Recorder.posts), 1)
        _, body = Recorder.posts[0]
        self.assertIn("add retries", body["content"])
        self.assertEqual(body["namespace_tag"], "session-capture")

    def test_capture_dedupes_identical_digest(self):
        t = self.transcript("one task")
        for reason in ("clear", "clear", "exit"):
            self.run_script("capture.sh",
                            {"session_id": "s", "transcript_path": t, "reason": reason},
                            KEMORY_API_KEY="k", KEMORY_AUTO_CAPTURE="1")
        self.assertEqual(len(Recorder.posts), 1,
                         "SessionEnd fires repeatedly; identical digests must upload once")

    def test_capture_uploads_again_for_new_turns(self):
        t = self.transcript("one task")
        self.run_script("capture.sh", {"session_id": "s", "transcript_path": t},
                        KEMORY_API_KEY="k", KEMORY_AUTO_CAPTURE="1")
        pathlib.Path(t).write_text(pathlib.Path(t).read_text() +
                                   json.dumps({"type": "user", "message": {"content": "second task"}}) + "\n")
        self.run_script("capture.sh", {"session_id": "s", "transcript_path": t},
                        KEMORY_API_KEY="k", KEMORY_AUTO_CAPTURE="1")
        self.assertEqual(len(Recorder.posts), 2)

    def test_capture_refuses_non_http_url(self):
        self.run_script("capture.sh",
                        {"session_id": "s", "transcript_path": self.transcript("x")},
                        KEMORY_API_KEY="k", KEMORY_AUTO_CAPTURE="1",
                        KEMORY_URL="file:///etc/passwd")
        self.assertEqual(len(Recorder.posts), 0)

    def test_capture_skips_assistant_turns_and_harness_noise(self):
        p = pathlib.Path(tempfile.mktemp(suffix=".jsonl", dir=self.home))
        p.write_text("\n".join([
            json.dumps({"type": "user", "message": {"content": "real intent"}}),
            json.dumps({"type": "assistant", "message": {"content": "assistant reply"}}),
            json.dumps({"type": "user", "message": {"content": "<system-reminder>noise</system-reminder>"}}),
        ]) + "\n")
        self.run_script("capture.sh", {"session_id": "s", "transcript_path": str(p)},
                        KEMORY_API_KEY="k", KEMORY_AUTO_CAPTURE="1")
        _, body = Recorder.posts[0]
        self.assertIn("real intent", body["content"])
        self.assertNotIn("assistant reply", body["content"])
        self.assertNotIn("system-reminder", body["content"])
        self.assertEqual(body["metadata"]["turns"], 1)

    # --- redaction --------------------------------------------------------
    SECRETS = [
        "export GH_TOKEN=ghp_AAAAAAAAAAAAAAAAAAAAAAAA",
        'api_key="sk-abcdefghij1234567890"',
        "password: hunter2supersecret",
        "AKIAIOSFODNN7EXAMPLE",
        "xoxb-1234567890-abcdefghij",
    ]
    PROSE = [
        "the token expired yesterday, please regenerate",
        "our secret sauce is caching",
        "add a password field to the signup form",
        "why does the api_key check fail on staging",
    ]

    def _captured(self, line):
        # Unique session per call: two different secrets can redact to identical
        # content, which the de-duplicator would (correctly) collapse.
        Recorder.posts.clear()
        self.run_script("capture.sh",
                        {"session_id": f"s{abs(hash(line))}",
                         "transcript_path": self.transcript(line)},
                        KEMORY_API_KEY="k", KEMORY_AUTO_CAPTURE="1")
        self.assertTrue(Recorder.posts, f"no upload for: {line!r}")
        return Recorder.posts[0][1]["content"]

    def test_secrets_are_redacted(self):
        for s in self.SECRETS:
            with self.subTest(secret=s):
                self.assertIn("[REDACTED]", self._captured(s))

    def test_prose_is_not_redacted(self):
        # Developer conversation says "token" and "secret" constantly; redacting
        # those sentences would gut exactly the content worth keeping.
        for s in self.PROSE:
            with self.subTest(prose=s):
                self.assertNotIn("[REDACTED]", self._captured(s))

    # --- rate reminder ----------------------------------------------------
    def test_reminder_silent_on_empty_recall(self):
        r = self.run_script("rate-reminder.sh",
                            {"tool_response": {"memories": [], "retrieval": {"recall_id": "r"}}})
        self.assertEqual(r.stdout.strip(), "")

    def test_reminder_fires_with_count_and_recall_id(self):
        r = self.run_script("rate-reminder.sh",
                            {"tool_response": {"memories": [1, 2, 3],
                                               "retrieval": {"recall_id": "rc_x"}}})
        ctx = json.loads(r.stdout)["hookSpecificOutput"]["additionalContext"]
        self.assertIn("3 memories", ctx)
        self.assertIn("rc_x", ctx)

    def test_reminder_silent_on_unparseable_input(self):
        # Fail CLOSED, not open: the matcher covers the whole kemory_* recall
        # family, so an unparseable non-recall response must not produce a
        # reminder to rate memories that were never recalled.
        r = subprocess.run([str(SCRIPTS / "rate-reminder.sh")], input="not json",
                           text=True, capture_output=True, env=self.env())
        self.assertEqual(r.stdout.strip(), "")

    def test_reminder_fires_for_recall_alias_shape(self):
        # kemory_recall is a documented alias of kemory_recall_memory and
        # returns the same envelope; it must be reminded on too.
        r = self.run_script("rate-reminder.sh",
                            {"tool_response": {"total": 2, "showing": 2,
                                               "memories": [1, 2],
                                               "retrieval": {"recall_id": "rc_alias"}}})
        ctx = json.loads(r.stdout)["hookSpecificOutput"]["additionalContext"]
        self.assertIn("2 memories", ctx)
        self.assertIn("rc_alias", ctx)

    def test_reminder_fires_on_recall_id_without_list(self):
        r = self.run_script("rate-reminder.sh",
                            {"tool_response": {"retrieval": {"recall_id": "rc_only"}}})
        self.assertIn("rc_only", r.stdout)

    def test_reminder_silent_for_non_recall_response(self):
        # A store/write response carries no recall_id and no result list.
        r = self.run_script("rate-reminder.sh",
                            {"tool_response": {"memory_id": "m", "namespace": "shared",
                                               "version": 1}})
        self.assertEqual(r.stdout.strip(), "")

    def test_hook_matcher_covers_recall_family(self):
        import re
        hooks = json.loads((ROOT / "plugin" / "hooks" / "hooks.json").read_text())
        matcher = hooks["hooks"]["PostToolUse"][0]["matcher"]
        rx = re.compile(matcher)
        for tool in ("recall", "recall_memory", "get_context", "ask", "memory",
                     "find_similar", "get_compressed", "get_raw",
                     "get_session_context", "get_namespace_summary"):
            name = f"mcp__plugin_kemory_kemory__kemory_{tool}"
            with self.subTest(tool=tool):
                self.assertTrue(rx.match(name), f"{tool} not covered by matcher")

    # --- session start ----------------------------------------------------
    def test_session_start_injects_summaries(self):
        Recorder.get_payload = {"namespaces": [
            {"namespace": "user:preferences", "summary": "Prefers concise answers."}]}
        r = self.run_script("session-start.sh", {}, KEMORY_API_KEY="k")
        out = json.loads(r.stdout)
        self.assertEqual(out["hookSpecificOutput"]["hookEventName"], "SessionStart")
        self.assertIn("user:preferences", out["hookSpecificOutput"]["additionalContext"])

    def test_session_start_respects_budget(self):
        Recorder.get_payload = {"namespaces": [
            {"namespace": f"ns{i}", "summary": "S" * 400} for i in range(5)]}
        r = self.run_script("session-start.sh", {}, KEMORY_API_KEY="k",
                            KEMORY_CONTEXT_MAX_CHARS="600")
        ctx = json.loads(r.stdout)["hookSpecificOutput"]["additionalContext"]
        self.assertEqual(ctx.count("- ["), 1)
        self.assertIn("omitted", ctx)

    def test_session_start_namespace_allowlist(self):
        Recorder.get_payload = {"namespaces": [
            {"namespace": "keep", "summary": "yes"},
            {"namespace": "drop", "summary": "no"}]}
        r = self.run_script("session-start.sh", {}, KEMORY_API_KEY="k",
                            KEMORY_CONTEXT_NAMESPACES="keep")
        ctx = json.loads(r.stdout)["hookSpecificOutput"]["additionalContext"]
        self.assertIn("keep", ctx)
        self.assertNotIn("drop", ctx)

    def test_session_start_disabled(self):
        r = self.run_script("session-start.sh", {}, KEMORY_API_KEY="k", KEMORY_CONTEXT="0")
        self.assertEqual(r.stdout.strip(), "")

    def test_setup_hint_shown_once_then_quiet(self):
        first = self.run_script("session-start.sh", {}, KEMORY_URL="")
        self.assertIn("systemMessage", first.stdout)
        second = self.run_script("session-start.sh", {}, KEMORY_URL="")
        self.assertEqual(second.stdout.strip(), "", "must not nag every session")

    def test_setup_hint_suppressed_by_flag(self):
        r = self.run_script("session-start.sh", {}, KEMORY_URL="", KEMORY_QUIET_SETUP="1")
        self.assertEqual(r.stdout.strip(), "")


if __name__ == "__main__":
    unittest.main(verbosity=2)
