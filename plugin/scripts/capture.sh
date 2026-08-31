#!/usr/bin/env bash
# SessionEnd / TaskCompleted hook — capture a bounded digest of the session
# into kemory as an episodic memory, tagged with session_id so the server-side
# Reflector can consolidate episodes into a semantic summary later.
#
# OPT-IN. Capture uploads conversation content to your kemory instance, so it
# stays off until you explicitly set KEMORY_AUTO_CAPTURE=1.
#
# Best-effort by design: any failure exits 0 so a session is never blocked.
set -uo pipefail

[ "${KEMORY_AUTO_CAPTURE:-0}" = "1" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh disable=SC1091
. "$DIR/lib.sh"
# Resolves hosted (bearer) or community (X-API-Key) auth, from the CLI's
# credential file or from environment variables.
kemory_resolve_auth || exit 0

HOOK_INPUT="$(cat)"
export HOOK_INPUT
export KEMORY_NAMESPACE="${KEMORY_CAPTURE_NAMESPACE:-shared}"
export KEMORY_MAX_TURNS="${KEMORY_CAPTURE_MAX_TURNS:-12}"
export KEMORY_CAPTURE_SOURCE="${KEMORY_CAPTURE_SOURCE:-claude-code}"

python3 <<'PY' 2>/dev/null
import json, os, re, urllib.request

MAX_CHARS = 8000
SECRET = re.compile(
    r'(?i)(bearer\s+[\w\-\.]+|(?:api[_-]?key|token|secret|password|passwd)'
    r'["\'\s:=]+[^\s"\',}]+|sk-[A-Za-z0-9]{16,}|gh[pousr]_[A-Za-z0-9]{20,}'
    r'|AKIA[0-9A-Z]{16}|-----BEGIN[^-]+PRIVATE KEY-----)'
)

def die():
    raise SystemExit(0)

try:
    url = os.environ["KEMORY_BASE_URL"]
    auth_name, _, auth_value = os.environ["KEMORY_AUTH_HEADER"].partition(": ")
    hook = json.loads(os.environ["HOOK_INPUT"])
except Exception:
    die()
if not url or not auth_value:
    die()

session_id = hook.get("session_id") or ""
transcript = hook.get("transcript_path") or ""
if not transcript or not os.path.isfile(transcript):
    die()

# Only the user's own turns: they carry intent and goals, and skipping
# assistant output keeps the digest small and avoids re-storing tool dumps.
turns = []
try:
    with open(transcript, errors="replace") as fh:
        for line in fh:
            try:
                ev = json.loads(line)
            except Exception:
                continue
            if ev.get("type") != "user":
                continue
            content = (ev.get("message") or {}).get("content")
            if isinstance(content, list):
                content = " ".join(
                    p.get("text", "") for p in content if isinstance(p, dict)
                )
            if isinstance(content, str):
                t = content.strip()
                # Skip harness-injected noise, not real user intent.
                if t and not t.startswith(("<", "Caveat:")):
                    turns.append(t)
except Exception:
    die()

turns = turns[-int(os.environ["KEMORY_MAX_TURNS"]):]
if not turns:
    die()

body = SECRET.sub("[REDACTED]", "\n".join(f"- {t}" for t in turns))[:MAX_CHARS]
content = (
    "What was this coding session about? Session digest captured automatically "
    f"at session end (user turns only, secrets redacted).\n\ncwd: "
    f"{hook.get('cwd', 'unknown')}\n\n{body}"
)

req = urllib.request.Request(
    url + "/api/v1/memories",
    data=json.dumps({
        "namespace": os.environ["KEMORY_NAMESPACE"],
        "namespace_tag": "session-capture",
        "content": content,
        "content_type": "text",
        "session_id": session_id,
        "metadata": {
            "source": os.environ.get("KEMORY_CAPTURE_SOURCE", "claude-code"),
            "capture": "auto",
            "turns": len(turns),
        },
    }).encode(),
    headers={
        auth_name: auth_value,
        "Content-Type": "application/json",
    },
    method="POST",
)
try:
    urllib.request.urlopen(req, timeout=8).read()
except Exception:
    pass
PY
exit 0
