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
for kw in ISSUE_TMP mktemp issue-analysis.json MAX_REVIEW_ROUNDS needs_enrichment stdout draft_all full-report; do
  grep -q "$kw" "$SKILL" || err "SKILL missing: $kw"
done
grep -q 'MAX_ROUNDS_PER_SECTION' "$SKILL" && err "SKILL must not use per-section MAX_ROUNDS_PER_SECTION"
grep -q 'background-knowledge\|module-background' "$SKILL" && err "SKILL must not reference background-knowledge flow"

# agents (5 agents, no module-background-analyst)
for a in issue-scout code-tracer business-context-analyst issue-writer issue-challenger; do
  [[ -f "$ROOT/agents/${a}.md" ]] || err "missing agent: $a"
done
[[ ! -f "$ROOT/agents/module-background-analyst.md" ]] || err "module-background-analyst should be removed"

grep -q 'full-report\|draft_all' "$ROOT/agents/issue-challenger.md" || err "challenger missing full-report scope"
grep -q 'draft_all\|full-report' "$ROOT/agents/issue-writer.md" || err "writer missing draft_all mode"
grep -q '叙事优先\|R16\|code dump' "$ROOT/agents/issue-writer.md" || err "writer missing narrative-first R16"
grep -q 'background-knowledge' "$ROOT/agents/issue-writer.md" && err "writer must not reference background-knowledge"
grep -q 'business_meaning' "$ROOT/agents/code-tracer.md" || err "code-tracer missing business_meaning"
grep -q 'causal_narrative' "$ROOT/agents/business-context-analyst.md" || err "business-context missing causal_narrative"
grep -q 'R17' "$SKILL" || err "SKILL missing R17 conditional rigor"
grep -q 'when_does_not_trigger\|when_triggers' "$ROOT/agents/code-tracer.md" || err "code-tracer missing trigger polarity"
grep -q '不触发\|反向' "$ROOT/agents/issue-writer.md" || err "writer missing reverse trigger sections"
grep -q 'R17\|conditional_rigor' "$ROOT/agents/issue-challenger.md" || err "challenger missing R17 checks"
grep -q 'non_trigger_scenarios' "$ROOT/agents/business-context-analyst.md" || err "business-context missing non_trigger_scenarios"

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
