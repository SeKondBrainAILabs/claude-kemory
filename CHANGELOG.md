# Changelog

All notable changes to this project are documented here. This project follows
[Semantic Versioning](https://semver.org/).

## [0.1.0] — 2026-08-31

Initial release. Claude Code only.

### Added
- Rate reminder now covers the whole recall family (`kemory_recall`,
  `kemory_ask`, `kemory_memory`, `kemory_find_similar`, `kemory_get_*`), not
  just `kemory_recall_memory` and `kemory_get_context`. It gates on a
  `recall_id` or a non-empty result list, so write calls never trigger it.
- Bundled MCP server runs the Kemory CLI's stdio bridge, so a single
  `kemory login` (OAuth browser sign-in) covers both the memory tools and the
  credentials the hooks need — no keys to copy or paste.
- 17 behavioural tests driving the real hook scripts, run by CI.
- `/kemory:status` slash command reporting credential, API, capture, and
  context-injection state, so users can tell whether the plugin is working.
- Client-side capture de-duplication: identical session digests are written
  once per session, since `SessionEnd` fires on exit, `/clear`, and resume.
- `SessionStart` hook that injects your Kemory namespace summaries into a new
  session, with a context budget, a namespace allowlist, and a once-a-day
  setup notice when Kemory is not configured yet.
- Shared credential resolver (`scripts/lib.sh`) supporting hosted bearer
  tokens and community-edition `X-API-Key`.
- `PostToolUse` hook reminding the agent to rate memories it actually used
  after a Kemory recall.
- `PreCompact` hook reminding the agent to consolidate before context is
  summarised away.
- `SessionEnd` hook that captures a bounded, redacted session digest
  (**opt-in**, off unless `KEMORY_AUTO_CAPTURE=1`).
- Hooks refuse to send credentials to a non-HTTP(S) URL.
- The rate reminder stays silent when a recall returned no memories.
- `kemory` skill covering recall, rating, storing, and phrasing memories so
  semantic search can find them again.
- Bundled stdio MCP server entry for the Kemory CLI.
