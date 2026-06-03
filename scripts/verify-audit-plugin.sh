#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

test -f plugins/audit/.claude-plugin/plugin.json
test -f plugins/audit/skills/audit-merged-pr/SKILL.md
for a in pr-intent-analyst business-accuracy-analyst language-defect-analyst \
  security-analyst edge-effect-analyst similar-defect-scout subsequent-fix-scout \
  peer-path-comparator peer-parity-challenger finding-dedupe-normalizer \
  audit-challenger report-writer; do
  test -f "plugins/audit/agents/${a}.md"
done

python3 -c "
import json
m=json.load(open('.claude-plugin/marketplace.json'))
assert any(p['name']=='audit' for p in m['plugins'])
"

rg -q 'audit-merged-pr' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q '阶段 0b' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'expected_owner_repo' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'repo-binding.json' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'remote\\..*\\.url' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'findings-final' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'p3_below_threshold' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'effective-diff' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'severity_review' plugins/audit/agents/audit-challenger.md
rg -q 'matrix_rule_id' plugins/audit/agents/audit-challenger.md
rg -q 'trigger_vague_unfounded' plugins/audit/agents/audit-challenger.md
rg -q 'M10' plugins/audit/agents/audit-challenger.md
rg -q 'two_phase_yield' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'path_consistency' plugins/audit/agents/business-accuracy-analyst.md
rg -q 'shallow_path_consistency' plugins/audit/agents/audit-challenger.md
rg -q 'M11' plugins/audit/agents/audit-challenger.md
rg -q 'subsequent-fix-scout' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'subsequent_fix' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'already_fixed' plugins/audit/agents/subsequent-fix-scout.md
rg -q 'M12' plugins/audit/agents/audit-challenger.md
rg -q 'peer-path-comparator' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'peer-parity-challenger' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'peer-challenges' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q '6a″' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'peer-comparisons.json' plugins/audit/agents/peer-path-comparator.md
rg -q 'peer_reopened_by_audit' plugins/audit/agents/audit-challenger.md
rg -q 'M13' plugins/audit/agents/peer-parity-challenger.md
rg -q '同类路径比较' plugins/audit/agents/report-writer.md
rg -q 'R15' plugins/audit/agents/report-writer.md
rg -q '禁止.*markdown.*表格' plugins/audit/agents/report-writer.md
rg -q 'R15' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'rebuttals' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'needs_rebuttal' plugins/audit/agents/audit-challenger.md
rg -q 'debate_summary' plugins/audit/agents/audit-challenger.md
rg -q 'finding-defense-mode' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'counterclaims' plugins/audit/agents/finding-defense-mode.md
test -f plugins/audit/agents/finding-defense-mode.md
rg -q '阶段 5b' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'finding-dedupe-normalizer' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'dedupe-result.json' plugins/audit/agents/finding-dedupe-normalizer.md
rg -q 'canonical_items' plugins/audit/agents/finding-dedupe-normalizer.md
rg -q 'contributing_agents' plugins/audit/agents/finding-dedupe-normalizer.md
rg -q '最多 2 轮' plugins/audit/agents/peer-parity-challenger.md
rg -q '最多 3 轮' plugins/audit/agents/audit-challenger.md
rg -q 'peer_round <= 2' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'round <= 3' plugins/audit/skills/audit-merged-pr/SKILL.md

echo "OK: audit plugin structure"
