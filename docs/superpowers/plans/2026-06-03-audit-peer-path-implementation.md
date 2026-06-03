# audit 等同路径比较（peer-path + peer-parity）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在已有 `audit` 插件上实现 **模式 2**：6a′ `peer-path-comparator`（1 pass）→ 6a″ `peer-parity-challenger`（≤3 轮/finding）→ 6b `audit-challenger`（≤5 轮，peer 交叉验证）；终稿含 **同类路径比较**。

**Architecture:** 两个新 agent Markdown + 扩展主编排 `SKILL.md` 阶段 6；`AUDIT_TMP` 新增 `peer-comparisons.json`、`peer-challenges/`；`audit-challenger` 必读 `peer-challenges/<id>-final.json`，M13/M14 主责迁至 peer 线；无单元测试，用 `scripts/verify-audit-plugin.sh` 做结构门禁。

**Tech Stack:** Claude Code plugin agents（YAML frontmatter + 中文正文）、Bash 校验脚本。

**Reference:**

- [`docs/superpowers/specs/2026-06-03-audit-peer-path-comparison-design.md`](../specs/2026-06-03-audit-peer-path-comparison-design.md)（v2）
- [`docs/superpowers/specs/2026-06-03-audit-pr-plugin-design.md`](../specs/2026-06-03-audit-pr-plugin-design.md)（v8 §4.7c–4.7d）

**Conventions:** agent 正文中文；`name` 英文 kebab-case；每 task 结束单独 commit。

---

## 文件结构

| 路径 | 动作 | 职责 |
|------|------|------|
| `plugins/audit/agents/peer-path-comparator.md` | Create | 6a′：1 pass → `peer-comparisons.json` |
| `plugins/audit/agents/peer-parity-challenger.md` | Create | 6a″：≤3 轮 → `peer-challenges/` |
| `plugins/audit/agents/audit-challenger.md` | Modify | Read peer-final；`peer_reopened_by_audit`；M13/M14 改为复核 |
| `plugins/audit/skills/audit-merged-pr/SKILL.md` | Modify | 阶段 6a′/6a″/6b 伪代码、Sub-agent 表、stdout 报告节 |
| `plugins/audit/agents/report-writer.md` | Modify | **同类路径比较** 小节 |
| `plugins/audit/.claude-plugin/plugin.json` | Modify | agent 数量描述（可选） |
| `scripts/verify-audit-plugin.sh` | Modify | 新 agent + 关键词 |
| `docs/installation.md` | Modify | 一句说明 peer 两阶段（若存在 audit 段） |

---

### Task 1: Agent — `peer-path-comparator`

**Files:**

- Create: `plugins/audit/agents/peer-path-comparator.md`

- [ ] **Step 1: 创建 agent 文件**

Frontmatter 示例：

```yaml
---
name: peer-path-comparator
description: 等同路径对照员。对每条 P0–P2 finding 做 1 次局部兄弟分支(A≤8)与可选仓库 analogue(B≤5)对照，写 peer-comparisons.json。不质询。
model: inherit
tools: Read, Grep, Glob, Write
---
```

正文须包含：

- 入队：未 `subsequent_fix` 淘汰；`severity ∈ {P0,P1,P2}`
- **A 必做**：Read 锚点完整函数；`siblings[]`；`local_conclusion`
- **B 条件**：A 有 `same_pattern=true` 或 finding 称系统性；`analogues` ≤5；Grep ≤10/条
- Write **仅** `$AUDIT_TMP/peer-comparisons.json`（schema 见 spec §4.1）
- 返回主线程 ≤6 行：`agent`, `items`, `output`

- [ ] **Step 2: 校验文件存在**

```bash
test -f plugins/audit/agents/peer-path-comparator.md
rg -q 'peer-comparisons.json' plugins/audit/agents/peer-path-comparator.md
rg -q 'local_conclusion' plugins/audit/agents/peer-path-comparator.md
```

Expected: 无错误

- [ ] **Step 3: Commit**

```bash
git add plugins/audit/agents/peer-path-comparator.md
git commit -m "feat(audit): add peer-path-comparator agent (1-pass survey)"
```

---

### Task 2: Agent — `peer-parity-challenger`

**Files:**

- Create: `plugins/audit/agents/peer-parity-challenger.md`

- [ ] **Step 1: 创建 agent 文件**

Frontmatter：

