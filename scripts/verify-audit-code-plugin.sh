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
assert any(p['name']=='audit-code' for p in m['plugins'])
p=json.load(open('plugins/audit-code/.claude-plugin/plugin.json'))
assert p['name']=='audit-code'
"

rg -q '/audit-code:review' plugins/audit-code/skills/review/SKILL.md
rg -q 'REVIEW_TMP' plugins/audit-code/skills/review/SKILL.md
rg -q 'change-context-analyst' plugins/audit-code/skills/review/SKILL.md
rg -q 'residual-defect-scout' plugins/audit-code/skills/review/SKILL.md
rg -q 'mark_should_fix' plugins/audit-code/skills/review/SKILL.md
rg -q 'mark_ignore' plugins/audit-code/skills/review/SKILL.md
rg -q '### 结论' plugins/audit-code/agents/report-writer.md
rg -q 'R16' plugins/audit-code/skills/review/SKILL.md
if rg -q 'audit-challenger' plugins/audit-code/skills/review/SKILL.md 2>/dev/null; then
  echo "SKILL must not reference audit-challenger in v1" >&2
  exit 1
fi

echo "OK: audit-code plugin structure"
