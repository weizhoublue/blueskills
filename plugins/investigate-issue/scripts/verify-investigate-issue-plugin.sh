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
grep -q 'R19\|REVIEW_RESULT' "$SKILL" || err "SKILL missing R19 verdict"
grep -q '仅一行\|禁止.*其他' "$ROOT/agents/issue-writer.md" || err "writer must require verdict one line only"
grep -q 'R19\|verdict' "$ROOT/agents/issue-challenger.md" || err "challenger missing R19 verdict"
grep -q 'mechanism_motivation\|motivation_audit\|R18' "$ROOT/agents/issue-challenger.md" || err "challenger missing R18 mechanism_motivation"
grep -q '关键机制为何如此设计\|R18' "$ROOT/agents/issue-writer.md" || err "writer missing R18 subsection"
grep -q 'design_rationale' "$ROOT/agents/business-context-analyst.md" || err "business-context missing design_rationale"
grep -q 'R18\|design_rationale' "$SKILL" || err "SKILL missing R18 or design_rationale merge"
grep -q 'scenario_evidence\|scenario_evidence_audit\|R20' "$ROOT/agents/issue-challenger.md" || err "challenger missing R20 scenario_evidence"
grep -q '未能从代码确认\|R20' "$ROOT/agents/issue-writer.md" || err "writer missing R20 unverified subsection"
grep -q 'scenario_kind\|unverified' "$ROOT/agents/code-tracer.md" || err "code-tracer missing R20 scenario_kind/unverified"
grep -q 'R20\|unverified' "$SKILL" || err "SKILL missing R20 or unverified merge"

# three-section report (no standalone consequences section)
grep -q '故障表现' "$ROOT/agents/issue-writer.md" || err "writer missing 故障表现 subsection"
grep -q 'sections/consequences.md' "$SKILL" && err "SKILL must not reference sections/consequences.md"
grep -q '## 2\. 问题后果' "$SKILL" && err "SKILL stdout must not have ## 2. 问题后果"
grep -q '## 2\. 触发条件' "$SKILL" || err "SKILL stdout must have ## 2. 触发条件"
grep -q '## 3\. 结论' "$SKILL" || err "SKILL stdout must have ## 3. 结论"
grep -q '缺.*故障表现' "$ROOT/agents/issue-challenger.md" || err "challenger missing 故障表现 gap checks"
grep -q 'sections/consequences.md' "$ROOT/agents/issue-challenger.md" && err "challenger must not read consequences.md"
grep -q 'target_section.*consequences' "$ROOT/agents/issue-challenger.md" && err "challenger target_section must not include consequences"

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