```yaml
---
name: peer-parity-challenger
description: 等同路径专质询员。每条 finding 最多 3 轮：M13/M14、对照深浅、结论一致性。Write 仅 peer-challenges/。
model: inherit
tools: Read, Write
---
```

正文须包含：

- Read：`peer-comparisons.json`、`intent.json`、finding、`peer-challenges/` 历史
- Write：`peer-challenges/<finding_id>-round-<N>.json` 与结案 `peer-challenges/<finding_id>-final.json`
- `challenge_types`：`missing_peer_comparison`, `peer_survey_shallow`, `peer_conclusion_inconsistent`
- **M13 / M14** 主责；`round` 1..3；`peer_line_resolution`: accepted|withdrawn|downgraded|inconclusive
- proposer 始终为 `source_agent`（主线程委派修订 `peer_comparison`）
- 禁止 Write `challenges/`

Round JSON 最小 schema（写入 agent 正文）：

```json
{
  "finding_id": "F-001",
  "round": 1,
  "challenger": "peer-parity-challenger",
  "challenge_types": ["peer_survey_shallow"],
  "severity_review": { "matrix_rule_id": "M13", "proposed_action": "require_more_peer_evidence" },
  "resolution": "revise|withdrawn|accepted|downgraded"
}
```

- [ ] **Step 2: 校验**

```bash
test -f plugins/audit/agents/peer-parity-challenger.md
rg -q 'peer-challenges' plugins/audit/agents/peer-parity-challenger.md
rg -q 'M13' plugins/audit/agents/peer-parity-challenger.md
rg -q '最多 3 轮' plugins/audit/agents/peer-parity-challenger.md
```

- [ ] **Step 3: Commit**

```bash
git add plugins/audit/agents/peer-parity-challenger.md
git commit -m "feat(audit): add peer-parity-challenger agent (≤3 rounds)"
```

---

### Task 3: 更新 `audit-challenger.md`

**Files:**

- Modify: `plugins/audit/agents/audit-challenger.md`

- [ ] **Step 1: 更新 description**

加入：必读 `peer-challenges/*-final`；`peer_reopened_by_audit`；M13/M14 仅在新证据下复核。

- [ ] **Step 2: 新增 §peer 线与 audit 分工**

表格（写入 agent）：

| audit 会做 | audit 禁止（除非 `peer_reopened_by_audit` + `new_evidence_refs`） |
|------------|---------------------------------------------------------------------|
| 调用链、触发、§5.7、§5.8、M0–M12（非 13/14 主责） | 重复 peer 已 accepted 的 sibling 调查 |
| 新 path:line 推翻 peer 结论 | 空泛重审 M13/M14 |

- [ ] **Step 3: 将原 §路径一致性质询中的 M13/M14 引用改为「见 peer-parity-challenger；audit 仅 `peer_reopened_by_audit`」**

保留 M11/M12 在 audit。

- [ ] **Step 4: Read 列表追加**

`peer-comparisons.json`、`peer-challenges/<finding_id>-final.json`

- [ ] **Step 5: `challenge_type` 枚举追加 `peer_reopened_by_audit`**

- [ ] **Step 6: Commit**

```bash
git add plugins/audit/agents/audit-challenger.md
git commit -m "feat(audit): audit-challenger peer cross-validation after peer-final"
```

---

### Task 4: 更新 `audit-merged-pr/SKILL.md` 阶段 6

**Files:**

- Modify: `plugins/audit/skills/audit-merged-pr/SKILL.md`

- [ ] **Step 1: 更新 skill `description`**

提及 `peer-path-comparator`、`peer-parity-challenger`（≤3 轮）、`audit-challenger`（≤5 轮）。

- [ ] **Step 2: 替换「阶段 6」伪代码**

在 `subsequent-fix-scout` 之后插入：

```text
# 6a′ peer-path-comparator（1 pass / finding，P0–P2，未 subsequent_fix）
委派 peer-path-comparator → peer-comparisons.json
合并 → F.peer_comparison 草稿

# 6a″ peer-parity-challenger（≤3 轮 / finding）
peer_round ← 1
while peer_round <= 3:
  委派 peer-parity-challenger(F, peer_round)
  若 withdrawn → rejected；跳过 6b；break
  若 accepted|downgraded → 写 peer-challenges/F-final.json；更新 peer_comparison；break
  委派 source_agent 修订 peer_comparison
  peer_round++
若 peer_round>3 → rejected（peer_inconclusive）或 主编排策略见 spec

# 6b audit-challenger（≤5 轮，须已有 peer-challenges/F-final.json）
round ← 1
while round <= 5:
  委派 audit-challenger(F, round)  # 必读 peer-final
  ...
```

