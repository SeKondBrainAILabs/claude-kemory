# Contributing

Thanks for helping improve the Kemory plugin.

## Ground rules

- Open an issue before a large change so we can agree on the approach.
- Keep hooks **best-effort**: a hook must never block or fail a user's
  session. Exit `0` on every error path.
- Keep the plugin **no-op safe**: if no Kemory server is connected, or the
  user has no credentials, nothing should error.
- Anything that sends data anywhere must be **opt-in and documented**.

## Before opening a PR

```bash
./scripts/check.sh
```

This validates every JSON manifest and shell script. CI runs the same script.

## Testing hooks locally

Pipe a synthetic payload into the script the way the harness would:

```bash
echo '{"tool_response":{"retrieval":{"recall_id":"rc_test"}}}' \
  | plugin/scripts/rate-reminder.sh
```

## Scope

This repo holds client-side integrations only. Server behaviour, MCP tool
definitions, and the CLI live in
[kemory-community](https://github.com/SeKondBrainAILabs/kemory-community).
