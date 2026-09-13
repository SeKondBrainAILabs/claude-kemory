# claude-kemory

Persistent, cross-session memory for Claude Code, powered by
[Kemory](https://kemory.sekondbrain.ai). Works with hosted Kemory and the
open-source [community edition](https://github.com/SeKondBrainAILabs/kemory-community)
— same wire protocol.

An MCP server gives an agent memory *tools*. This plugin makes it actually use
them: relevant memories are injected on every prompt, recalls get rated so
retrieval improves instead of decaying, and a session digest can be stored
automatically.

## Features

- **Prompt recall** — every prompt is searched against your vault and the
  matches arrive before the agent answers, without it deciding to look
- **Context injection** — your namespace summaries load at session start
- **Rate reminder** — the agent rates the memories it used, so retrieval keeps
  improving
- **Session capture** — *opt-in.* A bounded, redacted digest of what the
  session was about, stored at the end
- **`/kemory:status`** — one command that says what is and is not working

## Install

```
/plugin marketplace add SeKondBrainAILabs/claude-kemory
/plugin install kemory@kemory
```

Then give it a credential. What that means depends on how you already reach
Kemory:

| You have | Do this |
|----------|---------|
| Nothing yet | `export KEMORY_API_KEY="..."` in your shell profile — key from [kemory.sekondbrain.ai](https://kemory.sekondbrain.ai). The bundled MCP entry and the hooks both read it. |
| The Kemory CLI, signed in with `kemory login` | Nothing for the hooks — they read the CLI's stored credentials. Run `kemory connect` to write the tools' MCP entry, then disable this plugin's bundled one under `/mcp` so you are not running two. |
| The claude.ai Kemory connector | Tools already work. The hooks still need `export KEMORY_API_KEY="..."` — the connector's OAuth token lives inside Claude and a shell script cannot read it. Disable the bundled entry under `/mcp`. |
| A self-hosted or community instance | `export KEMORY_URL=http://...` alongside `KEMORY_API_KEY`. One URL moves the whole plugin. |

Restart Claude Code fully, then:

```
/kemory:status
```

The key must be an environment **variable**. A key inside an MCP config file
authenticates the *tools* and is invisible to the *hooks* — the most common way
to end up with working tools and nothing else. `/kemory:status` detects that
case and says so.

Installing and signing in with the CLI:
[docs.sekondbrain.ai/kemory/cli](https://docs.sekondbrain.ai/kemory/cli/).
Running your own instance: [kemory-community](https://github.com/SeKondBrainAILabs/kemory-community).
The hooks are `bash` scripts calling `curl` and `python3`; on Windows they need
Git Bash or WSL, which is untested, so Windows is not claimed for the hooks even
though the CLI runs there.

## Staying current

Plugins do not update themselves. What you installed is a snapshot, and this
plugin's behaviour lives in its hooks — leave an install alone and it keeps
running the hook set from the day you ran it, however much has been fixed since.

```
/plugin update kemory@kemory
```

It refreshes the marketplace on the way through, so that is the whole command.
Restart Claude Code afterwards to load the new hooks; the update does not apply
them to a running session. `/kemory:status` prints the version you are on, and
[CHANGELOG.md](CHANGELOG.md) says what moved.

## How it works

| Hook | Event | Behaviour |
|------|-------|-----------|
| context injection | `SessionStart` | Injects your namespace summaries so the agent starts informed instead of blind, and warns once if Kemory isn't set up |
| prompt recall | `UserPromptSubmit` | Searches your vault with the prompt you just typed and injects what matches, so relevant history arrives without you asking for it |
| recall approval | `PreToolUse` on Kemory read tools | Auto-approves reads, so memory stops being the thing that interrupts you |
| rate reminder | `PostToolUse` on Kemory recall tools | Prompts the agent to rate the memories it actually used, so recall quality improves instead of silently decaying |
| consolidate reminder | `SessionStart` after a compaction | Prompts the agent to store durable facts that would otherwise survive only as a summary |
| session capture | `Stop`, `SessionEnd` | **Opt-in.** Stores a bounded, redacted digest of what the session was about |

Plus a `kemory` skill covering how to recall, rate, store, and phrase memories
so semantic search can find them again, and a `kemory-setup` skill that walks
the agent through connecting Kemory when something is not working.

The hooks never read MCP config. They take `KEMORY_API_KEY` or `KEMORY_TOKEN`
from the environment, or the CLI's stored credentials, against `KEMORY_URL`
(default: hosted Kemory). With no credential at all, every hook no-ops rather
than erroring.

## Configuration

Session capture is off unless you set it, because it uploads conversation
content:

```bash
export KEMORY_AUTO_CAPTURE=1
```

It captures your own prompts only — assistant replies and tool output are
skipped — capped at the last 12 turns and 8000 characters, with common secret
patterns redacted. Every other knob (`KEMORY_PROMPT_RECALL`, capture window,
namespaces, `KEMORY_ENV`) is in [plugin/README.md](plugin/README.md);
[SECURITY.md](SECURITY.md) covers what redaction does and does not guarantee.

## Which surfaces this works on

Claude Code runs in four places, and the install above applies to three of
them: the **terminal**, the **Desktop app**, and the **IDE extensions**.

**Claude Code on the web** (`claude.ai/code`) is the exception. Per the Claude
Code docs, commands that only run in the terminal interface — `/plugin` among
them — aren't available in cloud sessions, so the install cannot be run there.
Whether a repo-committed `.claude/settings.json` can load the plugin instead is
untested; if you try it, note that `kemory login` won't work in a cloud VM (no
browser, and the VM is reclaimed on expiry), so the hooks would need
`KEMORY_API_KEY` set as a cloud-environment variable, and the environment's
network access would have to permit the Kemory API.

**claude.ai chat** has no plugin or hook system at all — use the Kemory
connector there for the memory tools.

## Privacy Policy

The service is governed by the
[SeKondBrain Privacy Policy](https://docs.sekondbrain.ai/legal/privacy/) and
its [sub-processor list](https://docs.sekondbrain.ai/subprocessors/). This
section covers the part that policy cannot: what *this plugin* transmits from
your machine, and when.

The plugin is a client. It sends data to one place — the Kemory instance you
point it at, hosted or your own via `KEMORY_URL`. It adds no telemetry, no
analytics and no third-party endpoint of its own.

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

The hosted service builds the namespace summaries that context injection reads
by sending memory content to an LLM sub-processor — Groq and OpenRunner are
the ones currently
[listed](https://docs.sekondbrain.ai/subprocessors/). Embeddings are computed
with a local model and do not leave the service. On a self-hosted instance
both are whatever you configured. The plugin itself adds no sub-processor.

One thing to be aware of: injected context becomes part of your Claude Code
conversation, so it reaches Anthropic on the same terms as anything else you
type there.

### Local files

`~/.kemory/.captured/` holds per-session digest hashes for de-duplication and
`~/.kemory/.setup-hint` holds a timestamp. Neither contains conversation
content. The plugin never writes credentials anywhere and never logs them.

### Contact

Privacy and data questions: **privacy@sekondbrain.ai**, the contact named in
the [published policy](https://docs.sekondbrain.ai/legal/privacy/).
Vulnerabilities go to **security@sekondbrain.ai** — see
[SECURITY.md](SECURITY.md).

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
├── .mcp.json                     bundled HTTP MCP entry
├── hooks/hooks.json
├── commands/status.md            /kemory:status
├── skills/kemory/SKILL.md        using memory well
├── skills/setup/SKILL.md         connecting Kemory, and diagnosing it
└── scripts/                      session-start, prompt-recall, recall-approve,
                                  rate-reminder, capture, status, lib, redact
```

Apache-2.0. Kemory itself lives at [kemory.sekondbrain.ai](https://kemory.sekondbrain.ai);
the open-source server, MCP tools, and CLI are in
[kemory-community](https://github.com/SeKondBrainAILabs/kemory-community).
