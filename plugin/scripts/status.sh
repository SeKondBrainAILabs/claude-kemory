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
    info "run /kemory:login again — until then every hook will be rejected"
  fi
else
  bad "no credential the hooks can use — every hook is inert"
  mcp_key="$(kemory_find_mcp_config_key)"
  if [ -n "$mcp_key" ]; then
    info "found an API key in $mcp_key, which the hooks cannot read"
    info "export that same key as KEMORY_API_KEY to turn the hooks on"
  else
    if command -v kemory >/dev/null 2>&1; then
      info "run /kemory:login (browser sign-in), or set KEMORY_API_KEY"
    else
      # /kemory:login ships with the plugin, so there is no longer a machine
      # where the best route has to be installed first.
      info "run /kemory:login (browser sign-in), or set KEMORY_API_KEY"
    fi
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
# Report what actually decides whether the tools appear, not a proxy for it.
# Until 0.4.0 this printed "kemory CLI on PATH — the bundled MCP server can
# start", which was left over from a stdio entry; under the http entry that
# replaced it the CLI was irrelevant, so the line said the tools were fine
# while the entry was dead. The bundled entry now launches scripts/mcp.sh,
# which resolves a credential the same way the hooks do — so the honest check
# is to resolve it here too and name who would serve.
echo
echo "TOOLS — the kemory_* MCP tools"
if [ -n "${KEMORY_BASE_URL:-}" ]; then
  if [ -n "${KEMORY_API_KEY:-}" ] || [ -n "${KEMORY_TOKEN:-}" ]; then
    if command -v python3 >/dev/null 2>&1; then
      ok "bundled server will start — credential from the environment"
    else
      bad "credential found, but python3 is missing and the CLI cannot read it"
      info "install python3, or run 'kemory login' to use the CLI's own bridge"
    fi
  elif command -v kemory >/dev/null 2>&1; then
    ok "bundled server will start — CLI credential, served by 'kemory mcp serve'"
  elif command -v python3 >/dev/null 2>&1; then
    ok "bundled server will start — CLI credential, served by the bundled bridge"
  else
    bad "credential found, but neither the kemory CLI nor python3 is available"
  fi
else
  bad "bundled server will not start — no credential (same one the hooks need)"
  info "it exits with that reason rather than appearing connected with no tools"
  info "using the claude.ai connector for tools? that is fine — disable this"
  info "server under /mcp so you are not running two"
fi

# Two servers means two copies of every tool in each request. The connector
# lives inside Claude and cannot be seen from here, so only on-disk entries are
# counted and the connector is named as the case this cannot detect.
others=$(kemory_count_mcp_entries)
if [ "${others:-0}" -gt 0 ]; then
  if [ "$others" -eq 1 ]; then noun="entry"; else noun="entries"; fi
  info "$others other kemory MCP $noun found in your MCP configs"
  info "more than one means duplicate tools — keep one and remove the rest"
fi
info "run /mcp to confirm which kemory server Claude is actually talking to"

# --- plugin version --------------------------------------------------------
manifest="$DIR/../.claude-plugin/plugin.json"
if [ -r "$manifest" ] && command -v python3 >/dev/null 2>&1; then
  installed=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("version",""))' "$manifest" 2>/dev/null)
  [ -n "$installed" ] && info "plugin version $installed — '/plugin update kemory@kemory' to move it"
fi

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
