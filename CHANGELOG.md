# Changelog

All notable changes to this project are documented here. This project follows
[Semantic Versioning](https://semver.org/).

## [0.3.0] — 2026-09-14

### Added
- **The standing instruction ships with the plugin.** Until now the plugin
  made an agent *read* memory but left *writing* to a paragraph the user had
  to paste into `CLAUDE.md` themselves — per-machine, per-repo, silently
  absent in a new project, and drifting from the docs the day either changed.
  `session-start.sh` now injects it on every session, including a brand-new
  vault, an unreachable API and a user with no hook credential; those paths
  previously returned nothing at all. It is deliberately short: recall and the
  write prompt are mechanisms now, so it states only what no hook can.
- **Store nudge (`KEMORY_STORE_NUDGE=1`, off by default).** A `Stop` hook that
  fires when a turn settled something durable and no Kemory write happened,
  asking for the write before the turn ends. This is the only thing in the
  plugin that makes a write *happen* rather than hoping for one. It emits
  `hookSpecificOutput.additionalContext`, not `decision: "block"` — the hooks
  reference says both run the same continuation loop and the same loop
  protections, but the former is shown as hook feedback rather than a hook
  error, which is what guidance should look like. Gated on decision-shaped
  phrasing, silent when the turn already stored, and once per turn.

### Notes
- Off by default for one release. A hook that continues a turn is disruptive
  when it is wrong, so the false-positive rate gets measured on real sessions
  before it is considered for on-by-default.
## [0.2.10] — 2026-09-14

### Fixed
- **The privacy policy named a sub-processor that does not exist.** It said
  memory content reaches Groq and OpenRunner. OpenRunner is not a
  sub-processor and never was: it appears nowhere in the platform — no client,
  no base URL, no API key in any environment — and its entry on the public
  list came from an early drafting note. The claim was added in 0.2.8 by
  reading that list rather than the code, in the same pass that corrected
  three other privacy statements by checking them against the backend.

  Now names Groq, which is what the code shows on these paths, and defers to
  the [sub-processor list](https://docs.sekondbrain.ai/subprocessors/) as the
  authoritative record instead of restating a snapshot of it. A copied list
  goes stale, which is how this happened.

## [0.2.9] — 2026-09-13

The repo went public for the plugin directory, which does not accept
closed-source plugins. Most of this release is the consequence of being read
by strangers rather than by the people who wrote it.

### Added
- **`PRIVACY.md`.** The per-hook detail — what leaves your machine, how to
  switch each transmission off, retention, deletion, who can see what, the
  local files — now has its own document instead of being a section most
  readers scrolled past.
- **`check.sh` asserts the bundled MCP entry.** `plugin/.mcp.json` decides
  whether a user gets any memory tools, and nothing tested it: replacing it
  with a bogus endpoint and an empty headers block passed the whole suite. The
  check covers transport, path, the `${KEMORY_URL:-…}` fallback self-hosted
  users depend on, an `X-API-Key` that references the variable rather than
  carrying a literal key, and agreement with the hooks' own default host —
  the two halves authenticate separately and would otherwise drift onto
  different servers.
- **`check.sh` fails on internal tracker ids and Notion links** in tracked
  files. `release.yml` copies the changelog verbatim into a published release,
  so a pasted ticket reference reaches the public by itself.

### Changed
- **The README is a landing page.** It had grown into the whole manual. Install
  now branches on the four ways you can already be reaching Kemory, because the
  previous version presented `KEMORY_API_KEY` as universal — wrong for anyone
  signed in with `kemory login`, and wrong in the other direction for a
  connector user who has tools but no hook credential. CLI installation defers
  to the docs rather than being re-explained.
- **Says how to keep the plugin current**, which nothing did.

## [0.2.8] — 2026-09-11

Closes the gaps that would have failed a Claude plugin directory review.

### Added
- **A Privacy Policy, which the directory rejects submissions for lacking.**
  States per hook what leaves the machine, where it goes, how to switch each
  transmission off, how long content is kept and how to delete it, who can see
  it, what is written locally, and a contact address.
- **A `kemory-setup` skill.** Walks the agent through getting connected: the one
  environment variable that authenticates both halves, the browser-login route
  for anyone who would rather not hold a key, and what a silent session means.

### Changed
- **The bundled MCP entry is now an HTTP connection, not a stdio binary.** It
  was `kemory mcp serve`, which needs the CLI on `PATH` — so on a machine
  without it the server failed to start and the `kemory_*` tools never
  appeared. It is now
  `${KEMORY_URL:-https://api.kemory.s9n.ai}/mcp/v1` with `KEMORY_API_KEY` as
  `X-API-Key`, which is what the Kemory docs have always told people to paste
  by hand. Nothing to install, and because the hooks already read
  `KEMORY_API_KEY`, one export now turns on both halves instead of two
  credentials doing one job each. `kemory login` plus `kemory connect` remains
  the browser-login path; disable the bundled server if you use it.
- **`api.kemory.s9n.ai` is the canonical API host.** The default was
  `api.kemory.sekondbrain.ai` while the credential-retargeting path in
  `lib.sh` already rewrote retired hosts *to* `api.kemory.s9n.ai`. Aligned.

### Fixed
- **Prompt recall was undocumented in the capability table** despite being on by
  default and sending the text of every prompt to the search endpoint. It is now
  listed alongside the other hooks, in both the table and the privacy policy.
- **The bundled MCP server's dependency on the CLI is now stated** rather than
  implied by "covers CLI users".

## [0.2.7] — 2026-09-01

### Added
- **Which Claude surfaces this works on, stated for the first time.** The
  Quickstart applies to the terminal, the Desktop app and the IDE extensions.
  It does **not** work in **Claude Code on the web**: per the Claude Code docs,
  commands that only run in the terminal interface — `/plugin` among them —
  aren't available in cloud sessions, so `/plugin marketplace add` and
  `/plugin install` cannot be run there. Whether a repo-committed
  `.claude/settings.json` loads the plugin instead is untested and documented
  as such, along with the two conditions that would apply anyway: `kemory login`
  cannot work in a cloud VM, and the environment's egress would have to permit
  the Kemory API. **claude.ai chat** has no plugin or hook system at all and is
  connector-only.

## [0.2.6] — 2026-09-01

Two defects found by actually walking the install on a machine with no CLI and
an empty `$HOME`, rather than reasoning about it.

### Fixed
- **The README's non-Homebrew install command would have scattered a Python
  runtime across the user's `bin` directory.** The release archive is a bundle —
  a `kemory` launcher beside an `_internal/` runtime tree, 223 files — so
  `tar -xz -C ~/.local/bin` unpacks all of it into a `PATH` directory. Corrected
  to extract into `~/.kemory/lib` and symlink the launcher, which is what the
  s9n installer does and what actually works (verified: `kemory, version 0.6.7`
  from the symlink).
- **The setup notice and `/kemory:status` recommended `kemory login` on machines
  with no `kemory` binary,** and gave no way to obtain one. Both are now
  CLI-aware: without the CLI they lead with `KEMORY_API_KEY` — the remedy that
  needs no install — and mention the CLI as something to install first. With
  the CLI present the wording is unchanged.

## [0.2.5] — 2026-09-01

### Fixed
- **The 0.2.4 README claimed there is no Windows build. There is.**
  `kemory-windows-x64.zip` ships on the same release as the macOS and Linux
  tarballs. The claim came from reading the Homebrew formula, which has only
  `on_macos` and `on_linux` blocks — a source that structurally cannot express
  a Windows build was treated as evidence one does not exist. Same error class
  as the payload-shape defects in 0.1.3 and 0.2.1: inferring absence from a
  source that cannot represent presence.

  The real limit is narrower and still worth stating: the **hooks** are `bash`
  scripts calling `curl` and `python3`, so on Windows they need Git Bash or
  WSL, which is untested. The CLI runs on Windows; the hooks are unproven
  there.
- Removed a duplicated Quickstart in `README.md`, left by the 0.2.4 rebase
  against the two credential PRs.

## [0.2.4] — 2026-09-01

Four ways a user could believe the plugin was working while the hooks were
inert, and one install story that excluded people for no reason.

### Fixed
- **Expired tokens are now refreshed.** The credential file has carried
  `expires_at` and `refresh_token` all along, but `lib.sh` read `access_token`
  and nothing else — so once it expired, every hook 401'd and no-op'd with no
  notice at all, because the setup hint only fires when no credential file
  exists and a stale one does. Refresh is best-effort against the stored
  issuer, written back atomically at `0600`. A refresh that fails is reported
  as expired rather than silently retried forever.
- **The setup notice no longer claims nothing is configured.** It said "no
  memory backend configured yet" and pointed at `brew install` — wrong, and
  actively misleading, for anyone whose MCP tools were already working through
  a connector. It now says the *hooks* have no credential, notes the tools
  authenticate separately, and names both remedies.
- **A key in an MCP config is detected and explained.** Our own docs tell
  Claude Code users to put the API key in an `X-API-Key` header inside the MCP
  config file — where the hooks cannot see it, since they read the environment
  or the CLI credential file. The most likely path to working tools and inert
  hooks. `/kemory:status` and the setup notice now name the file and say to
  export the same key. Detection only: the key itself is never read out or
  echoed, because harvesting a credential from another tool's config is not a
  habit to build in.

### Changed
- **`/kemory:status` reports the two axes separately** — HOOKS and TOOLS — since
  one combined verdict is how a user concludes the plugin works when half of it
  is doing nothing.
- **Homebrew is no longer the headline.** The tap wraps four prebuilt tarballs
  on a GitHub release; the README now gives the direct `curl` for people
  without Homebrew, and the plugin install comes first, before any credential
  step. Supported platforms are stated for the first time: macOS and Linux on
  arm64/x64, no Windows build, hooks needing `bash`/`curl`/`python3`.
## [0.2.3] — 2026-09-01

### Fixed
- **A keyed setup got told to run a command it does not have.** Without the CLI
  there is no credentials file: the API host comes from `KEMORY_URL`, so it
  reaches a superseded host by a different route than a stale credential. The
  0.2.2 rewrite already covered that path, but `/kemory:status` offered
  `kemory login` as the remedy — not a command a connector or community-edition
  user has installed. It now picks the remedy from where the host actually came
  from, and both paths are pinned by tests.

### Changed
- The Quickstart names both credential routes at step 1. Installing the CLI was
  step 1 with the keyed route collapsed in a `<details>` below it, so a
  connector or community-edition user read a CLI-first onboarding for a setup
  that does not involve the CLI at all.

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
