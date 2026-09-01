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

echo "→ python modules"
while IFS= read -r f; do
  if python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$f" 2>/dev/null; then
    echo "  ok   $f"
  else
    echo "  FAIL $f (syntax)"; fail=1
  fi
done < <(find . -name '*.py' -not -path './.git/*' -not -path './test/*')

if command -v claude >/dev/null 2>&1; then
  echo "→ official manifest validation"
  if claude plugin validate . >/dev/null 2>&1; then
    echo "  ok   marketplace manifest"
  else
    echo "  FAIL marketplace manifest"; fail=1
  fi
  if claude plugin validate ./plugin >/dev/null 2>&1; then
    echo "  ok   plugin manifest"
  else
    echo "  FAIL plugin manifest"; fail=1
  fi
else
  echo "→ official manifest validation (skipped: claude CLI not on PATH)"
fi

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

echo "→ hook behaviour tests"
if python3 test/test_hooks.py >/tmp/kemory-tests.log 2>&1; then
  echo "  ok   $(grep -oE 'Ran [0-9]+ tests' /tmp/kemory-tests.log) passed"
else
  echo "  FAIL hook tests — see /tmp/kemory-tests.log"; tail -20 /tmp/kemory-tests.log; fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS"
else
  echo "FAILURES ABOVE"; exit 1
fi
