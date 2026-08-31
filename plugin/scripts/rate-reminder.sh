#!/usr/bin/env bash
# PostToolUse hook — after a Kemory recall, remind the agent to rate the
# memories it actually used, so retrieval quality improves instead of decaying.
#
# Stays silent when the recall returned nothing: a reminder to rate zero
# memories is noise, and repeated noise trains the agent to ignore it.
#
# Best-effort by design: never blocks, never errors.
set -uo pipefail
input="$(cat)"

read_fields() {
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$input" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("unknown 1"); raise SystemExit(0)   # unparseable -> fail open, remind
r = d.get("tool_response")
if isinstance(r, str):
    try:
        r = json.loads(r)
    except Exception:
        r = None
if not isinstance(r, dict):
    print("unknown 1"); raise SystemExit(0)
rid = (r.get("retrieval") or {}).get("recall_id") or "unknown"
count = None
for key in ("memories", "results", "items"):
    v = r.get(key)
    if isinstance(v, list):
        count = len(v); break
if count is None:
    t = r.get("total") or r.get("count")
    count = t if isinstance(t, int) else 1      # unknown shape -> fail open
print(rid, count)
' 2>/dev/null || printf 'unknown 1'
  else
    printf 'unknown 1'
  fi
}

read -r recall_id count <<< "$(read_fields)"
[ -n "${count:-}" ] || count=1
[ "$count" -gt 0 ] 2>/dev/null || exit 0

printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Reminder: you just recalled %s memory/memories from Kemory. Before ending this turn, call kemory_rate_memory for each one you actually used in your response (up if it helped, down with a reason if not). Do not rate memories you merely skimmed. recall_id=%s"}}\n' \
  "$count" "${recall_id:-unknown}"
exit 0