- [ ] **Step 3: AUDIT_TMP 目录说明**

`mkdir peer-challenges` 于 0c（与 `findings challenges` 并列）。

- [ ] **Step 4: Sub-agent 表增加两行**

`peer-path-comparator` | `peer-comparisons.json`  
`peer-parity-challenger` | `peer-challenges/*`

- [ ] **Step 5: stdout 报告结构增加 `- 同类路径比较`**

- [ ] **Step 6: Commit**

```bash
git add plugins/audit/skills/audit-merged-pr/SKILL.md
git commit -m "feat(audit): skill stage 6a′ 6a″ peer parity before audit"
```

---

### Task 5: 更新 `report-writer.md`

**Files:**

- Modify: `plugins/audit/agents/report-writer.md`

- [ ] **Step 1: 在「复现概率」后增加小节**

```markdown
- **同类路径比较** （来自 `peer_comparison.report_blurb_zh` / `table_rows`）
```

- [ ] **Step 2: Read 说明**

可读 `findings-final` 内 `peer_comparison`（含 `peer_line_resolution`）。

- [ ] **Step 3: Commit**

```bash
git add plugins/audit/agents/report-writer.md
git commit -m "feat(audit): report-writer 同类路径比较 section"
```

---

### Task 6: `verify-audit-plugin.sh` 与 plugin 描述

**Files:**

- Modify: `scripts/verify-audit-plugin.sh`
- Modify: `plugins/audit/.claude-plugin/plugin.json`（可选）

- [ ] **Step 1: 扩展 agent 列表循环**

```bash
for a in pr-intent-analyst business-accuracy-analyst language-defect-analyst \
  security-analyst edge-effect-analyst similar-defect-scout subsequent-fix-scout \
  peer-path-comparator peer-parity-challenger \
  audit-challenger report-writer; do
```

- [ ] **Step 2: 追加 rg 检查**

```bash
rg -q 'peer-path-comparator' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'peer-parity-challenger' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'peer-challenges' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'peer-comparisons.json' plugins/audit/agents/peer-path-comparator.md
rg -q 'peer_reopened_by_audit' plugins/audit/agents/audit-challenger.md
rg -q 'M13' plugins/audit/agents/peer-parity-challenger.md
rg -q '同类路径比较' plugins/audit/agents/report-writer.md
rg -q '6a″' plugins/audit/skills/audit-merged-pr/SKILL.md
```

- [ ] **Step 3: 运行脚本**

```bash
./scripts/verify-audit-plugin.sh
```

Expected: `OK: audit plugin structure`

- [ ] **Step 4: Commit**

```bash
git add scripts/verify-audit-plugin.sh plugins/audit/.claude-plugin/plugin.json
git commit -m "chore(audit): verify peer-path and peer-parity agents"
```

---

### Task 7: 文档同步（可选短任务）

**Files:**

- Modify: `docs/installation.md`（若含 audit 段落）

- [ ] **Step 1: 在 audit 用法段增加一句**

说明阶段 6 含等同路径对照（1 pass）+ 专质询（≤3 轮）+ 全链路质询（≤5 轮）。

- [ ] **Step 2: Commit**

```bash
git add docs/installation.md
git commit -m "docs(audit): document peer parity stages in installation"
```

---

## Spec 覆盖自检

| Spec 要求 | Task |
|-----------|------|
| 6a′ 1 pass A/B | 1, 4 |
| 6a″ ≤3 轮 M13/M14 | 2, 4 |
| 6b ≤5 轮 peer 交叉验证 | 3, 4 |
| peer-final / withdrawn 跳过 audit | 2, 4 |
| 终稿同类路径比较 | 5 |
| 验收脚本 | 6 |

## 执行后人工抽检（非自动化）

1. 在任意已 clone 仓库运行 `/audit:audit-merged-pr <merged_pr_url>`（或 dry-run 读 SKILL 编排）。
2. 设置 `AUDIT_KEEP_TMP=1`，确认存在 `peer-comparisons.json`、`peer-challenges/F-001-final.json`。
3. 确认 `withdrawn` 的 finding 无 `challenges/F-001-round-1.json`。

---

**Plan complete.** 实现时优先 Task 1→2→4→3→5→6→7。
