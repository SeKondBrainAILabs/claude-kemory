#!/usr/bin/env bash
# Sign in to Kemory from the plugin. Thin wrapper over login.py, matching how
# status.sh fronts its own logic — the command file invokes this.
#
# Deliberately NOT no-op safe. Every hook exits 0 on every error path because a
# hook must never fail a user's session; this is a command the user ran on
# purpose, and a sign-in that quietly does nothing is the failure mode this
# whole change exists to remove.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "kemory: need python3 to sign in. Install it, or set KEMORY_API_KEY instead." >&2
  exit 1
fi

exec python3 "$DIR/login.py"
