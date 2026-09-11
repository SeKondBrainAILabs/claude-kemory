---
name: kemory-setup
description: Get Kemory connected after installing the plugin, or diagnose it when the kemory_* tools are missing, the MCP server is unauthorised, or context injection is silent. Load when the user installs this plugin, asks how to set Kemory up, or reports that Kemory is not working.
---

# Connecting Kemory

Run `/kemory:status` first. It reports on both halves of the plugin and names
the specific failure; the steps below act on what it says.

## One variable turns on everything

The bundled MCP entry talks to hosted Kemory over HTTP and reads
`KEMORY_API_KEY` from the environment. The hooks read the same variable. So a
single export authenticates both halves, and there is nothing to install:

```bash
export KEMORY_API_KEY="..."   # from your Kemory dashboard
```

Put it somewhere your shell loads on startup, then restart the client fully —
closing the window is not enough.

If the variable is unset, Claude Code warns about the unexpanded
`${KEMORY_API_KEY}` and the server answers 401. That is the signal: the
credential is missing, not the server.

Self-hosted or community edition: set `KEMORY_URL` to your API base, no
trailing slash and no path. Both the MCP entry and the hooks honour it.

## If you would rather sign in with a browser

`kemory connect` writes its own MCP entry using the CLI's stored credentials,
so no key is ever written into a config file:

```bash
kemory login
kemory connect
```

Do that and **disable the bundled server** so two are not running. Run `/mcp`
to see what is actually connected. Note the hooks still need
`KEMORY_API_KEY` — they read the CLI credential file too, but only when one
exists for the environment you are on.

Getting the CLI is a separate step; the root README covers Homebrew and the
direct download.

## Why the tools can work while nothing else does

**A key inside an MCP config file authenticates the tools and is invisible to
the hooks.** They never read MCP config. That is the most common way to end up
with working `kemory_*` tools and no context injection. `/kemory:status`
detects it and says so — export the same key as `KEMORY_API_KEY` to fix it.

## Confirm, and know what silence means

Re-run `/kemory:status`. From the next session, namespace summaries are
injected at start and recalls get rated.

Every hook is best-effort by design: no credential, an unreachable server, or a
malformed transcript all exit cleanly. Nothing breaks, but nothing happens
either — so a quiet session is a setup problem, not a healthy one.

Before enabling session capture (`KEMORY_AUTO_CAPTURE=1`), read the Privacy
Policy in the plugin README. It uploads your own turns.
