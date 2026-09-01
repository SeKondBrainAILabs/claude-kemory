#!/usr/bin/env bash
# Shared credential resolution for Kemory hooks. Sourced, not executed.
#
# Sets, on success (return 0):
#   KEMORY_BASE_URL    — API base, no trailing slash
#   KEMORY_AUTH_HEADER — a complete header line to send
#   KEMORY_URL_RETARGETED_FROM — set only when a superseded host was rewritten
#
# Hosted Kemory authenticates with a bearer token; the community edition
# authenticates with X-API-Key only (backend/core/auth.py), so both are
# supported and detected rather than assumed.
# Hosted Kemory. Only override KEMORY_URL when pointing at a self-hosted or
# community instance, so the common case needs a key and nothing else.
KEMORY_DEFAULT_URL="${KEMORY_DEFAULT_URL:-https://api.kemory.sekondbrain.ai}"

# A cached credential keeps the API host it was written with, so a host that has
# since stopped serving the API survives indefinitely on an existing install —
# the default above only ever reaches a fresh login. The kemory CLI rewrites
# these when it loads a credential; this path reads the file directly, so it
# needs the same rewrite or the hooks and /kemory:status stay pointed at a dead
# host while the CLI itself is fine.
#
# Exact match only. A self-hosted or community host that merely looks similar
# must be left alone.
#
# Answers in KEMORY_RETARGETED_URL rather than on stdout: a command
# substitution would run this in a subshell and lose the
# KEMORY_URL_RETARGETED_FROM breadcrumb, leaving a silent rewrite.
kemory_retarget_url() {
  KEMORY_RETARGETED_URL="$1"
  case "$1" in
    # Retired: now redirects to the browser dashboard, which sends any API path
    # on to SSO login. A caller sees a redirect or an HTML login page.
    https://kemory.prod.apps.s9n.ai)
      KEMORY_RETARGETED_URL="https://api.kemory.s9n.ai"
      KEMORY_URL_RETARGETED_FROM="$1"
      ;;
  esac
}

kemory_resolve_auth() {
  local creds url token api_key
  url="" ; token="" ; api_key=""
  unset KEMORY_URL_RETARGETED_FROM

  if [ -n "${KEMORY_API_KEY:-}" ]; then
    api_key="$KEMORY_API_KEY"
    url="${KEMORY_URL:-$KEMORY_DEFAULT_URL}"
  elif [ -n "${KEMORY_TOKEN:-}" ]; then
    token="$KEMORY_TOKEN"
    url="${KEMORY_URL:-$KEMORY_DEFAULT_URL}"
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
  kemory_retarget_url "${url%/}"
  KEMORY_BASE_URL="$KEMORY_RETARGETED_URL"
  export KEMORY_BASE_URL KEMORY_AUTH_HEADER KEMORY_URL_RETARGETED_FROM
  return 0
}
