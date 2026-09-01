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
import json, os, shlex, time

CREDS = os.environ["KEMORY_CREDS"]
try:
    d = json.load(open(CREDS))
except Exception:
    raise SystemExit(0)

expired = False


def refresh(d):
    """Trade the refresh token for a fresh access token, in place.

    The CLI refreshes on every use; the hooks used to read access_token and
    nothing else, so once it expired every hook 401d and no-opd with no
    notice at all -- the setup hint only fires when no credential file
    exists, and a stale one does. Best-effort: any failure leaves the old
    token in place and the caller reports it as expired.
    """
    import urllib.parse
    import urllib.request

    issuer = (d.get("issuer") or "").rstrip("/")
    token = d.get("refresh_token")
    client = d.get("client_id")
    if not (issuer and token and client):
        return False
    body = urllib.parse.urlencode({
        "grant_type": "refresh_token",
        "refresh_token": token,
        "client_id": client,
    }).encode()
    req = urllib.request.Request(
        issuer + "/protocol/openid-connect/token",
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urllib.request.urlopen(req, timeout=6) as r:
            fresh = json.load(r)
    except Exception:
        return False
    if not fresh.get("access_token"):
        return False
    d["access_token"] = fresh["access_token"]
    if fresh.get("refresh_token"):
        d["refresh_token"] = fresh["refresh_token"]
    if fresh.get("expires_in"):
        d["expires_at"] = time.time() + float(fresh["expires_in"])
    # Atomic, and 0600 -- this file holds a bearer token. Written beside the
    # original so the rename cannot cross a filesystem boundary.
    tmp = CREDS + ".tmp"
    try:
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as fh:
            json.dump(d, fh)
        os.replace(tmp, CREDS)
    except Exception:
        try:
            os.unlink(tmp)
        except Exception:
            pass
        # The refreshed token is still good for this process even if the
        # write failed, so do not report failure.
    return True


exp = d.get("expires_at")
if d.get("access_token") and isinstance(exp, (int, float)):
    if time.time() > float(exp) - 60 and not refresh(d):
        expired = True

for var, key in (("url", "kemory_url"), ("token", "access_token"), ("api_key", "api_key")):
    v = d.get(key) or ""
    if v:
        print(f"{var}={shlex.quote(str(v))}")
if expired:
    print("KEMORY_TOKEN_EXPIRED=1")
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

# Locate a Kemory API key sitting in an MCP client config, where our own docs
# tell Claude Code users to put it.
#
# The hooks cannot use it: they read KEMORY_API_KEY / KEMORY_TOKEN from the
# environment, or the CLI credential file. A user who follows the documented
# local-client route therefore ends up with a valid key on disk, working
# tools, and no hooks. This detects that state so we can say so, and
# deliberately does NOT return the key itself -- harvesting a credential out
# of another tool's config is not a habit worth building in.
#
# Echoes the config path and returns 0 when found.
kemory_find_mcp_config_key() {
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$@" <<'PY' 2>/dev/null
import json, os, sys

candidates = [
    os.path.join(os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()), ".mcp.json"),
    os.path.expanduser("~/.claude.json"),
    os.path.expanduser("~/.mcp.json"),
    os.path.expanduser(
        "~/Library/Application Support/Claude/claude_desktop_config.json"),
]


def has_kemory_key(node):
    """True if any server entry looks like Kemory and carries a key."""
    if not isinstance(node, dict):
        return False
    for name, cfg in node.items():
        if not isinstance(cfg, dict):
            continue
        blob = json.dumps(cfg).lower()
        looks_kemory = "kemory" in str(name).lower() or "kemory" in blob
        has_key = any(
            k.lower() in ("x-api-key", "authorization")
            for k in (cfg.get("headers") or {})
        ) or "kemory_api_key" in blob
        if looks_kemory and has_key:
            return True
    return False


for path in candidates:
    try:
        with open(path) as fh:
            data = json.load(fh)
    except Exception:
        continue
    servers = data.get("mcpServers") if isinstance(data, dict) else None
    if has_kemory_key(servers) or has_kemory_key(data):
        print(path)
        raise SystemExit(0)
    # Claude Code nests per-project config under "projects".
    for proj in (data.get("projects") or {}).values() if isinstance(data, dict) else []:
        if isinstance(proj, dict) and has_kemory_key(proj.get("mcpServers")):
            print(path)
            raise SystemExit(0)
raise SystemExit(1)
PY
}
