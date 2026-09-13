#!/usr/bin/env python3
"""Assert the shape of the plugin's bundled MCP entry.

`plugin/.mcp.json` decides whether a user gets any memory tools. Nothing else
in this repo looks at it: on 2026-09-12 replacing it with a bogus endpoint and
an empty headers block passed all 85 tests, so a change that breaks every
install would go green through CI and fail only on the user's machine.

What is checked, and why each one matters:

  * valid JSON, one server named `kemory`  — a typo here removes the tools
  * `type: http`                           — the stdio bridge it replaced
                                             needed a binary on PATH
  * url ends `/mcp/v1`                     — the API answers 401 there and 404
                                             elsewhere, so a wrong path reads
                                             as an auth problem
  * url carries a `${KEMORY_URL:-...}`     — self-hosted users repoint the
    fallback                                 whole plugin with that one
                                             variable
  * `X-API-Key: ${KEMORY_API_KEY}`         — the hooks read the same variable;
                                             a literal key here would also be
                                             a committed secret
  * its default host equals the hooks'     — they authenticate separately, and
    default in lib.sh                        a drift sends the two halves to
                                             different servers

Prints a one-line summary and exits 0, or the reason and exits 1.
"""

from __future__ import annotations

import json
import pathlib
import re
import sys

ENTRY = pathlib.Path("plugin/.mcp.json")
LIB = pathlib.Path("plugin/scripts/lib.sh")

EXPECTED_KEY_REF = "${KEMORY_API_KEY}"
EXPECTED_PATH = "/mcp/v1"
# ${KEMORY_URL:-https://api.kemory.s9n.ai}/mcp/v1
URL_SHAPE = re.compile(r"^\$\{KEMORY_URL:-(?P<default>https://[^}/]+)\}(?P<path>/.*)$")
LIB_DEFAULT = re.compile(
    r'^KEMORY_DEFAULT_URL="\$\{KEMORY_DEFAULT_URL:-(?P<default>[^}]+)\}"', re.M
)


def fail(message: str) -> None:
    print(message)
    raise SystemExit(1)


def main() -> None:
    try:
        entry = json.loads(ENTRY.read_text())
    except FileNotFoundError:
        fail(f"{ENTRY} is missing")
    except json.JSONDecodeError as exc:
        fail(f"{ENTRY} is not valid JSON: {exc}")

    server = entry.get("kemory")
    if not isinstance(server, dict):
        fail(f"{ENTRY} has no 'kemory' server (found: {', '.join(entry) or 'nothing'})")

    transport = server.get("type")
    if transport != "http":
        fail(f"transport is {transport!r}, expected 'http'")

    url = server.get("url", "")
    shape = URL_SHAPE.match(url)
    if not shape:
        fail(
            f"url {url!r} is not ${{KEMORY_URL:-<https host>}}{EXPECTED_PATH} — "
            "without that fallback a self-hosted user cannot repoint the plugin"
        )
    if shape["path"] != EXPECTED_PATH:
        fail(f"url path is {shape['path']!r}, expected {EXPECTED_PATH!r}")

    headers = server.get("headers") or {}
    key_ref = headers.get("X-API-Key")
    if key_ref is None:
        fail(
            "no X-API-Key header — the API answers 401 and the user sees no tools "
            f"(headers: {', '.join(headers) or 'none'})"
        )
    if key_ref != EXPECTED_KEY_REF:
        fail(
            f"X-API-Key is {key_ref!r}, expected {EXPECTED_KEY_REF!r}. A literal key "
            "here would be a committed secret and would ignore the user's own."
        )

    lib_match = LIB_DEFAULT.search(LIB.read_text())
    if not lib_match:
        fail(f"could not read KEMORY_DEFAULT_URL from {LIB}")
    if lib_match["default"] != shape["default"]:
        fail(
            f"entry defaults to {shape['default']} but the hooks default to "
            f"{lib_match['default']} — the tools and the hooks would talk to "
            "different servers"
        )

    print(f"http {shape['default']}{EXPECTED_PATH}, key from KEMORY_API_KEY")


if __name__ == "__main__":
    main()
