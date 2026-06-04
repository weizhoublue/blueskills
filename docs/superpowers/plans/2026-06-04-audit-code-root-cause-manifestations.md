# audit-code 根因聚合与表现点 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 同一根因只产出 1 条 P2 finding，终稿以「根因原理 + 表现点列表」呈现多处位置与各自后果；上游少派重复题、下游 assembler 兜底合并。

**Architecture:** 主编排 3c 先归纳 `root_cause_key` 再写 `investigation-plan`（一因一题、`scopes[]`）；`probe-worker` 同簇同 key 合并为单条 `items[]` + `manifestations[]`；`report-assembler` 在 cluster pass 前执行 `root_cause pass`，终稿 `manifestations.length >= 2` 时用 **表现点** 格式。

**Tech Stack:** Claude Code plugin（Markdown agents + SKILL.md）、`scripts/verify-audit-code-plugin.sh`、无新二进制依赖。

**Reference:** [`docs/superpowers/specs/2026-06-04-audit-code-root-cause-manifestations-design.md`](../specs/2026-06-04-audit-code-root-cause-manifestations-design.md)

**Conventions:** 插件正文中文；`REVIEW_TMP`；不恢复已删除的六维 analyst。

---

## 文件结构

| 路径 | 操作 | 职责 |
|------|------|------|
| `plugins/audit-code/skills/review/SKILL.md` | Modify | 3c 按根因出题；spec 链接；`root_causes[]` |
| `plugins/audit-code/agents/probe-worker.md` | Modify | 簇内 `root_cause_key` 合并、`manifestations[]` |
| `plugins/audit-code/agents/report-assembler.md` | Modify | `root_cause pass`、表现点终稿、`duplicate_root_cause` |
| `plugins/audit-code/.claude-plugin/plugin.json` | Modify | version `0.2.3`，description 一句 |
| `scripts/verify-audit-code-plugin.sh` | Modify | rg 新关键字 |
| `docs/installation.md` | Modify | 表现点说明 + 一因多果示例 |
| `docs/superpowers/specs/2026-06-04-audit-code-question-driven-design.md` | Modify | §7 schema 增加 `root_cause_key`/`scopes[]` 指针（可选一节） |

---

## 共享片段

### investigation-plan 题目（新增字段）

```json
{
  "id": "Q-RC-1",
  "kind": "correctness",
  "priority": "must",
  "template": "semantic_compare",
  "root_cause_key": "parentref-pointer-semantic-compare",
  "hypothesis": "ParentReference 含指针字段，用 == 或 slices.Contains 比较地址而非语义值",
  "scopes": [
    "operator/pkg/gateway-api/status_route.go",
    "operator/pkg/gateway-api/routechecks/",
    "operator/pkg/gateway-api/gateway_reconcile.go"
  ],
  "scope": ["operator/pkg/gateway-api/routechecks/httproute.go"],
  "entry_ref": "Gateway Reconcile → setRouteStatuses",
  "peer_compare_refs": ["operator/pkg/httproute/"],
  "grep_tokens": ["ParentReference", "slices.Contains", "DeepEqual", "=="]
}
```

### finding item（probe / merged）

```json
{
  "root_cause_key": "parentref-pointer-semantic-compare",
  "title": "ParentReference 指针字段用 ==/Contains 导致语义比较失效",
  "severity": "P2",
  "finding_category": "correctness",
  "issue_origin": "pr_introduced",
  "primary_location": { "file": "…/httproute.go", "line": 59, "symbol": "mergeStatusConditions" },
  "trigger": {
    "defect_mechanism": "…唯一根因段…",
    "failure_mode": "…可选摘要…",
    "scenario": { "precondition": "…", "trigger": "…", "bad_outcome": "…" }
  },
  "manifestations": [
    {
      "location": { "file": "…/status_route.go", "line": 18, "symbol": "pruneRouteParentStatuses" },
      "failure_mode": "跨命名空间剪枝失效…"
    }
  ],
  "related_symbols": [],
  "reachability": { "trace_summary": "…", "reachable_in_prod": true },
  "recommendation": "统一 ParentRef 值比较或 cmp.Equal"
}
```

