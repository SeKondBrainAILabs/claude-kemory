#!/usr/bin/env bash
# SessionStart hook — inject the user's Kemory memory summaries so a session
# begins already knowing their preferences and project context, instead of
# starting blind and hoping the agent thinks to call recall.
#
# Also acts as a preflight: if Kemory is not usable yet, say so once, with the
# exact command to fix it, rather than failing silently in /mcp.
#
# Best-effort by design: any failure emits nothing and exits 0.
set -uo pipefail
[ "${KEMORY_CONTEXT:-1}" = "1" ] || exit 0

# The hook payload carries `source`: startup | resume | clear | compact.
# "compact" is the only channel that can nudge consolidation -- PreCompact
# itself rejects hookSpecificOutput.additionalContext outright, and runs as
# compaction begins, so the model would get no turn to act on it anyway.
PAYLOAD="$(cat 2>/dev/null || true)"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh disable=SC1091
. "$DIR/lib.sh"

emit_setup_hint() {
  [ "${KEMORY_QUIET_SETUP:-0}" = "1" ] && exit 0
  local stamp="$HOME/.kemory/.setup-hint"
  # Nag at most once a day so a deliberate connector-only setup is not spammed.
  if [ -f "$stamp" ]; then
    local now age
    now=$(date +%s)
    age=$(( now - $(stat -f %m "$stamp" 2>/dev/null || stat -c %Y "$stamp" 2>/dev/null || echo "$now") ))
    [ "$age" -lt 86400 ] && exit 0
  fi
  mkdir -p "$(dirname "$stamp")" 2>/dev/null && touch "$stamp" 2>/dev/null

  # Never claim "nothing is configured": the MCP tools authenticate
  # separately and are very often already working when this fires. Say what
  # is actually true -- the hooks have no credential of their own -- and if a
  # key is sitting in an MCP config, name that file, because following our
  # own docs is the most likely way to arrive here.
  local found msg
  found="$(kemory_find_mcp_config_key)"
  if [ -n "$found" ]; then
    msg="Kemory plugin: found an API key in $found, which the hooks cannot read \u2014 they take a credential from the environment or the CLI, not from MCP config. Your memory tools are unaffected. To turn the hooks on, export KEMORY_API_KEY with that same key."
  else
    # Do not name a command the machine does not have. A fresh install with no
    # CLI got told to run `kemory login` with no way to obtain it.
    if command -v kemory >/dev/null 2>&1; then
      msg="Kemory plugin: the hooks have no credential, so context injection, prompt recall, rating and capture are off. Your MCP memory tools may already be working \u2014 they authenticate separately. To turn the hooks on, run \`kemory login\` (browser sign-in) or export KEMORY_API_KEY."
    else
      msg="Kemory plugin: the hooks have no credential, so context injection, prompt recall, rating and capture are off. Your MCP memory tools may already be working \u2014 they authenticate separately. Quickest fix: export KEMORY_API_KEY with a key from kemory.sekondbrain.ai. Or install the kemory CLI and run \`kemory login\` \u2014 see the plugin README for how to get it."
    fi
  fi
  KEMORY_MSG="$msg" python3 -c 'import json, os; print(json.dumps({"systemMessage": os.environ["KEMORY_MSG"].encode().decode("unicode_escape") + " Silence this with KEMORY_QUIET_SETUP=1."}))' 2>/dev/null \
    || printf '%s\n' '{"systemMessage":"Kemory plugin: the hooks have no credential, so context injection, recall, rating and capture are off. Run kemory login, or export KEMORY_API_KEY. Silence this with KEMORY_QUIET_SETUP=1."}'
  exit 0
}

kemory_resolve_auth || emit_setup_hint
command -v curl >/dev/null 2>&1 || exit 0

DEPTH="${KEMORY_CONTEXT_DEPTH:-l3}"
RESP="$(curl -s --max-time "${KEMORY_CONTEXT_TIMEOUT:-6}" \
  -H "$KEMORY_AUTH_HEADER" \
  "$KEMORY_BASE_URL/api/v1/user/context?depth=$DEPTH" 2>/dev/null)" || exit 0
[ -n "$RESP" ] || exit 0

command -v python3 >/dev/null 2>&1 || exit 0
KEMORY_RESP="$RESP" \
KEMORY_PAYLOAD="$PAYLOAD" \
KEMORY_MAX_CHARS="${KEMORY_CONTEXT_MAX_CHARS:-4000}" \
KEMORY_NAMESPACES="${KEMORY_CONTEXT_NAMESPACES:-}" \
python3 <<'PY' 2>/dev/null
import json, os, sys

try:
    data = json.loads(os.environ["KEMORY_RESP"])
except Exception:
    sys.exit(0)

try:
    source = (json.loads(os.environ.get("KEMORY_PAYLOAD") or "{}")
              .get("source") or "")
except Exception:
    source = ""
compacted = source == "compact"

CONSOLIDATE = (
    "This session was just compacted. Anything established before the "
    "compaction now exists only as a summary. If this session produced "
    "durable facts, decisions or solved problems that are not in kemory "
    "yet, store them now with kemory_consolidate_session (or "
    "kemory_store_memory for individual facts) before continuing."
)

namespaces = data.get("namespaces")
if not isinstance(namespaces, list):
    # Not the expected shape — most likely an auth error body. Stay silent,
    # except after a compaction, where the nudge stands on its own.
    if compacted:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": CONSOLIDATE}}))
    sys.exit(0)

wanted = {n.strip() for n in os.environ["KEMORY_NAMESPACES"].split(",") if n.strip()}
lines = []
for ns in namespaces:
    ns = ns or {}
    summary = (ns.get("summary") or "").strip()
    name = ns.get("namespace")
    if not summary:
        continue
    if wanted and name not in wanted:
        continue
    lines.append(f"- [{name}] {summary}")

if not lines:
    if compacted:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": CONSOLIDATE}}))
    sys.exit(0)

budget = max(500, int(os.environ["KEMORY_MAX_CHARS"]))
body, used, truncated = [], 0, False
for line in lines:
    if used + len(line) > budget:
        truncated = True
        break
    body.append(line)
    used += len(line)
if not body:
    sys.exit(0)

context = (
    "Your Kemory memory (persistent across sessions) — namespace summaries:\n"
    + "\n".join(body)
)
if truncated:
    context += (
        f"\n\n({len(lines) - len(body)} more namespace summaries omitted to stay "
        "within the context budget; raise KEMORY_CONTEXT_MAX_CHARS to include them.)"
    )
if compacted:
    context += "\n\n" + CONSOLIDATE
context += (
    "\n\nRecall details with kemory_recall_memory / kemory_get_context before "
    "re-deriving anything, and rate what you use with kemory_rate_memory."
)

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": context,
    }
}))
PY
exit 0
