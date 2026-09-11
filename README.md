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

**1. Install the plugin.**

```
/plugin marketplace add SeKondBrainAILabs/claude-kemory
```

```
/plugin install kemory@kemory
```

**2. Give it a credential.** Kemory has two halves that authenticate
*separately*: the `kemory_*` MCP **tools**, and the **hooks** that make the
agent actually use them.

*With the CLI* — one browser sign-in covers both:

```bash
kemory login
```

No keys to copy or paste. See
[Getting the CLI](#getting-the-cli-with-or-without-homebrew) — Homebrew is one
option, not a requirement.

*Without the CLI* — if you already reach Kemory through the connector, a custom
MCP endpoint, or self-hosted, you have the tools; give the hooks a key of their
own:

```bash
export KEMORY_API_KEY="..."   # from kemory.sekondbrain.ai
```

It must be an environment variable. **A key inside an MCP config file
authenticates the tools and is invisible to the hooks** — the most common way
to end up with working tools and nothing else. `/kemory:status` detects that
case and says so.

**3. Confirm it works.**

```
/kemory:status
```

From the next session your namespace summaries are injected automatically,
and recalls get rated so retrieval keeps improving.

<details>
<summary>Getting the CLI, with or without Homebrew</summary>

Homebrew is a convenience, not a requirement — the tap wraps prebuilt binaries
published on a GitHub release:

```bash
brew install sekondbrainailabs/s9n/kemory
```

Without Homebrew, take the binary directly. The archive is a bundle — a
`kemory` launcher beside an `_internal/` runtime directory — so extract it into
its own directory and link the launcher onto your `PATH`. Do **not** unpack it
straight into a `bin` directory; that scatters 200-plus runtime files across it.
Replace the platform with one of `macos-arm64`, `macos-x64`, `linux-arm64`,
`linux-x64`:

```bash
mkdir -p ~/.kemory/lib ~/.local/bin
curl -fsSL https://github.com/SeKondBrainAILabs/homebrew-s9n/releases/latest/download/kemory-macos-arm64.tar.gz \
  | tar -xz -C ~/.kemory/lib
ln -sf ~/.kemory/lib/kemory ~/.local/bin/kemory
kemory --version
```

Windows has a build too — `kemory-windows-x64.zip` on the same release.

**Supported platforms.** The CLI ships for macOS and Linux (arm64, x64) and
Windows x64. **The plugin's hooks are narrower:** they are `bash` scripts
calling `curl` and `python3`, so on Windows they need Git Bash or WSL. That
combination is untested, so Windows is not currently claimed for the hooks even
though the CLI runs there.

</details>

<details id="connecting-without-the-cli">
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
| prompt recall | `UserPromptSubmit` | Searches your vault with the prompt you just typed and injects what matches, so relevant history arrives without you asking for it |
| rate reminder | `PostToolUse` on Kemory recall tools | Prompts the agent to rate the memories it actually used, so recall quality improves instead of silently decaying |
| consolidate reminder | `SessionStart` after a compaction | Prompts the agent to store durable facts that would otherwise survive only as a summary |
| session capture | `Stop`, `SessionEnd` | **Opt-in.** Stores a bounded, redacted digest of what the session was about |

Plus `/kemory:status` for checking your setup, a `kemory` skill covering
how to recall, rate, store, and phrase memories so semantic search can find
them again, and a `kemory-setup` skill that walks the agent through connecting
Kemory when something is not working.

## Connecting Kemory

The plugin bundles a stdio MCP entry that runs `kemory mcp serve`, so it needs
the `kemory` binary on your `PATH` — without it that server fails to start and
the `kemory_*` tools never appear. If you connect another way — the hosted claude.ai
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

### Which surfaces this works on

Claude Code runs in four places, and the Quickstart above applies to three of
them: the **terminal**, the **Desktop app**, and the **IDE extensions**.

**Claude Code on the web** (`claude.ai/code`) is the exception. Per the Claude
Code docs, commands that only run in the terminal interface — `/plugin` among
them — aren't available in cloud sessions, so steps 1 and 2 above cannot be
run there. Whether a repo-committed `.claude/settings.json` can load the plugin
instead is untested; if you try it, note that `kemory login` won't work in a
cloud VM (no browser, and the VM is reclaimed on expiry), so the hooks would
need `KEMORY_API_KEY` set as a cloud-environment variable, and the
environment's network access would have to permit the Kemory API.

**claude.ai chat** has no plugin or hook system at all — use the Kemory
connector there for the memory tools.

## Privacy Policy

The plugin is a client. It sends data to one place: the Kemory instance you
point it at — [kemory.sekondbrain.ai](https://kemory.sekondbrain.ai) for the
hosted service, or your own host if you set `KEMORY_URL`. No telemetry, no
analytics, no third-party endpoint.

### What each hook sends

| Hook | Event | What leaves your machine | Default |
|------|-------|--------------------------|---------|
| context injection | `SessionStart` | Your credential only; reads your namespace summaries back | on |
| prompt recall | `UserPromptSubmit` | **The text of your prompt**, as a search query | on |
| recall approval | `PreToolUse` | Nothing — runs entirely locally | on |
| rate reminder | `PostToolUse` | Nothing — runs entirely locally | on |
| session capture | `Stop`, `SessionEnd` | Your own prompts: last 12 turns, 8000 characters max, redacted | **off** |

Prompt recall skips prompts under 12 characters and any prompt starting with
`/`, `!` or `#`, so slash commands are never sent. Separately, when a stored
OAuth token has expired the hooks refresh it against the identity provider
named in the CLI's own credential file.

### Turning transmission off

```bash
export KEMORY_PROMPT_RECALL=0   # stop sending prompt text
export KEMORY_AUTO_CAPTURE=0    # capture, already the default
```

With no credential configured at all, every hook no-ops and nothing is sent.

### Storage, retention and deletion

What you send is stored as memories in your own vault, scoped to your
organisation and user. Encryption at rest is **opt-in per account** and off
until you enable it. Memories persist until you remove them — there is no
automatic expiry unless you set a TTL when storing.

Removal comes at two levels, and the difference matters:

- `kemory_delete_memory` and `kemory_forget` are **soft deletes**. The memory
  stops being active and stops coming back in recall, but the row remains.
- `DELETE /api/v1/user/memory-data` is **irreversible erasure**: every memory
  for your user in that organisation, everything derived from them (session
  summaries, session digests, the consolidated namespace summary), and your
  memory encryption key along with it. If your vault was encrypted, destroying
  that key makes any ciphertext surviving in a backup permanently
  unrecoverable; if it was never encrypted, this is an ordinary hard delete.
  The response tells you which of the two you got.

### Who else can see it

Memories default to `user-private` and are isolated per organisation; nothing
crosses to another organisation. You can widen a memory to `team` or
`org-public` yourself.

The hosted service generates the namespace summaries that context injection
reads by sending memory content to a third-party model provider (currently
Groq). Embeddings are computed with a local model and do not leave the
service. On a self-hosted instance both are whatever you configured. The
hosted service's own terms govern its sub-processors; this plugin adds none.

One thing to be aware of: injected context becomes part of your Claude Code
conversation, so it reaches Anthropic on the same terms as anything else you
type there.

### Local files

`~/.kemory/.captured/` holds per-session digest hashes for de-duplication and
`~/.kemory/.setup-hint` holds a timestamp. Neither contains conversation
content. The plugin never writes credentials anywhere and never logs them.

### Contact

Privacy and data questions: **security@sekondbrain.ai**. Same address for
vulnerability reports — see [SECURITY.md](SECURITY.md).

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
├── skills/kemory/SKILL.md       using memory well
├── skills/setup/SKILL.md        connecting Kemory, and diagnosing it
└── scripts/{rate-reminder,capture}.sh
```

Apache-2.0. Kemory itself lives at [kemory.sekondbrain.ai](https://kemory.sekondbrain.ai);
the open-source server, MCP tools, and CLI are in
[kemory-community](https://github.com/SeKondBrainAILabs/kemory-community).