---

### Task 1: SKILL.md — 主编排按根因出题

**Files:**
- Modify: `plugins/audit-code/skills/review/SKILL.md`

- [ ] **Step 1:** 在文件头 design spec 列表追加一行：

```markdown
；**根因聚合/表现点**：`docs/superpowers/specs/2026-06-04-audit-code-root-cause-manifestations-design.md`
```

- [ ] **Step 2:** 在「阶段 3c：主编排出题」的 `investigation-plan.json` 小节**最前**插入子节 **「按根因归纳（先于分簇）」**：

```markdown
   **按根因归纳（先于分簇，硬性）：**

   1. 从 `hunk-index` + `change-context` 列出候选根因，每项：`root_cause_key`（slug）、`summary`、`grep_tokens[]`。
   2. 写入 plan 根级 `root_causes[]`（与候选列表一致）。
   3. **每个逻辑类根因仅 1 道** `priority: must` 题，且带 `root_cause_key` + `scopes[]`（覆盖该根因所有触及路径）；**禁止**同一 `root_cause_key` 再按文件拆多道 must 题。
   4. `ripple` / `correctness` 题若与已有 `root_cause_key` 重叠 → 合并进该题的 `scopes[]` 或降为 `should`。
   5. `review-brief.md` 增加 **待验证根因**（≤5 bullet，来自 `root_causes[]`）。
   6. 典型 bugfix：`must` 逻辑根因题 ≤2 + residual（若 enable）+ 可选 security/architecture。
```

- [ ] **Step 3:** 在 `investigation-plan.json` 每题必填列表中追加：

```markdown
   - 带 `root_cause_key` 的题：**必填** `scopes[]`（≥1 路径前缀或文件）、`grep_tokens[]`（≥2）
   - plan 内同一 `root_cause_key`：**至多 1 道** `must` 题（`kind: residual` 除外）
```

- [ ] **Step 4:** 在标准题包示例 JSON 中给 `Q-001` 类题加上 `root_cause_key` + `scopes[]` 字段（可复制 spec §5.2 示例）。

- [ ] **Step 5:** 运行验证：

```bash
./scripts/verify-audit-code-plugin.sh
```

Expected: 可能仍 PASS（新 rg 在 Task 5）；至少无语法破坏。

- [ ] **Step 6:** 提交：

```bash
git add plugins/audit-code/skills/review/SKILL.md
git commit -m "feat(audit-code): plan investigations by root_cause_key"
```

---

### Task 2: probe-worker — 簇内合并与 manifestations

**Files:**
- Modify: `plugins/audit-code/agents/probe-worker.md`

- [ ] **Step 1:** 在「## finding 要求（`confirmed`）」**之前**插入新节 **「## 根因键与表现点（硬性）」**：

```markdown
## 根因键与表现点（硬性）

1. 每题读取 `root_cause_key`（若有）。本簇 `items[]` 中已存在相同 `root_cause_key` → **只向该条追加 `manifestations[]`**，禁止新建 item。
2. 单题带 `scopes[]`：按 scope 逐处验证；`confirmed` 的写入 `manifestations[]`；`refuted` 的不写入；全部 refuted → 无 item。
3. **`trigger.defect_mechanism` 仅写在 finding 顶层一次**；每个 manifestation 写自己的 `failure_mode`（与可选 `scenario` / `trace_summary`）。
4. `title` 描述根因类，不以单函数为唯一标题；`primary_location` 取 PR 核心或最严重处。
5. `root_cause_key` 格式：`[a-z0-9]+(-[a-z0-9]+)*`；无 plan 键时 probe **不得**自造多个 slug 拆成多条 P0–P2。
```

- [ ] **Step 2:** 在「## finding 要求」列表末尾追加：

```markdown
- `root_cause_key`：P0–P2 必填（来自题目）
- `manifestations[]`：P0–P2 至少 1 条；多 scope confirmed 时 ≥2
- `primary_location`：P0–P2 必填
```

- [ ] **Step 3:** 在「## 输出 `answers[]` 片段」示例中增加字段：

