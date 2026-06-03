#!/usr/bin/env bash
# verify-investigate-issue-plugin.sh — 校验 investigate-issue 插件结构
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT/../.." && pwd)"
fail=0
err() { echo "ERROR: $*" >&2; fail=$((fail + 1)); }

# manifest
[[ -f "$ROOT/.claude-plugin/plugin.json" ]] || err "missing plugin.json"
python3 -c "import json; assert json.load(open('$ROOT/.claude-plugin/plugin.json'))['name']=='investigate-issue'"

# skill
SKILL="$ROOT/skills/investigate/SKILL.md"
[[ -f "$SKILL" ]] || err "missing SKILL.md"
for kw in ISSUE_TMP mktemp issue-analysis.json MAX_ROUNDS_PER_SECTION needs_enrichment stdout; do
  grep -q "$kw" "$SKILL" || err "SKILL missing: $kw"
done

# agents
for a in issue-scout code-tracer business-context-analyst module-background-analyst issue-writer issue-challenger; do
  [[ -f "$ROOT/agents/${a}.md" ]] || err "missing agent: $a"
done

# challenger enricher role
grep -qE '深化|补全' "$ROOT/agents/issue-challenger.md" || err "challenger missing enricher role"

# no investigate-project paths in plugin content
if rg -q 'REPORT_ROOT|analysis-report' "$ROOT/agents" "$ROOT/skills" 2>/dev/null; then
  err "plugin must not reference REPORT_ROOT or analysis-report"
fi

# marketplace
python3 -c "
import json
m=json.load(open('$REPO_ROOT/.claude-plugin/marketplace.json'))
assert any(p['name']=='investigate-issue' for p in m['plugins'])
"

if [[ $fail -eq 0 ]]; then
  echo "verify OK"
else
  echo "verify FAILED: $fail errors"
  exit 1
fi
