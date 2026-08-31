#!/usr/bin/env bash
# Shared credential resolution for Kemory hooks. Sourced, not executed.
#
# Sets, on success (return 0):
#   KEMORY_BASE_URL    — API base, no trailing slash
#   KEMORY_AUTH_HEADER — a complete header line to send
#
# Hosted Kemory authenticates with a bearer token; the community edition
# authenticates with X-API-Key only (backend/core/auth.py), so both are
# supported and detected rather than assumed.
kemory_resolve_auth() {
  local creds url token api_key
  url="" ; token="" ; api_key=""

  if [ -n "${KEMORY_API_KEY:-}" ]; then
    api_key="$KEMORY_API_KEY"
    url="${KEMORY_URL:-}"
  elif [ -n "${KEMORY_TOKEN:-}" ]; then
    token="$KEMORY_TOKEN"
    url="${KEMORY_URL:-}"
  else
    creds="$HOME/.kemory/credentials-${KEMORY_ENV:-prod}"
    [ -r "$creds" ] || creds="$HOME/.kemory/credentials"
    [ -r "$creds" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
    # shellcheck disable=SC2016
    eval "$(KEMORY_CREDS="$creds" python3 -c '
import json, os, shlex
try:
    d = json.load(open(os.environ["KEMORY_CREDS"]))
except Exception:
    raise SystemExit(0)
for var, key in (("url", "kemory_url"), ("token", "access_token"), ("api_key", "api_key")):
    v = d.get(key) or ""
    if v:
        print(f"{var}={shlex.quote(str(v))}")
' 2>/dev/null)"
  fi

  [ -n "$url" ] || return 1
  if [ -n "$api_key" ]; then
    KEMORY_AUTH_HEADER="X-API-Key: $api_key"
  elif [ -n "$token" ]; then
    KEMORY_AUTH_HEADER="Authorization: Bearer $token"
  else
    return 1
  fi
  KEMORY_BASE_URL="${url%/}"
  export KEMORY_BASE_URL KEMORY_AUTH_HEADER
  return 0
}
