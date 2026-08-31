#!/usr/bin/env bash
# Validate every manifest and script. Run before opening a PR; CI runs this too.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0

echo "→ JSON manifests"
while IFS= read -r f; do
  if jq empty "$f" 2>/dev/null; then
    echo "  ok   $f"
  else
    echo "  FAIL $f"; fail=1
  fi
done < <(find . -name '*.json' -not -path './.git/*' -not -path '*/node_modules/*')

echo "→ shell scripts"
while IFS= read -r f; do
  if bash -n "$f" 2>/dev/null; then
    if [ -x "$f" ]; then
      echo "  ok   $f"
    else
      echo "  FAIL $f (not executable)"; fail=1
    fi
  else
    echo "  FAIL $f (syntax)"; fail=1
  fi
done < <(find . -name '*.sh' -not -path './.git/*')

echo "→ plugin source paths resolve"
while IFS= read -r m; do
  p=$(jq -r '.plugins[0].source | if type=="string" then . else .path end' "$m")
  if [ -d "${p#./}" ]; then echo "  ok   $m -> $p"; else echo "  FAIL $m -> $p"; fail=1; fi
done < <(find . -name 'marketplace.json' -not -path './.git/*')

echo "→ hooks reference existing scripts"
while IFS= read -r s; do
  s="${s/\$\{CLAUDE_PLUGIN_ROOT\}/plugin}"
  if [ -f "$s" ]; then echo "  ok   $s"; else echo "  FAIL missing $s"; fail=1; fi
done < <(jq -r '.hooks[][].hooks[].command | select(contains("CLAUDE_PLUGIN_ROOT"))' \
          plugin/hooks/hooks.json | awk '{print $1}')

echo "→ session-start is silent when disabled"
if KEMORY_CONTEXT=0 sh -c 'echo "{}" | plugin/scripts/session-start.sh' | grep -q .; then
  echo "  FAIL session-start emitted output with KEMORY_CONTEXT=0"; fail=1
else
  echo "  ok   silent when disabled"
fi

echo "→ capture is opt-in by default"
if echo '{}' | plugin/scripts/capture.sh | grep -q .; then
  echo "  FAIL capture emitted output with KEMORY_AUTO_CAPTURE unset"; fail=1
else
  echo "  ok   silent when disabled"
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS"
else
  echo "FAILURES ABOVE"; exit 1
fi
