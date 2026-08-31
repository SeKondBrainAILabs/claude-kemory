# Kemory plugin

Hooks and a skill that make Claude Code use Kemory memory well.

## What it does

| Hook | Event | Behaviour |
|------|-------|-----------|
| `session-start.sh` | `SessionStart` | Injects your Kemory namespace summaries so the session starts informed, and warns once if Kemory isn't configured yet |
| `rate-reminder.sh` | `PostToolUse` on kemory recall tools | Reminds the agent to rate memories it actually used, so recall quality improves over time |
| inline | `PreCompact` | Reminds the agent to consolidate before context is summarised away |
| `capture.sh` | `SessionEnd` | **Opt-in.** Stores a bounded, redacted digest of the session as an episodic memory |

Plus a `kemory` skill covering how to recall, rate, store, and phrase memories
so semantic search can find them again.

## Install

See the [root README](../README.md#install) for the install commands.

## Connecting Kemory

The plugin bundles a stdio MCP entry that runs `kemory mcp serve`, so
self-hosted and community-edition users need only `kemory login`. If you
connect through the hosted claude.ai connector or a remote MCP endpoint
(`https://<host>/mcp/v1`), disable the bundled server so you do not run two.

If no Kemory server is connected, every hook no-ops rather than erroring.

## Session context injection

On every session start the plugin fetches your namespace summaries and injects
them, so the agent begins knowing your preferences and project context instead
of starting blind.

| Variable | Default | Meaning |
|----------|---------|---------|
| `KEMORY_CONTEXT` | `1` | Set to `0` to disable injection |
| `KEMORY_CONTEXT_DEPTH` | `l3` | Summary depth requested (`l3`, `l4`) |
| `KEMORY_CONTEXT_MAX_CHARS` | `4000` | Context budget; summaries beyond it are dropped with a note (floor 500) |
| `KEMORY_CONTEXT_NAMESPACES` | all | Comma-separated allowlist, e.g. `user:preferences,shared` |
| `KEMORY_CONTEXT_TIMEOUT` | `6` | Seconds to wait for the API |
| `KEMORY_QUIET_SETUP` | `0` | Set to `1` to suppress the "not configured yet" notice |

If Kemory is not configured, the hook prints one short setup notice and then
stays quiet for 24 hours rather than nagging every session.

## Automatic session capture (opt-in)

Capture is **off** unless you set it explicitly, because it uploads
conversation content to your kemory instance:

```bash
export KEMORY_AUTO_CAPTURE=1
```

| Variable | Default | Meaning |
|----------|---------|---------|
| `KEMORY_AUTO_CAPTURE` | `0` | Set to `1` to enable capture |
| `KEMORY_CAPTURE_NAMESPACE` | `shared` | Namespace to write digests to |
| `KEMORY_CAPTURE_MAX_TURNS` | `12` | How many recent user turns to include |
| `KEMORY_CAPTURE_SOURCE` | `claude-code` | Value recorded in the memory's `metadata.source` |
| `KEMORY_ENV` | `prod` | Which credentials file to read |
| `KEMORY_URL` | — | Kemory base URL — only needed if you have no CLI credentials |
| `KEMORY_TOKEN` | — | Bearer token (hosted Kemory) |
| `KEMORY_API_KEY` | — | API key (community edition, sent as `X-API-Key`) |

All hooks that reach the API share one credential resolver
(`scripts/lib.sh`): the CLI's `~/.kemory/credentials` if present, otherwise
`KEMORY_URL` plus either `KEMORY_TOKEN` (hosted, sent as a bearer token) or
`KEMORY_API_KEY` (community edition, sent as `X-API-Key`). With none of
those, every hook stays silent.

What is captured: your own turns only (assistant replies and tool output are
skipped), capped at the last N turns and 8000 characters, with common secret
patterns redacted. Digests are written to `POST /api/v1/memories` tagged
`session-capture` and carry the `session_id` so the server-side Reflector can
consolidate them into semantic summaries.

`SessionEnd` fires on exit, `/clear`, and resume, so the same turns can be
offered more than once. The hook stores a hash of each digest under
`~/.kemory/.captured/<session_id>` and skips a write whose content it has
already stored, so repeats do not accumulate duplicate memories. The hash is
recorded only after the write succeeds.

Redaction is pattern-based, so treat it as a safety net rather than a
guarantee. If you work with sensitive material, leave capture off.

Every hook is best-effort: missing credentials, an unreachable server, or a
malformed transcript all exit cleanly and never block a session.
