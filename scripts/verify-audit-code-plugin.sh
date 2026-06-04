#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

test -f plugins/audit-code/.claude-plugin/plugin.json
test -f plugins/audit-code/skills/review/SKILL.md
for a in change-context-analyst narrative-writer probe-worker report-assembler \
  finding-merger report-writer correctness-analyst architecture-analyst \
  security-analyst performance-analyst impact-analyst residual-defect-scout; do
  test -f "plugins/audit-code/agents/${a}.md"
done
if test -f plugins/audit-code/agents/readability-analyst.md; then
  echo "readability-analyst must be removed" >&2
  exit 1
fi
test -x plugins/audit-code/scripts/audit-code-hunk-index.sh
test -x plugins/audit-code/scripts/audit-code-triage.sh
test -x scripts/audit-code-hunk-index.sh
test -x scripts/audit-code-triage.sh

python3 -c "
import json
m=json.load(open('.claude-plugin/marketplace.json'))
names=[p['name'] for p in m['plugins']]
assert 'audit-code' in names
assert 'audit' not in names, 'legacy audit plugin must be removed from marketplace'
p=json.load(open('plugins/audit-code/.claude-plugin/plugin.json'))
assert p['name']=='audit-code'
"
if test -d plugins/audit; then
  echo "plugins/audit directory must be removed" >&2
  exit 1
fi
if test -f scripts/verify-audit-plugin.sh; then
  echo "scripts/verify-audit-plugin.sh must be removed" >&2
  exit 1
fi

rg -q '/audit-code:review' plugins/audit-code/skills/review/SKILL.md
rg -q 'REVIEW_TMP' plugins/audit-code/skills/review/SKILL.md
rg -q 'change-context-analyst' plugins/audit-code/skills/review/SKILL.md
rg -q 'probe-worker' plugins/audit-code/skills/review/SKILL.md
rg -q 'report-assembler' plugins/audit-code/skills/review/SKILL.md
rg -q 'investigation-plan' plugins/audit-code/skills/review/SKILL.md
rg -q 'review-brief' plugins/audit-code/skills/review/SKILL.md
rg -q 'REVIEW_LEGACY_DIMENSIONS' plugins/audit-code/skills/review/SKILL.md
rg -q 'question-driven-design' plugins/audit-code/skills/review/SKILL.md
rg -q 'residual-defect-scout' plugins/audit-code/skills/review/SKILL.md
rg -q 'mark_should_fix' plugins/audit-code/skills/review/SKILL.md
rg -q 'mark_ignore' plugins/audit-code/skills/review/SKILL.md
rg -q 'review-brief.md' plugins/audit-code/agents/probe-worker.md
rg -q 'findings/probes' plugins/audit-code/agents/probe-worker.md
rg -q 'user_facing' plugins/audit-code/agents/narrative-writer.md
rg -q '顶层调用链' plugins/audit-code/agents/report-assembler.md
if rg -q 'readability-analyst' plugins/audit-code/skills/review/SKILL.md 2>/dev/null; then
  echo "SKILL must not reference readability-analyst" >&2
  exit 1
fi
rg -q 'trigger.scenario' plugins/audit-code/agents/correctness-analyst.md
rg -q 'meta_scope_not_a_defect' plugins/audit-code/agents/finding-merger.md
rg -q 'out_of_scope_style' plugins/audit-code/agents/finding-merger.md
rg -q 'dry_duplicate' plugins/audit-code/agents/architecture-analyst.md
rg -q '## 1. 修改意图分析' plugins/audit-code/agents/report-assembler.md
rg -q '## 4. 结论' plugins/audit-code/agents/report-assembler.md
rg -q '根因原理' plugins/audit-code/agents/report-assembler.md
rg -q 'defect_mechanism' plugins/audit-code/agents/correctness-analyst.md
rg -q 'duplicate_cluster' plugins/audit-code/agents/finding-merger.md
rg -q 'mechanism-dedup-design' plugins/audit-code/skills/review/SKILL.md
rg -q '不得超过 P3' plugins/audit-code/agents/performance-analyst.md

if rg -q 'audit-challenger' plugins/audit-code/skills/review/SKILL.md 2>/dev/null; then
  echo "SKILL must not reference audit-challenger in v1" >&2
  exit 1
fi

echo "OK: audit-code plugin structure"
