#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

test -f plugins/audit-code/.claude-plugin/plugin.json
test -f plugins/audit-code/skills/review/SKILL.md
for a in change-context-analyst narrative-writer probe-worker report-assembler; do
  test -f "plugins/audit-code/agents/${a}.md"
done
for removed in correctness-analyst architecture-analyst security-analyst \
  performance-analyst impact-analyst residual-defect-scout finding-merger report-writer \
  readability-analyst; do
  if test -f "plugins/audit-code/agents/${removed}.md"; then
    echo "removed agent must not exist: ${removed}" >&2
    exit 1
  fi
done
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
rg -q 'question-driven-design' plugins/audit-code/skills/review/SKILL.md
if rg -q 'REVIEW_LEGACY_DIMENSIONS' plugins/audit-code/skills/review/SKILL.md 2>/dev/null; then
  echo "SKILL must not reference REVIEW_LEGACY_DIMENSIONS" >&2
  exit 1
fi
if rg -q 'correctness-analyst' plugins/audit-code/skills/review/SKILL.md 2>/dev/null; then
  echo "SKILL must not reference removed dimension analysts" >&2
  exit 1
fi
rg -q 'review-brief.md' plugins/audit-code/agents/probe-worker.md
rg -q 'findings/probes' plugins/audit-code/agents/probe-worker.md
rg -q 'defect_mechanism' plugins/audit-code/agents/probe-worker.md
rg -q 'trigger.scenario' plugins/audit-code/agents/probe-worker.md
rg -q 'entry_ref' plugins/audit-code/agents/probe-worker.md
rg -q '向下追溯' plugins/audit-code/agents/probe-worker.md
rg -q 'call_chain_trace' plugins/audit-code/agents/probe-worker.md
rg -q 'peer_pattern_compare' plugins/audit-code/agents/probe-worker.md
rg -q 'peer_compare_refs' plugins/audit-code/agents/probe-worker.md
rg -q 'peer_compare_refs' plugins/audit-code/skills/review/SKILL.md
rg -q 'residual_peer_pattern' plugins/audit-code/skills/review/SKILL.md
rg -q 'fix_pattern_summary' plugins/audit-code/skills/review/SKILL.md
rg -q 'grep_tokens' plugins/audit-code/skills/review/SKILL.md
rg -q 'missing_peer_compare' plugins/audit-code/agents/report-assembler.md
rg -q 'entry_ref' plugins/audit-code/skills/review/SKILL.md
rg -q 'missing_call_chain' plugins/audit-code/agents/report-assembler.md
rg -q 'user_facing' plugins/audit-code/agents/narrative-writer.md
rg -q 'meta_scope_not_a_defect' plugins/audit-code/agents/report-assembler.md
rg -q 'duplicate_cluster' plugins/audit-code/agents/report-assembler.md
rg -q 'vague_no_mechanism' plugins/audit-code/agents/report-assembler.md
rg -q 'misclassified_dimension' plugins/audit-code/agents/report-assembler.md
rg -q '## 1. 修改意图分析' plugins/audit-code/agents/report-assembler.md
rg -q '根因原理' plugins/audit-code/agents/report-assembler.md
rg -q 'mark_should_fix' plugins/audit-code/skills/review/SKILL.md
rg -q 'mechanism-dedup-design' plugins/audit-code/skills/review/SKILL.md

if rg -q 'audit-challenger' plugins/audit-code/skills/review/SKILL.md 2>/dev/null; then
  echo "SKILL must not reference audit-challenger in v1" >&2
  exit 1
fi

echo "OK: audit-code plugin structure"
