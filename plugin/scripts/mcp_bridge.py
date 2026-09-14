#!/usr/bin/env python3
"""Stdio MCP bridge: line-delimited JSON-RPC on stdin/stdout, HTTP to Kemory.

The fallback for a machine with a credential but no `kemory` binary. The CLI
ships a bridge of its own and `mcp.sh` prefers it; this exists so that dropping
the CLI dependency does not mean pinning the credential into a static header,
which is what made the bundled entry dead for CLI and connector users.

Reads KEMORY_BASE_URL and KEMORY_AUTH_HEADER from the environment — resolved by
lib.sh, the same function the hooks use, so both halves authenticate identically
and cannot drift apart.

Today's endpoint is stateless JSON — verified against the live API: `initialize`
answers 200 application/json and issues no `Mcp-Session-Id`. The transport
allows a server to start issuing one at any time, though, and a relay that
dropped it would break the moment that happened, in a way no test here would
catch. So the header is echoed back when the server sends one, and a 404 on a
session the server has since forgotten clears it rather than wedging every
later call. Same reason a text/event-stream reply is parsed: degrade to
working rather than to silence.

Every failure answers in-band as a JSON-RPC error. A bridge that dies on a bad
response leaves the host waiting on a request that can never complete.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

TIMEOUT = float(os.environ.get("KEMORY_MCP_TIMEOUT", "120"))
# -32603 is JSON-RPC "internal error": the request was well-formed and we could
# not answer it. Transport faults are ours, not the caller's.
INTERNAL_ERROR = -32603

# Set from the server's Mcp-Session-Id when it issues one, and sent on every
# later request. Module state because a bridge process serves exactly one
# client connection, which is what a session is scoped to.
_session_id: str | None = None


def _endpoint() -> str:
    base = (os.environ.get("KEMORY_BASE_URL") or "").rstrip("/")
    if not base:
        raise SystemExit("kemory: KEMORY_BASE_URL is empty — mcp.sh must set it")
    return base + "/mcp/v1"


def _headers() -> dict[str, str]:
    header = os.environ.get("KEMORY_AUTH_HEADER") or ""
    name, _, value = header.partition(":")
    if not (name and value.strip()):
        raise SystemExit("kemory: KEMORY_AUTH_HEADER is empty — mcp.sh must set it")
    return {
        name.strip(): value.strip(),
        "Content-Type": "application/json",
        # Both, so a server that prefers SSE still has a shape to choose.
        "Accept": "application/json, text/event-stream",
    }


def _parse(raw: bytes, content_type: str) -> dict | None:
    """Decode one response body, JSON or SSE."""
    text = raw.decode("utf-8", "replace").strip()
    if not text:
        return None
    if "text/event-stream" in content_type:
        # Take the last complete `data:` payload; earlier frames are progress.
        payload = None
        for line in text.splitlines():
            if line.startswith("data:"):
                chunk = line[5:].strip()
                if chunk and chunk != "[DONE]":
                    payload = chunk
        if payload is None:
            return None
        text = payload
    return json.loads(text)


def _error(request_id, message: str) -> dict:
    return {
        "jsonrpc": "2.0",
        "id": request_id,
        "error": {"code": INTERNAL_ERROR, "message": message},
    }


def _relay(endpoint: str, headers: dict[str, str], request: dict) -> dict | None:
    """POST one message. Returns the reply, or None when none is due."""
    global _session_id

    # A JSON-RPC notification has no `id` and takes no response. Answering one
    # is a protocol violation the host may drop the connection over.
    request_id = request.get("id")
    is_notification = "id" not in request

    sent = dict(headers)
    if _session_id:
        sent["Mcp-Session-Id"] = _session_id

    body = json.dumps(request).encode()
    req = urllib.request.Request(endpoint, data=body, headers=sent, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as response:
            issued = response.headers.get("Mcp-Session-Id")
            if issued:
                _session_id = issued
            status = response.status
            raw = response.read()
            content_type = response.headers.get("Content-Type", "")
    except urllib.error.HTTPError as exc:
        # 404 against a session id means the server has forgotten it. Dropping
        # it lets the next call start clean instead of failing forever.
        if exc.code == 404 and _session_id:
            _session_id = None
        if is_notification:
            return None
        detail = exc.read().decode("utf-8", "replace")[:200].strip()
        hint = ""
        if exc.code in (401, 403):
            hint = " — credential rejected; re-run 'kemory login' or check KEMORY_API_KEY"
        return _error(request_id, f"kemory API HTTP {exc.code}{hint}: {detail}")
    except Exception as exc:  # noqa: BLE001 — every transport fault answers in-band
        if is_notification:
            return None
        return _error(request_id, f"kemory API unreachable: {exc.__class__.__name__}: {exc}")

    if is_notification:
        return None
    # 202 Accepted is the transport's "received, nothing to return".
    if status == 202:
        return None
    try:
        parsed = _parse(raw, content_type)
    except ValueError as exc:
        return _error(request_id, f"kemory API sent a non-JSON reply: {exc}")
    if parsed is None:
        return _error(request_id, "kemory API sent an empty reply")
    return parsed


def main() -> None:
    endpoint = _endpoint()
    headers = _headers()

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except ValueError:
            # No id is recoverable from an unparseable line, so answer with the
            # null id the spec reserves for exactly this case.
            sys.stdout.write(json.dumps(_error(None, "invalid JSON from host")) + "\n")
            sys.stdout.flush()
            continue
        # A batch is a list; relay each member and answer with the replies due.
        if isinstance(request, list):
            replies = [r for r in (_relay(endpoint, headers, m) for m in request) if r]
            if replies:
                sys.stdout.write(json.dumps(replies) + "\n")
                sys.stdout.flush()
            continue
        reply = _relay(endpoint, headers, request)
        if reply is not None:
            sys.stdout.write(json.dumps(reply) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    try:
        main()
    except (BrokenPipeError, KeyboardInterrupt):
        # The host closed the connection. Not an error worth a traceback.
        pass
