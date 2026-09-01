#!/usr/bin/env bash
# Report whether Kemory is actually working: credentials, API reachability,
# capture state, and local capture history. Read-only and safe to run anytime.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh disable=SC1091
. "$DIR/lib.sh"

ok()   { printf '  \033[32m✔\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$1"; }
info() { printf '  \033[2m·\033[0m %s\n' "$1"; }

echo "Kemory status"
echo

# --- credentials -----------------------------------------------------------
if kemory_resolve_auth; then
  case "$KEMORY_AUTH_HEADER" in
    X-API-Key:*)      mode="API key" ;;
    Authorization:*)  mode="bearer token" ;;
    *)                mode="unknown" ;;
  esac
  ok "credentials resolved — $mode"
  info "endpoint: $KEMORY_BASE_URL"
  if [ -n "${KEMORY_URL_RETARGETED_FROM:-}" ]; then
    info "your cached credential names ${KEMORY_URL_RETARGETED_FROM}, which no"
    info "longer serves the API — using the current host instead. Re-run"
    info "'kemory login' to update the credential itself"
  fi
else
  bad "no credentials"
  info "run 'kemory login' (browser sign-in), or set KEMORY_API_KEY for a keyed setup"
fi

# --- API reachability ------------------------------------------------------
if [ -n "${KEMORY_BASE_URL:-}" ] && command -v curl >/dev/null 2>&1; then
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 6 \
          -H "$KEMORY_AUTH_HEADER" "$KEMORY_BASE_URL/api/v1/namespaces" 2>/dev/null || echo 000)"
  case "$code" in
    200)      ok  "API reachable and credentials accepted (HTTP 200)" ;;
    401|403)  bad "API reachable but rejected the credentials (HTTP $code)" ;;
    000)      bad "API unreachable — wrong URL, or the server is down" ;;
    # A redirect means the endpoint is not an API host — typically a
    # browser/SSO host, which answers every path with a login redirect. Naming
    # that is the difference between a fix and a mystery status code.
    3??)      bad "API redirected (HTTP $code) — that endpoint is not the API"
              info "a browser or SSO host cannot serve the API; re-run 'kemory login',"
              info "or set KEMORY_URL to your instance's API host" ;;
    *)        bad "API returned HTTP $code" ;;
  esac
fi

# --- CLI / MCP -------------------------------------------------------------
if command -v kemory >/dev/null 2>&1; then
  ok "kemory CLI on PATH — the bundled MCP server can start"
else
  info "kemory CLI not on PATH; the bundled MCP server will not start"
  info "install it with 'brew install sekondbrainailabs/s9n/kemory', or use the"
  info "Kemory connector for tools and disable the bundled server"
fi
info "run /mcp to confirm which kemory server Claude is actually talking to"

# --- capture ---------------------------------------------------------------
echo
if [ "${KEMORY_AUTO_CAPTURE:-0}" = "1" ]; then
  ok "session capture ENABLED — digests of your prompts are uploaded at session end"
  info "namespace: ${KEMORY_CAPTURE_NAMESPACE:-shared}, last ${KEMORY_CAPTURE_MAX_TURNS:-12} turns"
else
  info "session capture disabled (default) — set KEMORY_AUTO_CAPTURE=1 to enable"
fi
n=$(find "$HOME/.kemory/.captured" -type f 2>/dev/null | wc -l | tr -d ' ')
[ "${n:-0}" -gt 0 ] && info "$n session(s) captured so far"

# --- context injection -----------------------------------------------------
if [ "${KEMORY_CONTEXT:-1}" = "1" ]; then
  info "context injection on (budget ${KEMORY_CONTEXT_MAX_CHARS:-4000} chars, depth ${KEMORY_CONTEXT_DEPTH:-l3})"
else
  info "context injection disabled via KEMORY_CONTEXT=0"
fi
exit 0
