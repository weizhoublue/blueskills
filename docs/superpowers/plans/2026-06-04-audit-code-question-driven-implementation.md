# audit-code 问题驱动编排 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `audit-code:review` 默认路径改为「主编排出题 → probe 簇验证 → report-assembler 出报告」，缩短墙钟时间并减少重复读盘；保留 `REVIEW_LEGACY_DIMENSIONS=1` 六维旧路径。

**Architecture:** Shell 产出 `review-profile.json` + `hunk-index.json` → `change-context` core → **主编排**写 `review-brief.md` + `investigation-plan.json` → 2–3× `probe-worker` ∥ `narrative-writer` → `report-assembler`（内嵌 merger gate + 四节 Markdown）。探针 finding schema 与现 `correctness-analyst` 一致。

**Tech Stack:** Claude Code plugin（Markdown agents + SKILL.md）、bash（`git`、`rg`）、`scripts/verify-audit-code-plugin.sh`。

**Reference:** [`docs/superpowers/specs/2026-06-04-audit-code-question-driven-design.md`](../specs/2026-06-04-audit-code-question-driven-design.md)

**Conventions:** 插件正文中文；`REVIEW_TMP`；不删除旧六维 agent 文件（legacy 分支仍引用）。

---

## 文件结构

| 路径 | 操作 | 职责 |
|------|------|------|
| `scripts/audit-code-hunk-index.sh` | Create | 从 `raw-diff.patch` + `review-files.json` 写 `hunk-index.json` |
| `scripts/audit-code-triage.sh` | Create | 启发式写 `review-profile.json` |
| `plugins/audit-code/agents/change-context-analyst.md` | Modify | core-only；`pr_narrative` 可占位 |
| `plugins/audit-code/agents/narrative-writer.md` | Create | 补全 `pr_narrative` |
| `plugins/audit-code/agents/probe-worker.md` | Create | 按题簇作答；输出 `findings/probes/*.json` |
| `plugins/audit-code/agents/report-assembler.md` | Create | gate + 四节终稿 |
| `plugins/audit-code/skills/review/SKILL.md` | Modify | v2 主流程 + legacy 分支 + 3c 出题指引 |
| `plugins/audit-code/.claude-plugin/plugin.json` | Modify | description 提及 question-driven |
| `scripts/verify-audit-code-plugin.sh` | Modify | 断言新 agent/脚本/SKILL 关键字 |
| `docs/installation.md` | Modify | audit-code 流程一句更新 |
| `docs/superpowers/specs/2026-06-04-review-plugin-design.md` | Modify | 增加 v2 编排指针（可选一节） |
| 现有 `finding-merger.md` / `report-writer.md` / 六维 analyst | 保留 | 仅 `REVIEW_LEGACY_DIMENSIONS=1` 使用 |

---

## 共享片段

### `review-profile.json`（triage 脚本输出）

```json
{
  "version": 1,
  "depth": "fast",
  "skip_kinds": [],
  "enable_architecture": false,
  "enable_residual": true,
  "enable_security": true,
  "rationale": "…"
}
```

环境变量：`REVIEW_DEPTH=full` → `depth=full`，`enable_architecture=true`，且 SKILL 派 `should` 题。

### `investigation-plan.json`（主编排 3c 写入）

见 design spec §7；`clusters[].worker` ∈ `logic-ripple` | `nonfunctional` | `architecture`。

### Probe 输出 `findings/probes/<cluster-id>.json`

```json
{
  "version": 1,
  "cluster_id": "logic-1",
  "worker": "logic-ripple",
  "answers": [{ "question_id": "Q-001", "verdict": "confirmed", "finding": {} }],
  "items": []
}
```

`items[]` 为扁平 finding 列表（schema 同 `correctness-analyst.md`）。

---

### Task 1: Shell — hunk-index

**Files:**
- Create: `scripts/audit-code-hunk-index.sh`

- [ ] **Step 1:** 创建脚本（可执行），签名：

```bash
#!/usr/bin/env bash
# Usage: audit-code-hunk-index.sh <REVIEW_TMP>
# Reads: $REVIEW_TMP/raw-diff.patch, $REVIEW_TMP/review-files.json
# Writes: $REVIEW_TMP/hunk-index.json
```

