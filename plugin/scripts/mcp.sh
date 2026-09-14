#!/usr/bin/env bash
# Launcher for the bundled MCP server: resolve a credential, then serve.
#
# The invariant this exists to hold: ONE bundled entry, credential resolved at
# launch, never a static header in .mcp.json. A static header can only name one
# of the three ways a user reaches Kemory, so every previous version was dead
# for the other two — stdio needed the CLI on PATH, HTTP needed KEMORY_API_KEY
# in the environment, and the transport was switched three times because each
# fix broke the population the other served. Resolving here ends that: the same
# lib.sh function the hooks use answers for the tools too, so the two halves
# cannot authenticate differently or point at different hosts.
#
# Serves via the CLI's own bridge when the credential came from the CLI (it
# refreshes its token natively), and via mcp_bridge.py when the credential came
# from the environment (which the CLI bridge does not read).
#
# Exits non-zero with one line on stderr when there is no credential. A server
# that starts and exposes nothing looks connected in /mcp while every memory
# tool is missing, which is the failure this whole change is about.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh disable=SC1091
. "$DIR/lib.sh"

if ! kemory_resolve_auth; then
  echo "kemory: no credential — run /kemory:login in Claude Code to sign in with your browser (or set KEMORY_API_KEY for a headless machine). Using the claude.ai connector instead? Disable this server under /mcp." >&2
  exit 1
fi

if [ "${KEMORY_TOKEN_EXPIRED:-0}" = "1" ]; then
  echo "kemory: stored token expired and could not be refreshed — run /kemory:login to sign in again." >&2
  exit 1
fi

# Which credential lib.sh used decides who serves. The CLI bridge reads
# ~/.kemory/credentials-<env> and ignores KEMORY_API_KEY, so preferring it for
# an environment credential would silently serve a different account than the
# hooks use.
from_env=0
[ -n "${KEMORY_API_KEY:-}" ] && from_env=1
[ -n "${KEMORY_TOKEN:-}" ] && from_env=1

if [ "$from_env" -eq 0 ] && command -v kemory >/dev/null 2>&1; then
  exec kemory mcp serve
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "kemory: need python3 (or the kemory CLI) to serve the memory tools." >&2
  exit 1
fi

exec python3 "$DIR/mcp_bridge.py"
