# claude-kemory

Persistent, cross-session memory for Claude Code, powered by
[Kemory](https://kemory.sekondbrain.ai). Works with hosted Kemory and the
open-source [community edition](https://github.com/SeKondBrainAILabs/kemory-community)
— same wire protocol.

An MCP server gives an agent memory *tools*. This plugin makes it actually
use them: your context is injected at session start, recalls get rated so
retrieval improves instead of decaying, and durable facts get stored before
they are lost to compaction.

## Quickstart

**1. Install the Kemory CLI and sign in.**

```bash
brew install sekondbrainailabs/s9n/kemory
```

```bash
kemory login
```

Browser sign-in (OAuth 2.0 device flow) — no keys to copy or paste. This one
login gives the plugin everything it needs: the MCP bridge for memory tools,
and credentials the hooks read to inject your context and store facts.

**2. Install the plugin.**

```
/plugin marketplace add SeKondBrainAILabs/claude-kemory
```

```
/plugin install kemory@kemory
```

**3. Confirm it works.**

```
/kemory:status
```

From the next session your namespace summaries are injected automatically,
and recalls get rated so retrieval keeps improving.

<details>
<summary>Connecting without the CLI</summary>

**Already using the Kemory connector?** Adding *Kemory by SeKondBrain* in your
claude.ai connector settings gives you the memory tools over OAuth, everywhere
— web, mobile, desktop and Claude Code. Disable this plugin's bundled MCP
server so you do not run two: two servers means two copies of the same 28
tools in every request, and `/mcp` shows what is connected.

The hooks are separate from MCP — they call the API directly, so they need
their own credential. Without one they no-op silently, and you get the tools
and skill but no context injection and no capture. To enable them alongside
the connector, set a key from
[kemory.sekondbrain.ai](https://kemory.sekondbrain.ai):

```bash
export KEMORY_API_KEY="..."
```

**Self-hosted / community edition:**

```bash
git clone https://github.com/SeKondBrainAILabs/kemory-community.git
cd kemory-community && docker compose -f docker-compose.community.yml up -d --build
export KEMORY_URL=http://127.0.0.1:8111
export KEMORY_API_KEY=kemory-community-ci-key
```

`kemory login --local` skips OAuth and stores a machine-local API key for
this case. `KEMORY_URL` is honoured by both the hooks and the bundled MCP
bridge, so setting it points the whole plugin at your instance.

</details>

## What it does

| Hook | Event | Behaviour |
|------|-------|-----------|
| context injection | `SessionStart` | Injects your namespace summaries so the agent starts informed instead of blind, and warns once if Kemory isn't set up |
| rate reminder | `PostToolUse` on Kemory recall tools | Prompts the agent to rate the memories it actually used, so recall quality improves instead of silently decaying |
| consolidate reminder | `PreCompact` | Prompts the agent to store durable facts before context is summarised away |
| session capture | `SessionEnd` | **Opt-in.** Stores a bounded, redacted digest of what the session was about |

Plus `/kemory:status` for checking your setup, and a `kemory` skill covering
how to recall, rate, store, and phrase memories so semantic search can find
them again.

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

## Other agents

This repo is the **Claude Code** integration. Cursor and Codex have plugin
systems with hooks and would each get their own repo, but neither is built or
tested yet — the hook payloads, MCP tool naming, and plugin-root variables
differ, so support will be claimed once verified rather than assumed.

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

Apache-2.0. Kemory itself lives at [kemory.sekondbrain.ai](https://kemory.sekondbrain.ai);
the open-source server, MCP tools, and CLI are in
[kemory-community](https://github.com/SeKondBrainAILabs/kemory-community).