- [ ] **Step 2:** 实现逻辑（bash + python3 内联或纯 bash）：
  - 遍历 `review-files.json` 的 `files[]`
  - 每文件：`lines_added`/`lines_removed`（`git diff --numstat` 或解析 patch）
  - `symbols_touched`：`rg -o` 或 `grep -E '^(+|-).*func '` 启发；至少提取 patch 中 `func (` / `func(` 行
  - `hunk_summary`：该文件在 patch 中 ± 上下文合计 ≤80 行
  - 输出 JSON `{"version":1,"files":[...]}`

- [ ] **Step 3:** 本地冒烟

```bash
chmod +x scripts/audit-code-hunk-index.sh
# 在任意 git 仓库：REVIEW_TMP=$(mktemp -d) && git diff > "$REVIEW_TMP/raw-diff.patch"
# 手写 review-files.json 后运行脚本，test -f "$REVIEW_TMP/hunk-index.json"
```

- [ ] **Step 4: Commit**

```bash
git add scripts/audit-code-hunk-index.sh
git commit -m "feat(audit-code): add hunk-index shell helper"
```

---

### Task 2: Shell — triage

**Files:**
- Create: `scripts/audit-code-triage.sh`

- [ ] **Step 1:** 创建脚本，读 `$REVIEW_TMP/review-files.json`、`change-context.json`（若尚无则仅 review-files + patch 统计）、`scope.json`

- [ ] **Step 2:** 规则（python3 写 JSON）：
  - 全部路径匹配 `docs/**` 或仅 `.md` → `docs_only`：`enable_residual=false`，`skip_kinds` 含 `performance`,`security`
  - 文件数 ≤3 且总行变更 <80 → `enable_architecture=false`，`skip_kinds` 含 `performance`
  - `change_kind` 非 `bugfix`（无 change-context 时从 patch/message 启发）→ `enable_residual=false`
  - patch/hunk 无 `auth|token|password|http\.|Validate` → `enable_security=false`
  - `REVIEW_DEPTH=full` → `depth=full`，`enable_architecture=true`

- [ ] **Step 3: Commit**

```bash
git add scripts/audit-code-triage.sh
git commit -m "feat(audit-code): add triage profile shell helper"
```

---

### Task 3: change-context-analyst（core-only）

**Files:**
- Modify: `plugins/audit-code/agents/change-context-analyst.md`

- [ ] **Step 1:** 描述改为「六维/探针前：core 背景；`pr_narrative` 由 narrative-writer 补全」

- [ ] **Step 2:** 任务列表删除「完整 PR 叙事」硬性要求；改为：

```markdown
7. **pr_narrative（占位）**：可写 `unknown` 子字段；**禁止**花费大量 Read 写长叙事（由 narrative-writer 负责）。
```

- [ ] **Step 3:** Read 预算收紧：`Read ≤25, Grep ≤15`（core 应更快）

- [ ] **Step 4: Commit**

```bash
git add plugins/audit-code/agents/change-context-analyst.md
git commit -m "feat(audit-code): change-context core-only for v2 pipeline"
```

---

### Task 4: narrative-writer

**Files:**
- Create: `plugins/audit-code/agents/narrative-writer.md`

- [ ] **Step 1:**  frontmatter：

```yaml
---
name: narrative-writer
description: 补全 change-context.pr_narrative（顶层调用链 + 用户侧/软件侧前后表现）。只读；Write 仅更新 change-context.json 的 pr_narrative 字段。
model: inherit
tools: Read, Write
---
```

- [ ] **Step 2:** 硬性要求：
  - Read：`change-context.json`（core）、`hunk-index.json`、`pr-snapshot.json`（可选）、入口文件 ≤10
  - Write：**Read 全文 change-context → 合并写回**（或 Write 仅 `pr_narrative` 若编排允许 patch；推荐 Read+merge+Write 同一文件）
  - 填满 `top_level_call_chain`、`before_problem.{user_facing,software_level}`、`after_fix.*`、`design_approach`
  - 禁止输出 finding

- [ ] **Step 3: Commit**

```bash
git add plugins/audit-code/agents/narrative-writer.md
git commit -m "feat(audit-code): add narrative-writer agent"
```

---

### Task 5: probe-worker

**Files:**
- Create: `plugins/audit-code/agents/probe-worker.md`

- [ ] **Step 1:** frontmatter `name: probe-worker`；description 写明「按 investigation-plan 单簇执行」

- [ ] **Step 2:** 输入（主线程 prompt 传入）：
  - `cluster_id`
  - `REVIEW_TMP`
  - 必读：`review-brief.md`、`investigation-plan.json` 中本簇 `questions`

