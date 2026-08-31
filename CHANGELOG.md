# Changelog

All notable changes to this project are documented here. This project follows
[Semantic Versioning](https://semver.org/).

## [0.1.0] — Unreleased

Initial release. Claude Code only.

### Added
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
- `kemory` skill covering recall, rating, storing, and phrasing memories so
  semantic search can find them again.
- Bundled stdio MCP server entry for the Kemory CLI.
