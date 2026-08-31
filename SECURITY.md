# Security Policy

## Reporting a vulnerability

Please report security issues privately to **security@sekondbrain.ai** rather
than opening a public issue. We aim to acknowledge within 3 business days.

## Scope notes for this plugin

**Session capture is opt-in and off by default.** When enabled with
`KEMORY_AUTO_CAPTURE=1`, the plugin sends a bounded digest of your own
prompts to the Kemory instance you have configured. Review
[plugin/README.md](plugin/README.md) before enabling it.

**Redaction is best-effort.** `scripts/capture.sh` strips common secret
shapes (bearer tokens, `api_key=`/`password=` assignments, `sk-`, `gh*_`,
AWS access key ids, PEM private-key headers) before upload. This is
pattern-matching, not a guarantee — a novel or unusual secret format can pass
through. If you work with sensitive material, leave capture disabled.

**Credentials** are read from the Kemory CLI's local credential file, or from
`KEMORY_URL` / `KEMORY_TOKEN`. The plugin never writes credentials anywhere
and never logs them.