- [ ] **Step 3:** 硬性约束（原文写入 agent）：

```markdown
- 禁止 Read 完整 raw-diff.patch
- 禁止遍历 review-files.json 全表扫仓
- Read ≤12，Grep ≤15（worker=logic-ripple 且含 residual 题时 Grep ≤25，路径限 question.sibling_prefix 或 scope 目录）
- 每题 verdict: confirmed|refuted|inconclusive
- confirmed → 1 条 finding（schema 同 correctness-analyst，含 defect_mechanism、scenario、reachability、issue_origin）
- Write 仅：$REVIEW_TMP/findings/probes/<cluster_id>.json
```

- [ ] **Step 4:** 含 `answers[]` + `items[]` 输出 schema（见计划共享片段）

- [ ] **Step 5: Commit**

```bash
git add plugins/audit-code/agents/probe-worker.md
git commit -m "feat(audit-code): add probe-worker agent"
```

---

### Task 6: report-assembler

**Files:**
- Create: `plugins/audit-code/agents/report-assembler.md`

- [ ] **Step 1:** 复制 `finding-merger.md` 中 gate 列表（`meta_scope_not_a_defect`, `out_of_scope_style`, `vague_no_mechanism`, `misclassified_dimension`, `duplicate_cluster`, performance 封顶 P3、cluster pass 要点）为 **内嵌 § Merger gates**（可写「与 finding-merger 一致」并摘录 reject_reason 表）

- [ ] **Step 2:** 复制 `report-writer.md` 四节模板 + R15/R16 + **根因原理** 行顺序

- [ ] **Step 3:** 输入：
  - `findings/probes/*.json`
  - `change-context.json`（含 narrative）
  - `scope.json`
  - 可选写 `findings/merged.json`、`findings/rejected.json`

- [ ] **Step 4:** 输出：Markdown **返回主线程**（不写仓库）；§4 仅 `REVIEW_RESULT=...`

- [ ] **Step 5:** tools: `Read`, `Write`（仅 REVIEW_TMP）

- [ ] **Step 6: Commit**

```bash
git add plugins/audit-code/agents/report-assembler.md
git commit -m "feat(audit-code): add report-assembler agent"
```

---

### Task 7: SKILL.md — v2 主流程

**Files:**
- Modify: `plugins/audit-code/skills/review/SKILL.md`

- [ ] **Step 1:** description 与文首 spec 指针增加 `question-driven-design.md`

- [ ] **Step 2:** 在「工作流」前增加环境变量表：

```markdown
| 变量 | 效果 |
|------|------|
| `REVIEW_DEPTH=full` | should 题 + architecture 簇 |
| `REVIEW_LEGACY_DIMENSIONS=1` | 走 §Legacy 六维路径 |
| `REVIEW_KEEP_TMP=1` | 保留 REVIEW_TMP |
```

- [ ] **Step 3:** 插入阶段 **2c**（`bash scripts/audit-code-triage.sh "$REVIEW_TMP"`）、**2d**（`bash scripts/audit-code-hunk-index.sh "$REVIEW_TMP"`）

- [ ] **Step 4:** 重写 **3c 主编排出题**（主线程执行，不委派），含：
  - 读 `hunk-index.json`, `change-context.json`, `review-profile.json`
  - 写 `review-brief.md`（§ 结构见 design §6.2）
  - 写 `investigation-plan.json`（注入模板种子 §7.2；`must` ≥3；聚簇 2–3）
  - 标准题包回退（plan 不足时）

- [ ] **Step 5:** 替换阶段 4 为 **4′**：
  - 对每个 `clusters[]` 委派 `probe-worker`（prompt 含 `cluster_id`）
  - 并行委派 `narrative-writer`
  - 按 `review-profile` 跳过簇（如 `enable_security=false` 则不派 nonfunctional）

- [ ] **Step 6:** 阶段 5′ 仅委派 `report-assembler`；删除默认路径对 `finding-merger` + `report-writer` 的引用

- [ ] **Step 7:** 新增 **§Legacy（REVIEW_LEGACY_DIMENSIONS=1）**：保留现 3b→六维→merger→writer 全文（可从当前 SKILL 挪入）

- [ ] **Step 8:** 更新 Sub-agent 清单表

- [ ] **Step 9: Commit**

```bash
git add plugins/audit-code/skills/review/SKILL.md
git commit -m "feat(audit-code): question-driven review orchestration in SKILL"
```

---

### Task 8: verify 脚本

