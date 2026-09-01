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

# Kemory has two independent halves and they authenticate separately: the MCP
# tools, and the hooks. Reporting one number for both is how a user ends up
# believing the plugin works when half of it is inert.
echo "HOOKS — context injection, prompt recall, rating, capture"

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
    info "${KEMORY_URL_RETARGETED_FROM} no longer serves the API — using the"
    info "current host instead. Where that value comes from still needs fixing:"
    # Two different setups reach the same dead host, and the remedy differs. Do
    # not tell someone with no CLI to re-run a CLI command.
    if [ -n "${KEMORY_URL:-}" ]; then
      info "KEMORY_URL is set — point it at https://api.kemory.s9n.ai"
    else
      info "it is stored in your credentials file — re-run 'kemory login'"
    fi
  fi
  if [ "${KEMORY_TOKEN_EXPIRED:-0}" = "1" ]; then
    bad "the stored token is expired and could not be refreshed"
    info "run 'kemory login' again — until then every hook will be rejected"
  fi
else
  bad "no credential the hooks can use — every hook is inert"
  mcp_key="$(kemory_find_mcp_config_key)"
  if [ -n "$mcp_key" ]; then
    info "found an API key in $mcp_key, which the hooks cannot read"
    info "export that same key as KEMORY_API_KEY to turn the hooks on"
  else
    info "run 'kemory login' (browser sign-in), or set KEMORY_API_KEY"
  fi
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

# --- MCP tools -------------------------------------------------------------
echo
echo "TOOLS — the kemory_* MCP tools (a separate credential from the hooks)"
if command -v kemory >/dev/null 2>&1; then
  ok "kemory CLI on PATH — the bundled MCP server can start"
else
  info "kemory CLI not on PATH, so the bundled MCP server will not start"
  info "that is fine if you connect another way — the Kemory connector, or a"
  info "custom connector at https://api.kemory.s9n.ai/mcp/v1"
fi
info "run /mcp to confirm which kemory server Claude is actually talking to"

# --- capture ---------------------------------------------------------------
echo
echo "SETTINGS"
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
