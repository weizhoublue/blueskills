#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

test -f plugins/audit/.claude-plugin/plugin.json
test -f plugins/audit/skills/audit-merged-pr/SKILL.md
for a in pr-intent-analyst business-accuracy-analyst language-defect-analyst \
  security-analyst edge-effect-analyst similar-defect-scout audit-challenger report-writer; do
  test -f "plugins/audit/agents/${a}.md"
done

python3 -c "
import json
m=json.load(open('.claude-plugin/marketplace.json'))
assert any(p['name']=='audit' for p in m['plugins'])
"

rg -q 'audit-merged-pr' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'findings-final' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'p3_below_threshold' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'effective-diff' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'severity_review' plugins/audit/agents/audit-challenger.md
rg -q 'matrix_rule_id' plugins/audit/agents/audit-challenger.md
rg -q 'trigger_vague_unfounded' plugins/audit/agents/audit-challenger.md
rg -q 'M10' plugins/audit/agents/audit-challenger.md

echo "OK: audit plugin structure"