**Files:**
- Modify: `scripts/verify-audit-code-plugin.sh`

- [ ] **Step 1:** agent 列表改为默认 v2：

```bash
for a in change-context-analyst narrative-writer probe-worker report-assembler \
  finding-merger report-writer correctness-analyst architecture-analyst \
  security-analyst performance-analyst impact-analyst residual-defect-scout; do
  test -f "plugins/audit-code/agents/${a}.md"
done
```

- [ ] **Step 2:** 增加断言：

```bash
test -x scripts/audit-code-hunk-index.sh
test -x scripts/audit-code-triage.sh
rg -q 'investigation-plan' plugins/audit-code/skills/review/SKILL.md
rg -q 'review-brief' plugins/audit-code/skills/review/SKILL.md
rg -q 'probe-worker' plugins/audit-code/skills/review/SKILL.md
rg -q 'report-assembler' plugins/audit-code/skills/review/SKILL.md
rg -q 'REVIEW_LEGACY_DIMENSIONS' plugins/audit-code/skills/review/SKILL.md
rg -q 'question-driven-design' plugins/audit-code/skills/review/SKILL.md
rg -q 'review-brief.md' plugins/audit-code/agents/probe-worker.md
rg -q 'findings/probes' plugins/audit-code/agents/probe-worker.md
```

- [ ] **Step 3:** 运行

```bash
./scripts/verify-audit-code-plugin.sh
```

Expected: `OK: audit-code plugin structure`

- [ ] **Step 4: Commit**

```bash
git add scripts/verify-audit-code-plugin.sh
git commit -m "chore(audit-code): verify question-driven plugin layout"
```

---

### Task 9: 文档与 plugin.json

**Files:**
- Modify: `plugins/audit-code/.claude-plugin/plugin.json`
- Modify: `docs/installation.md`
- Modify: `docs/superpowers/specs/2026-06-04-review-plugin-design.md`（可选：文首加 v2 链接）

- [ ] **Step 1:** `plugin.json` description 改为含「问题驱动 / 主编排出题 / 六维 legacy」

- [ ] **Step 2:** `installation.md` audit-code 段补充：
  - 默认：主审出题 + 探针
  - `REVIEW_LEGACY_DIMENSIONS=1` 恢复六维
  - `REVIEW_DEPTH=full` 加深

- [ ] **Step 3: Commit**

```bash
git add plugins/audit-code/.claude-plugin/plugin.json docs/installation.md docs/superpowers/specs/2026-06-04-review-plugin-design.md
git commit -m "docs(audit-code): document question-driven review flow"
```

---

### Task 10: 本地试跑验收（人工）

- [ ] **Step 1:** `/reload-plugins` 或重装 audit-code@blueskills

- [ ] **Step 2:** 目标仓库对中型 bugfix PR 执行 `/audit-code:review`

- [ ] **Step 3:** 检查 `REVIEW_TMP`（`REVIEW_KEEP_TMP=1`）：
  - 存在 `hunk-index.json`, `review-profile.json`, `investigation-plan.json`, `review-brief.md`
  - `findings/probes/*.json` 数量 = 派发的簇数
  - sub-agent 调用次数 ≤5

- [ ] **Step 4:** stdout：
  - §1 含顶层调用链 + 用户侧/软件侧
  - §2/§3 finding 含根因原理
  - §4 仅一行 `REVIEW_RESULT`

- [ ] **Step 5:** 对比 `REVIEW_LEGACY_DIMENSIONS=1` 同 PR（可选）：确认 legacy 仍可用

- [ ] **Step 6:** 记录试跑耗时与问题，必要时收紧 probe Read 上限或 triage 规则（小提交）

---

## Spec 覆盖自检

| Spec 要求 | Task |
|-----------|------|
| triage `review-profile.json` | 2 |
| `hunk-index.json` | 1 |
| 主编排 3c plan+brief | 7 |
| probe-worker 契约 | 5, 7 |
| narrative-writer | 4, 7 |
| report-assembler gate+四节 | 6, 7 |
| `REVIEW_DEPTH=full` | 2, 7 |
| `REVIEW_LEGACY_DIMENSIONS=1` | 7 |
| 验收标准 verify | 8 |
| 保留旧 agent | 文件结构表 |

---

## 执行顺序建议

```text
Task 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10
     \___________ agents 可并行 ___________/
```

Task 7 依赖 3–6 的 agent 文件存在；Task 8 在 Task 7 之后。
