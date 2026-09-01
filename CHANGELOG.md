# Changelog

All notable changes to this project are documented here. This project follows
[Semantic Versioning](https://semver.org/).

## [0.2.2] — 2026-09-01

### Fixed
- **A credential written before the API host moved kept the old host forever,
  and `/kemory:status` reported it as a bare `HTTP 301`.** The hooks read
  `~/.kemory/credentials-<env>` directly, and that file stores the API host
  captured at login time — so changing the default only ever helped a fresh
  login. `https://kemory.prod.apps.s9n.ai` has since stopped serving the API: it
  redirects to the browser dashboard, which answers any API path with an SSO
  login redirect. The result on an affected machine was every hook silently
  failing and a status check printing a redirect code with no explanation.

  `lib.sh` now rewrites that one host, exact-match, to the current API host, so
  the hooks recover without a re-login — mirroring what the `kemory` CLI already
  does when it loads a credential. The rewrite is announced rather than silent:
  `/kemory:status` says which host your credential names and that
  `kemory login` updates the file itself.

- **A redirect from the API is now named instead of numbered.** Any 3xx reports
  that the endpoint is not an API host — typically a browser or SSO host, which
  redirects every path to login — and points at `kemory login` or `KEMORY_URL`.
  This applies to self-hosted instances behind an SSO proxy too, not just the
  retired host above.

## [0.2.1] — 2026-09-01

### Fixed
- **The consolidate reminder had never fired, on any version.** `PreCompact`
  does not accept `hookSpecificOutput.additionalContext` — the harness rejects
  the output with `Hook JSON output validation failed` and prints that error to
  the user on every compaction — while both READMEs advertised the feature.
  Third instance of the same root cause as 0.1.3 and 0.2.0: a hook written
  against an assumed payload contract.

  The hook is removed rather than repaired. Even with valid output `PreCompact`
  fires as compaction begins, so the model gets no turn to act on it. The nudge
  moved to `SessionStart` with `source=compact`, which fires after compaction
  and does accept `additionalContext`. It is emitted even when there are no
  namespace summaries to inject, since a compaction is worth consolidating
  either way.

### Added
- Captured `SessionStart`, `PreCompact` and `SessionEnd` payloads as fixtures,
  completing the set: every registered hook event now has a real payload behind
  it, and a test fails when one does not. The exemption list is empty.
  `PreCompact`'s fixture is kept although the event is no longer registered —
  it is the evidence for why.
- `session_title` and `source` are now known `SessionStart` fields; `source`
  was observed as `resume`. `PreCompact` carries `trigger` and
  `custom_instructions`; `SessionEnd` carries `reason`, seen as `other` on a
  normal exit.

## [0.2.0] — 2026-08-31

### Added
- **Prompt recall.** A `UserPromptSubmit` hook now searches Kemory with your
  prompt and injects the top matches, so recall happens on every substantive
  prompt instead of only when the agent thinks to spend a tool call on it.
  Default on; `KEMORY_PROMPT_RECALL=0` disables it. The query is redacted
  before it leaves the machine, and a memory injected once is not injected
  again in the same session.

  Known limitation: `POST /api/v1/memories/search` returns memory ids, not an
  invocation id, so hook-injected memories carry no `recall_id`. The agent is
  told to rate them by `memory_id`. They will not appear in recall *coverage*
  metrics, which join on recall ids.
- **Read-only auto-approval.** A `PreToolUse` hook approves read-only Kemory
  tools so recall no longer costs a permission prompt. Writes still ask. The
  gate is an explicit allowlist, never a regex over the tool family — see the
  fix below for why that distinction matters.
- The hooks manifest now records why the injection hooks must stay
  synchronous: an async hook's stdout is discarded, so an async SessionStart,
  UserPromptSubmit or PreToolUse would silently inject nothing while still
  appearing to run.
- Real captured payloads for `UserPromptSubmit`, `PreToolUse` and `Stop` as
  test fixtures, alongside the existing PostToolUse one.

### Changed
- **Capture is incremental and now also runs on `Stop`,** so a session that is
  killed or crashes still leaves its work behind rather than losing everything.
  Only new turns are posted: the marker at `~/.kemory/.captured/<session_id>`
  became `{"digest", "captured_turns"}`, a high-water mark. Without it the
  12-turn window would slide on every response and store a near-duplicate each
  time — the same defect class as 57d6e53. `KEMORY_CAPTURE_MIN_NEW_TURNS`
  (default 3) gates mid-session stores; `SessionEnd` flushes the remainder.
  Pre-0.2.0 markers are read and upgraded. Capture remains opt-in.
- Secret redaction moved to a single shared `plugin/scripts/redact.py` now that
  two hooks send text off the machine. Behaviour is unchanged and still pinned
  by the existing redaction tests.

### Fixed
- **The rate-reminder matcher matched a write.** `kemory_memory` is an alias of
  `kemory_store_memory` and requires `memory:write`, but the 0.1.3 matcher
  `kemory_(recall.*|ask|memory|find_similar|get_.*)` included it, so the plugin
  would have prompted the agent to rate memories after a *store*. It was silent
  in practice only because the script fails closed without a `recall_id`. Had
  that regex been reused for the new auto-approval hook, it would have
  auto-approved memory writes. A test now asserts the matcher rejects every
  write in the family.

## [0.1.3] — 2026-08-31

### Fixed
- **The rate reminder never worked for MCP tools.** A PostToolUse
  `tool_response` from an MCP server is a *list* of content blocks
  (`[{"type":"text","text":"<json>"}]`), not the payload object. The script
  only handled a dict or a JSON string, so on 0.1.0–0.1.1 it reported
  `recall_id=unknown` (useless for rating) and on 0.1.2, after the fail-closed
  change, it went silent entirely. It now unwraps the MCP envelope.
- Captured a real hook payload as `test/fixtures/posttooluse-mcp-recall.json`
  and test against it. Every prior synthetic shape was invented, and all of
  them passed while the real one produced nothing.

## [0.1.2] — 2026-08-31

### Fixed
- The "not configured yet" notice told users to run `kemory login` without
  saying how to obtain the CLI, so a new user's first contact with the plugin
  was a `command not found`. It now names the install command.
- `plugin/README.md` linked to a `#install` anchor that no longer existed.
- Stale header comment in `capture.sh` referencing the removed
  `TaskCompleted` hook.

### Added
- `NOTICE`, and the copyright holder filled into the Apache appendix.

## [0.1.1] — 2026-08-31

### Fixed
- The rate reminder only matched `kemory_recall_memory` and
  `kemory_get_context`, so it never fired for `kemory_recall` (an alias of the
  former), `kemory_ask`, `kemory_memory`, `kemory_find_similar` or the
  `kemory_get_*` family. Verified live: a `kemory_recall` returning two
  memories produced no reminder. The matcher now covers the recall family and
  gates on a `recall_id` or non-empty result list, so write calls never
  trigger it. Fails closed on unparseable input.

### Changed
- Sign-in leads with `kemory login` (OAuth device flow) instead of exporting
  a long-lived `KEMORY_API_KEY`; the bundled MCP server uses the CLI's stdio
  bridge so one login covers tools and hook credentials. Documents installing
  the CLI, which the README previously never mentioned.

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
