# kemory-plugin

The Kemory plugin for **Claude Code**. Persistent, cross-session memory, powered by
[Kemory](https://kemory.sekondbrain.ai). Works with hosted Kemory and the
open-source [community edition](https://github.com/SeKondBrainAILabs/kemory-community).

An MCP server gives an agent memory *tools*. This plugin makes it actually use
them: relevant memories arrive under every prompt, a turn that settles
something durable does not end with it unwritten, recalls get rated so
retrieval improves instead of decaying, and nothing is sent that you did not
turn on.

## Features

- **Standing instruction** — ships with the plugin, so there is nothing to
  paste into `CLAUDE.md` and nothing to keep in sync per project
- **Prompt recall** — every prompt is searched against your vault and the
  matches arrive before the agent answers, without it deciding to look
- **Store nudge** — *opt-in.* When a turn reached a decision and stored
  nothing, the turn does not just end
- **Context injection** — your namespace summaries load at session start
- **Rate reminder** — the agent rates the memories it used, so retrieval keeps
  improving
- **Session capture** — *opt-in.* A bounded, redacted digest of what the
  session was about, stored at the end
- **`/kemory:status`** — one command that says what is and is not working

## Install

Inside Claude Code:

```
/plugin marketplace add SeKondBrainAILabs/kemory-plugin
/plugin install kemory@kemory
/kemory:login
```

`/kemory:login` prints one link. Open it, approve in the browser, and the
credential is written for you — nothing to install, nothing to paste. Restart
Claude Code fully, then run `/kemory:status`.

It signs you in the same way the Kemory CLI does and writes the same file, so
if you install the CLI later it finds you already signed in.

<details>
<summary>Already reach Kemory another way?</summary>

| You have | Do this |
|----------|---------|
| The Kemory CLI, signed in with `kemory login` | Nothing at all — that is the same credential `/kemory:login` writes, and both halves read it. `kemory connect` is only needed for other MCP hosts. |
| The claude.ai Kemory connector | Tools already work; disable the bundled entry under `/mcp` so you are not running two. The hooks still need `export KEMORY_API_KEY="..."` — the connector's OAuth token lives inside Claude and a shell script cannot read it. |
| A self-hosted or community instance | `export KEMORY_URL=http://...` alongside `KEMORY_API_KEY`. One URL moves the whole plugin. |

CLI install and sign-in: [docs.sekondbrain.ai/kemory/cli](https://docs.sekondbrain.ai/kemory/cli/).
The hooks are `bash` scripts calling `curl` and `python3`; on Windows they need
Git Bash or WSL, which is untested.

</details>

Works in the terminal, the Desktop app and the IDE extensions. Claude Code on
the web has no `/plugin` command, and claude.ai chat has no hooks at all — use
the Kemory connector there.

## Staying current

Plugins do not update themselves; an install keeps the hook set from the day
you ran it.

```
/plugin update kemory@kemory
```

Restart Claude Code afterwards to load the new hooks. `/kemory:status` prints
the version you are on, and [CHANGELOG.md](CHANGELOG.md) says what moved.

## How it works

| Hook | When | What it does | Leaves your machine | Default |
|------|------|--------------|---------------------|---------|
| context injection | `SessionStart` | Injects your namespace summaries; warns once if Kemory isn't set up | Your credential; reads summaries back | on |
| prompt recall | `UserPromptSubmit` | Searches your vault with the prompt you typed and injects what matches | **The text of your prompt** | on |
| recall approval | `PreToolUse` | Auto-approves Kemory read tools so memory stops interrupting you | Nothing | on |
| rate reminder | `PostToolUse` | Prompts the agent to rate the memories it actually used | Nothing | on |
| consolidate reminder | `SessionStart` after compaction | Prompts the agent to store facts that would otherwise survive only as a summary | Nothing | on |
| store nudge | `Stop` | When the turn settled something durable and no Kemory write happened, asks for it before the turn ends | Nothing | **off** |
| session capture | `Stop`, `SessionEnd` | Stores a redacted digest of your own prompts: last 12 turns, 8000 characters | Your prompts, redacted | **off** |

If you pasted the instruction into `CLAUDE.md` before the plugin shipped one,
you can delete it — the plugin says so once a week until you do. Keeping both
is not harmful, but the pasted copy asks the agent to open each session with
`kemory_list_namespaces` and a recall, which the prompt-recall hook has already
done by then.

The instruction is injected on every session, including a brand-new vault and
a session whose context call failed. It is short on purpose: recall and the
write prompt are hooks now, so it says only what no hook can — what Kemory is,
and the standard for writing to it.

Plus a `kemory` skill on how to recall, rate, store and phrase memories so
semantic search finds them again, and a `kemory-setup` skill that walks the
agent through connecting Kemory when something is not working.

With no credential configured, every hook no-ops and nothing is sent.

## Privacy Policy

The plugin is a client. It sends data to one place — the Kemory instance you
point it at — and adds no telemetry, analytics or endpoint of its own. Prompt
recall skips prompts under 12 characters and anything starting with `/`, `!`
or `#`.

```bash
export KEMORY_PROMPT_RECALL=0   # stop sending prompt text
export KEMORY_AUTO_CAPTURE=1    # turn capture on (off by default)
export KEMORY_STORE_NUDGE=1     # turn the store nudge on (off by default)
```

The store nudge reads your transcript on this machine and sends nothing. It is
off by default anyway: a hook that continues a turn is disruptive when it is
wrong, so it ships off until the false-positive rate has been measured on real
sessions.

Storage, retention, deletion, sub-processors and who else can see a memory:
[PRIVACY.md](PRIVACY.md). The service itself is governed by the
[SeKondBrain Privacy Policy](https://docs.sekondbrain.ai/legal/privacy/).

## Configuration

Every knob — recall limits and relevance floor, context depth and budget,
capture window and namespace, `KEMORY_URL`, `KEMORY_ENV` — is documented in
[plugin/README.md](plugin/README.md). [SECURITY.md](SECURITY.md) covers what
redaction does and does not guarantee.

## Development

```bash
./scripts/check.sh
```

Validates manifests, shell syntax, executable bits, plugin source paths, hook
script references, and that capture stays off by default. CI runs the same
script plus shellcheck. See [CONTRIBUTING.md](CONTRIBUTING.md).

```
plugin/
├── .claude-plugin/plugin.json
├── .mcp.json                     bundled MCP entry → scripts/mcp.sh
├── hooks/hooks.json
├── commands/status.md            /kemory:status
├── skills/                       kemory, setup
└── scripts/                      one script per hook, plus lib and redact
```

Everything here is the Claude Code integration; plugins for other hosts will
live alongside it rather than in repositories of their own. Apache-2.0. The
open-source server, MCP tools and CLI are in
[kemory-community](https://github.com/SeKondBrainAILabs/kemory-community).
