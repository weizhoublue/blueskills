#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

test -f plugins/audit-code/.claude-plugin/plugin.json
test -f plugins/audit-code/skills/review/SKILL.md
for a in change-context-analyst correctness-analyst readability-analyst architecture-analyst \
  security-analyst performance-analyst impact-analyst residual-defect-scout \
  finding-merger report-writer; do
  test -f "plugins/audit-code/agents/${a}.md"
done

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
rg -q 'residual-defect-scout' plugins/audit-code/skills/review/SKILL.md
rg -q 'mark_should_fix' plugins/audit-code/skills/review/SKILL.md
rg -q 'mark_ignore' plugins/audit-code/skills/review/SKILL.md
rg -q 'pr_narrative' plugins/audit-code/agents/change-context-analyst.md
rg -q 'trigger.scenario' plugins/audit-code/agents/correctness-analyst.md
rg -q 'meta_scope_not_a_defect' plugins/audit-code/agents/finding-merger.md
rg -q 'out_of_scope_style' plugins/audit-code/agents/finding-merger.md
rg -q 'dry_duplicate' plugins/audit-code/agents/architecture-analyst.md
rg -q '## 1. 修改意图分析' plugins/audit-code/agents/report-writer.md
rg -q '## 2. 发现的 PR 自身缺陷' plugins/audit-code/agents/report-writer.md
rg -q '## 3. 发现的仓库中的残留缺陷' plugins/audit-code/agents/report-writer.md
rg -q '## 4. 结论' plugins/audit-code/agents/report-writer.md
rg -q '禁止' plugins/audit-code/agents/report-writer.md
rg -q 'pipe 表' plugins/audit-code/agents/report-writer.md
rg -q 'R16' plugins/audit-code/skills/review/SKILL.md
rg -q 'REVIEW_RESULT' plugins/audit-code/agents/report-writer.md
rg -q 'report-quality-design' plugins/audit-code/skills/review/SKILL.md
rg -q 'defect_mechanism' plugins/audit-code/agents/correctness-analyst.md
rg -q 'defect_mechanism' plugins/audit-code/agents/finding-merger.md
rg -q 'vague_no_mechanism' plugins/audit-code/agents/finding-merger.md
rg -q 'duplicate_cluster' plugins/audit-code/agents/finding-merger.md
rg -q 'misclassified_dimension' plugins/audit-code/agents/finding-merger.md
rg -q '根因原理' plugins/audit-code/agents/report-writer.md
rg -q 'finding_category == performance' plugins/audit-code/agents/finding-merger.md
rg -q 'mechanism-dedup-design' plugins/audit-code/skills/review/SKILL.md
rg -q '不得超过 P3' plugins/audit-code/agents/performance-analyst.md

if rg -q 'audit-challenger' plugins/audit-code/skills/review/SKILL.md 2>/dev/null; then
  echo "SKILL must not reference audit-challenger in v1" >&2
  exit 1
fi
if rg -q '### 做得好的地方' plugins/audit-code/agents/report-writer.md 2>/dev/null; then
  echo "report-writer must not include ### 做得好的地方 section" >&2
  exit 1
fi
if rg -q '至少 1 条' plugins/audit-code/agents/report-writer.md 2>/dev/null; then
  echo "report-writer must not require 做得好的地方 entries" >&2
  exit 1
fi
if rg -q '### 摘要' plugins/audit-code/agents/report-writer.md 2>/dev/null; then
  echo "report-writer must use 四节结构 not ### 摘要" >&2
  exit 1
fi

echo "OK: audit-code plugin structure"
