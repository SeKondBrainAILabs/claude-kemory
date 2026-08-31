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
  # shellcheck disable=SC2016  # backticks are markdown, not expansion
  printf '%s\n' '{"systemMessage":"Kemory plugin: no memory backend configured yet. Run `kemory login`, or set KEMORY_URL with KEMORY_TOKEN (hosted) or KEMORY_API_KEY (self-hosted). Set KEMORY_QUIET_SETUP=1 to silence this."}'
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
KEMORY_MAX_CHARS="${KEMORY_CONTEXT_MAX_CHARS:-4000}" \
KEMORY_NAMESPACES="${KEMORY_CONTEXT_NAMESPACES:-}" \
python3 <<'PY' 2>/dev/null
import json, os, sys

try:
    data = json.loads(os.environ["KEMORY_RESP"])
except Exception:
    sys.exit(0)

namespaces = data.get("namespaces")
if not isinstance(namespaces, list):
    # Not the expected shape — most likely an auth error body. Stay silent.
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
