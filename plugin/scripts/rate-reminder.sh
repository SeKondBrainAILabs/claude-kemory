#!/usr/bin/env bash
# PostToolUse hook: after a kemory recall, remind the agent to rate the
# memories it actually used. Best-effort — never blocks, never errors.
set -uo pipefail
input="$(cat)"
recall_id="unknown"
if command -v jq >/dev/null 2>&1; then
  recall_id="$(printf '%s' "$input" | jq -r '.tool_response.retrieval.recall_id // "unknown"' 2>/dev/null || echo unknown)"
elif command -v python3 >/dev/null 2>&1; then
  recall_id="$(printf '%s' "$input" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("tool_response",{}).get("retrieval",{}).get("recall_id","unknown"))
except Exception: print("unknown")' 2>/dev/null || echo unknown)"
fi
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Reminder: you just called a kemory recall tool. Before ending this turn, call kemory_rate_memory for each memory you actually used in your response (up if it helped, down with a reason if not). Do not rate memories you merely skimmed. recall_id=%s"}}\n' "$recall_id"
exit 0