```json
"root_cause_key": "parentref-pointer-semantic-compare",
"manifestation_count": 2
```

- [ ] **Step 4:** 提交：

```bash
git add plugins/audit-code/agents/probe-worker.md
git commit -m "feat(audit-code): probe merge findings by root_cause_key"
```

---

### Task 3: report-assembler — root_cause pass 与表现点终稿

**Files:**
- Modify: `plugins/audit-code/agents/report-assembler.md`

- [ ] **Step 1:** 在「## 输入」列表追加：

```markdown
- `$REVIEW_TMP/investigation-plan.json`（`root_causes[]`、题目 `grep_tokens`）
```

- [ ] **Step 2:** 将「## 流程」第 2 步改为：

```markdown
2. **root_cause pass**（见下）→ **cluster pass**（见下；合并结果写入 `manifestations`）→ **line÷20 去重**。
```

- [ ] **Step 3:** 在「## 聚类合并（cluster pass）」**之前**插入 **「## 根因合并（root_cause pass）」**：

```markdown
## 根因合并（root_cause pass）

在 cluster pass **之前**执行。

| 条件 | 动作 |
|------|------|
| 相同非空 `root_cause_key` | 合并为 1 条；`manifestations` 并集；`defect_mechanism` 取更具体者 |
| 无 key，plan.`root_causes[].grep_tokens` 与 title/mechanism 命中 ≥2 | 赋 key 后合并 |
| 无 key，同 `finding_category` 且从 plan 题目提取的 `grep_tokens` 交集 ≥2 | 合并，`root_cause_key: inferred-<8hex>` |

合并规则：
- 仅 `location` 的 loser → 迁入 winner 的 `manifestations[]`（含 `failure_mode`，可从原 `trigger.failure_mode` 复制）。
- `related_symbols` 并集；`severity` 取最高。
- 被合并项 → `rejected.json`，`reject_reason: duplicate_root_cause`，`merged_into: <id>`。
```

- [ ] **Step 4:** 在 cluster pass 段末追加一句：

```markdown
- 当条目已共享 `root_cause_key` 或刚经 root_cause pass 合并时，**不要求**「同目录」才合并；机制词重叠时把 loser 写入 `manifestations`。
```

- [ ] **Step 5:** 替换终稿模板中 P1 示例块为双模式。在「#### P1 — 标题」后注明：

```markdown
**多表现点**（`manifestations.length >= 2`）：

#### P2 — 标题（根因类）
- **根因原理**：…
- **表现点**：
  1. `path:line` · `symbol` — **后果**：…
  2. …
- **可达性**：…
- **建议**：…（一条统一修复）

**单点**（无 `manifestations` 或 length < 2）：保留 **位置** + **根因原理** + **生产后果** + **场景** 格式。
```

- [ ] **Step 6:** 在「## REVIEW_RESULT」后追加：

```markdown
§4 结论可注明合并后条数，例如：`1 个 P2（含 3 处表现点）`（推荐，非强制）。
```

- [ ] **Step 7:** 提交：

```bash
git add plugins/audit-code/agents/report-assembler.md
git commit -m "feat(audit-code): assembler root_cause pass and manifestation report"
```

---

### Task 4: verify 脚本与 plugin 元数据

**Files:**
- Modify: `scripts/verify-audit-code-plugin.sh`
- Modify: `plugins/audit-code/.claude-plugin/plugin.json`

- [ ] **Step 1:** 在 `verify-audit-code-plugin.sh` 末尾 `echo OK` 之前追加：

```bash
rg -q 'root-cause-manifestations-design' plugins/audit-code/skills/review/SKILL.md
rg -q 'root_cause_key' plugins/audit-code/skills/review/SKILL.md
rg -q 'scopes\[\]' plugins/audit-code/skills/review/SKILL.md
rg -q 'root_cause_key' plugins/audit-code/agents/probe-worker.md
rg -q 'manifestations' plugins/audit-code/agents/probe-worker.md
rg -q 'root_cause pass' plugins/audit-code/agents/report-assembler.md
rg -q 'duplicate_root_cause' plugins/audit-code/agents/report-assembler.md
rg -q '表现点' plugins/audit-code/agents/report-assembler.md
```

