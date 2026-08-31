# Kemory plugin for Claude Code

Persistent, cross-session memory for Claude Code via
[Kemory](https://github.com/SeKondBrainAILabs/kemory-community). Works with
hosted Kemory and the open-source community edition (same wire protocol).

An MCP server gives an agent memory *tools*. This plugin makes it actually
use them well: rate what it recalls so retrieval improves, consolidate before
context is lost, and optionally capture what a session was about.

## Quickstart

**1. Get a Kemory backend.** Either sign in to hosted Kemory with the CLI:

```bash
kemory login
```

…or run the community edition locally:

```bash
git clone https://github.com/SeKondBrainAILabs/kemory-community.git
cd kemory-community && docker compose -f docker-compose.community.yml up -d --build
```

For the local stack, point the plugin at it:

```bash
export KEMORY_URL=http://127.0.0.1:8111
export KEMORY_API_KEY=kemory-community-ci-key
```

**2. Install the plugin.**

```
/plugin marketplace add SeKondBrainAILabs/kemory-plugins
```

```
/plugin install kemory@kemory-plugins
```

**3. Start a session.** Your namespace summaries are injected automatically.
If Kemory is not reachable, the plugin tells you once what to fix.

## What it does

| Hook | Event | Behaviour |
|------|-------|-----------|
| context injection | `SessionStart` | Injects your namespace summaries so the agent starts informed instead of blind, and warns once if Kemory isn't set up |
| rate reminder | `PostToolUse` on Kemory recall tools | Prompts the agent to rate the memories it actually used, so recall quality improves instead of silently decaying |
| consolidate reminder | `PreCompact` | Prompts the agent to store durable facts before context is summarised away |
| session capture | `SessionEnd` | **Opt-in.** Stores a bounded, redacted digest of what the session was about |

Plus a `kemory` skill covering how to recall, rate, store, and phrase
memories so semantic search can find them again.

## Connecting Kemory

The plugin bundles a stdio MCP entry that runs `kemory mcp serve`, which
covers CLI users. If you connect another way — the hosted claude.ai
connector, or a remote MCP endpoint at `https://<host>/mcp/v1` — disable the
bundled server so you are not running two. Run `/mcp` to see what is
connected.

Hooks authenticate independently of MCP: they use the CLI's stored
credentials, or `KEMORY_URL` with `KEMORY_TOKEN` (hosted) or `KEMORY_API_KEY`
(community edition).

If no Kemory server is connected, every hook no-ops rather than erroring.

## Session capture (opt-in)

Off unless you set it explicitly, because it uploads conversation content:

```bash
export KEMORY_AUTO_CAPTURE=1
```

Captures your own prompts only — assistant replies and tool output are
skipped — capped at the last 12 turns and 8000 characters, with common
secret patterns redacted. See [plugin/README.md](plugin/README.md) for all
configuration and [SECURITY.md](SECURITY.md) for what redaction does and
does not guarantee.

## Other platforms

Claude Code only for now. Cursor and Codex have plugin systems with hooks,
but this plugin has not been tested against them — the hook payloads, MCP
tool naming, and plugin-root variables differ, so support will be claimed
once it is verified rather than assumed.

Connector-only platforms (ChatGPT, Gemini, Perplexity) have no client-side
plugin or hook system at all; correct usage there is carried by the Kemory
MCP tool descriptions themselves.

## Development

```bash
./scripts/check.sh
```

Validates manifests, shell syntax, executable bits, plugin source paths,
hook script references, and that capture stays off by default. CI runs the
same script plus shellcheck.

## Layout

```
.claude-plugin/marketplace.json   marketplace manifest
plugin/
├── .claude-plugin/plugin.json
├── .mcp.json                     bundled stdio MCP server
├── hooks/hooks.json
├── skills/kemory/SKILL.md
└── scripts/{rate-reminder,capture}.sh
```

Apache-2.0. Server, MCP tools, and CLI live in
[kemory-community](https://github.com/SeKondBrainAILabs/kemory-community).
