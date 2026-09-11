---
name: kemory-setup
description: Get Kemory connected after installing the plugin, or diagnose it when the kemory_* tools are missing, the bundled MCP server fails to start, or context injection is silent. Load when the user installs this plugin, asks how to set Kemory up, or reports that Kemory is not working.
---

# Connecting Kemory

The plugin ships two halves that authenticate **separately**: the `kemory_*`
MCP tools, and the hooks that make the agent use them. One can work while the
other is dead, so check both.

Run `/kemory:status` first — it reports on both halves and names the specific
failure. Use the steps below to act on what it says.

## The bundled MCP server needs the CLI

`plugin/.mcp.json` runs `kemory mcp serve`. If the `kemory` binary is not on
`PATH`, that server fails to start and the `kemory_*` tools never appear.
Check with `command -v kemory`.

Two ways out — pick one:

**Install the CLI.** Homebrew wraps prebuilt binaries:

```bash
brew install sekondbrainailabs/s9n/kemory
```

Without Homebrew, take the binary from the same release. It is a bundle — a
`kemory` launcher beside an `_internal/` directory — so extract it into its own
directory rather than straight into a `bin`. Substitute `macos-arm64`,
`macos-x64`, `linux-arm64` or `linux-x64`:

```bash
mkdir -p ~/.kemory/lib ~/.local/bin
curl -fsSL https://github.com/SeKondBrainAILabs/homebrew-s9n/releases/latest/download/kemory-macos-arm64.tar.gz \
  | tar -xz -C ~/.kemory/lib
ln -sf ~/.kemory/lib/kemory ~/.local/bin/kemory
kemory --version
```

**Or reach Kemory another way** and disable the bundled server so two are not
running: the hosted claude.ai connector, or a remote MCP endpoint at
`https://<host>/mcp/v1`. Run `/mcp` to see what is actually connected.

## Then give the hooks a credential

With the CLI, one browser sign-in covers both halves:

```bash
kemory login
```

Without it, the hooks need an environment variable of their own:

```bash
export KEMORY_API_KEY="..."   # from kemory.sekondbrain.ai
```

**A key inside an MCP config file authenticates the tools and is invisible to
the hooks.** That is the most common way to end up with working tools and no
context injection. `/kemory:status` detects it and says so.

Self-hosted or community edition: set `KEMORY_URL` as well — both the hooks and
the bundled MCP bridge honour it.

## Confirm, and know what silence means

Re-run `/kemory:status`. From the next session, namespace summaries are
injected at start and recalls get rated.

Every hook is best-effort by design: no credential, an unreachable server, or a
malformed transcript all exit cleanly. Nothing breaks, but nothing happens
either — so a quiet session is a setup problem, not a healthy one.

Before enabling session capture (`KEMORY_AUTO_CAPTURE=1`), read the Privacy
Policy in the plugin README. It uploads your own turns.