- [ ] **Step 2:** 将 `plugin.json` 的 `version` 改为 `0.2.3`，`description` 末尾追加：`根因聚合（一因多表现点）。`

- [ ] **Step 3:** 运行：

```bash
./scripts/verify-audit-code-plugin.sh
```

Expected: `OK: audit-code plugin structure`

- [ ] **Step 4:** 提交：

```bash
git add scripts/verify-audit-code-plugin.sh plugins/audit-code/.claude-plugin/plugin.json
git commit -m "chore(audit-code): verify root_cause_key and bump plugin to 0.2.3"
```

---

### Task 5: 文档 — installation 与 question-driven spec 指针

**Files:**
- Modify: `docs/installation.md`
- Modify: `docs/superpowers/specs/2026-06-04-audit-code-question-driven-design.md`

- [ ] **Step 1:** 在 `docs/installation.md` 的 audit-code「并行验证」或「报告结构」段落后追加短节：

```markdown
**一因多表现点：** 同一根因（如 ParentReference 指针比较）在多处文件表现不同时，终稿合并为 **1 条** finding：**根因原理** 写一次，**表现点** 列表列出各 `path:line` 与各自后果；`REVIEW_RESULT` 按合并后条数计。
```

- [ ] **Step 2:** 在 `question-driven-design.md` §7 schema 示例题目的 JSON 中增加注释行或字段：

```json
"root_cause_key": "optional-slug",
"scopes": ["pkg/a/", "pkg/b/status.go"]
```

并在 §7 末加一句：「根因聚合见 `2026-06-04-audit-code-root-cause-manifestations-design.md`。」

- [ ] **Step 3:** 提交：

```bash
git add docs/installation.md docs/superpowers/specs/2026-06-04-audit-code-question-driven-design.md
git commit -m "docs(audit-code): document root-cause manifestation report format"
```

---

### Task 6: 本地验收（人工）

**Files:** 无

- [ ] **Step 1:** `/reload-plugins` 或重装 `audit-code@blueskills`。

- [ ] **Step 2:** 对曾产出 3 条 ParentReference P2 的中型 bugfix PR 执行 `/audit-code:review`，`REVIEW_KEEP_TMP=1`。

- [ ] **Step 3:** 检查 `REVIEW_TMP/investigation-plan.json`：
  - 存在 `root_causes[]`
  - 同一 `root_cause_key` 仅 1 道 must 逻辑题，且 `scopes[]` 覆盖多文件

- [ ] **Step 4:** 检查 `findings/probes/*.json`：同簇同 key 的 `items[]` 长度 ≤1（或 assembler 合并后 `merged.json` 仅 1 条）。

- [ ] **Step 5:** stdout §2：1 条 P2，含 **表现点** ≥2；§4 可为 `REVIEW_RESULT=mark_should_fix` 且注明「1 个 P2（含 N 处表现点）」。

- [ ] **Step 6:** 记录若仍拆条：查看 `rejected.json` 的 `duplicate_root_cause` / `duplicate_cluster` 是否生效；必要时收紧 SKILL 3c 或 assembler grep 阈值（小 PR 修复）。

---

## Spec 覆盖自检

| Spec § | 任务 |
|--------|------|
| §5 schema | Task 1–3 共享片段 + probe/assembler |
| §6 主编排 3c | Task 1 |
| §7 probe | Task 2 |
| §8 assembler | Task 3 |
| §9 文件清单 | Task 1–5 |
| §10 验收 | Task 4 verify + Task 6 人工 |

## 执行选项

计划已保存至 `docs/superpowers/plans/2026-06-04-audit-code-root-cause-manifestations.md`。

**1. Subagent-Driven（推荐）** — 每任务派生子 agent，任务间你做 review  
**2. Inline Execution** — 本会话按任务顺序直接改代码，检查点处暂停

你选 **1** 还是 **2**？若只说「实施」默认按 **2** 在本会话执行。
