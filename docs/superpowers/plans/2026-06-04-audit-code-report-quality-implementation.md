# audit-code 报告质量与四节终稿 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 升级 `audit-code` 插件，使 stdout 终稿为固定四节 Markdown（禁止表格），finding 含位置/符号/场景 gate，merger 拒收 meta-scope 与噪音，§1 由 `pr_narrative` 驱动。

**Architecture:** `change-context-analyst` 输出 `pr_narrative` → 七维 analyst 使用扩展 finding schema（analyst 禁报噪音）→ `finding-merger` 硬 gate → `report-writer` 四节模板。无新依赖、无 pytest；`scripts/verify-audit-code-plugin.sh` + `rg` 验收。

**Tech Stack:** Claude Code plugin（Markdown agents + SKILL.md）、bash verify。

**Reference:** [`docs/superpowers/specs/2026-06-04-audit-code-report-quality-design.md`](../specs/2026-06-04-audit-code-report-quality-design.md)

**Conventions:** 插件正文中文；变量 `REVIEW_TMP`；不修改 `plugins/audit/*`。

---

## 文件结构

| 路径 | 变更 |
|------|------|
| `plugins/audit-code/agents/change-context-analyst.md` | `pr_narrative` |
| `plugins/audit-code/agents/correctness-analyst.md` | 扩展 schema（canonical） |
| `plugins/audit-code/agents/readability-analyst.md` | 噪音禁报 |
| `plugins/audit-code/agents/architecture-analyst.md` | `dry_duplicate` 封顶 P3 |
| `plugins/audit-code/agents/security-analyst.md` | 引用 schema + 禁 meta-scope |
| `plugins/audit-code/agents/performance-analyst.md` | 同上 |
| `plugins/audit-code/agents/impact-analyst.md` | 禁止「改动面」finding |
| `plugins/audit-code/agents/residual-defect-scout.md` | schema + scenario |
| `plugins/audit-code/agents/finding-merger.md` | 新 gate + 黑名单 |
| `plugins/audit-code/agents/report-writer.md` | 四节模板 + R15 正反例 |
| `plugins/audit-code/skills/review/SKILL.md` | 终稿结构、schema 指针 |
| `scripts/verify-audit-code-plugin.sh` | 新 rg 断言 |
| `docs/installation.md` | 报告结构一句（可选） |
| `docs/superpowers/specs/2026-06-04-audit-code-report-quality-design.md` | 状态 → 已审阅 |

---

## 共享片段（Task 2 写入 correctness-analyst，其它 agent 引用）

以下 JSON 为 **canonical finding schema**（各 analyst 复制或写「同 correctness-analyst §finding schema」）：

```json
{
  "id": "C-001",
  "dimension": "correctness",
  "issue_origin": "pr_introduced",
  "finding_category": "correctness",
  "severity": "P1",
  "title": "简短标题",
  "location": {
    "file": "pkg/foo.go",
    "line": 42,
    "symbol": "pruneRouteParentStatuses"
  },
  "related_symbols": [
    { "file": "pkg/foo.go", "line": 200, "symbol": "setHTTPRouteStatuses" }
  ],
  "trigger": {
    "description": "…",
    "failure_mode": "生产后果 + 具体字段/输入取值",
    "scenario": {
      "precondition": "…",
      "trigger": "…",
      "bad_outcome": "…"
    }
  },
  "reachability": {
    "prod_entry_refs": ["cmd/app/main.go:28"],
    "trace_summary": "main → Run → foo:42",
    "reachable_in_prod": true,
    "blocked_by": null
  },
  "evidence": ["pkg/foo.go:40-45"],
  "suggestion": "…",
  "confidence": "high",
  "context_read": true
}
```

**Analyst 共同禁报（不得写入 findings JSON）：**

- 函数过长 / 超行数上限
- 缺少日志 / 缺少单元测试 / 缺少文档注释
- 仅描述「影响 N 种资源 / 核心模块 / 两个 controller」而无 `failure_mode` 的 meta-scope 项

---

### Task 1: 更新 design spec 状态

**Files:**
- Modify: `docs/superpowers/specs/2026-06-04-audit-code-report-quality-design.md`

- [ ] **Step 1:** 将文首 `状态：待用户审阅` 改为 `状态：已审阅（2026-06-04）`

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-06-04-audit-code-report-quality-design.md
git commit -m "docs(audit-code): mark report-quality spec as reviewed"
```

---

### Task 2: correctness-analyst — canonical schema

**Files:**
- Modify: `plugins/audit-code/agents/correctness-analyst.md`

- [ ] **Step 1:** 在 `## finding schema` 替换为上文 **canonical finding schema**（完整 JSON）。

- [ ] **Step 2:** 在 `## 硬性要求` 追加：

```markdown
4. `location.file` + `location.line` 必填；`location.symbol` 无法定位时写 `unknown` 并设 `confidence: medium|low`。
5. `trigger.scenario` 三段（precondition / trigger / bad_outcome）必填；`failure_mode` 须含可核对输入与生产后果。
6. **禁止**上报：函数过长、缺日志、缺单测、缺文档注释；禁止 meta-scope（仅改动面/资源类型数量）finding。
7. **禁止**将「触及核心模块」标为 P0；P0 仅用于生产主路径不可用类缺陷。
```

- [ ] **Step 3: Commit**

```bash
git add plugins/audit-code/agents/correctness-analyst.md
git commit -m "feat(audit-code): extend correctness finding schema and bans"
```

---

### Task 3: change-context-analyst — pr_narrative

**Files:**
- Modify: `plugins/audit-code/agents/change-context-analyst.md`

- [ ] **Step 1:** 在 `## 任务` 增加第 7 条：填写 `pr_narrative`（before_problem / after_fix / design_approach）。

- [ ] **Step 2:** 在 `## 输出 schema` 的 JSON 内增加：

```json
  "pr_narrative": {
    "before_problem": "…",
    "after_fix": "…",
    "design_approach": "…"
  },
```

- [ ] **Step 3:** 增加说明：改动面、子系统范围只写入 `pr_narrative` 或 `feature_positioning`，**不得**作为 finding 由下游上报。

- [ ] **Step 4: Commit**

```bash
git add plugins/audit-code/agents/change-context-analyst.md
git commit -m "feat(audit-code): add pr_narrative to change-context output"
```

---

### Task 4: readability-analyst — 噪音禁报

**Files:**
- Modify: `plugins/audit-code/agents/readability-analyst.md`

- [ ] **Step 1:** 新增 `## 禁止作为 finding` 列表（函数过长、缺日志、缺单测、缺文档注释、纯格式/linter）。

- [ ] **Step 2:** 写明：可读性 finding 仍须完整 schema（同 correctness）；若仅风格偏好且 `reachable_in_prod: false`，severity ≤ P2。

- [ ] **Step 3: Commit**

```bash
git add plugins/audit-code/agents/readability-analyst.md
git commit -m "feat(audit-code): readability analyst out-of-scope finding ban"
```

---

### Task 5: architecture-analyst — dry_duplicate 封顶 P3

**Files:**
- Modify: `plugins/audit-code/agents/architecture-analyst.md`

- [ ] **Step 1:** 增加：`finding_category: dry_duplicate` 仅用于跨文件重复逻辑；**severity 不得超过 P3**。

- [ ] **Step 2:** 禁止 meta-scope；schema 同 correctness。

- [ ] **Step 3:** 将 `max_severity` 返回示例改为 `P3`（若存在 P2 上限描述则改）。

- [ ] **Step 4: Commit**

```bash
git add plugins/audit-code/agents/architecture-analyst.md
git commit -m "feat(audit-code): cap DRY findings at P3 in architecture analyst"
```

---

### Task 6: security / performance / impact analysts

**Files:**
- Modify: `plugins/audit-code/agents/security-analyst.md`
- Modify: `plugins/audit-code/agents/performance-analyst.md`
- Modify: `plugins/audit-code/agents/impact-analyst.md`

- [ ] **Step 1 (security):** 增加「finding schema 同 correctness-analyst」+ scenario 必填 + 共同禁报列表。

- [ ] **Step 2 (performance):** 同上；强调热路径问题须给出 scenario 中的具体负载/规模（如 routes×parents 数量级）。

- [ ] **Step 3 (impact):** 在 `## 任务` 明确：**不得**产出仅描述「本 PR 影响 Standard Gateway + GAMMA / N 种 Route 类型」的 finding；impact finding 须有 call site / 兄弟路径上的具体 `failure_mode`。可引用 `impact.related_sites[]`。

- [ ] **Step 4: Commit**

```bash
git add plugins/audit-code/agents/security-analyst.md \
  plugins/audit-code/agents/performance-analyst.md \
  plugins/audit-code/agents/impact-analyst.md
git commit -m "feat(audit-code): align security/performance/impact with extended schema"
```

---

### Task 7: residual-defect-scout

**Files:**
- Modify: `plugins/audit-code/agents/residual-defect-scout.md`

- [ ] **Step 1:** 所有 `residual_existing` finding 使用 canonical schema（location.symbol、trigger.scenario 必填）。

- [ ] **Step 2: Commit**

```bash
git add plugins/audit-code/agents/residual-defect-scout.md
git commit -m "feat(audit-code): residual scout extended finding schema"
```

---

### Task 8: finding-merger — gates

**Files:**
- Modify: `plugins/audit-code/agents/finding-merger.md`

- [ ] **Step 1:** 在 `## ECC Pre-Report Gate` 后新增 `## 扩展 Gate` 表：

| 条件 | `reject_reason` |
|------|-----------------|
| 标题/描述匹配改动面、资源类型枚举、controller 清单，且无具体 failure_mode | `meta_scope_not_a_defect` |
| `finding_category` 或标题匹配：函数过长、缺少日志、缺少单元测试、缺少文档注释 | `out_of_scope_style` |
| 缺 `location.file` 或 `location.line` | `gate_failed` |
| 缺 `trigger.scenario` 任一段为空 | `vague_no_scenario` |
| `failure_mode` 仅含「可能」「边界情况」等无具体输入输出 | `vague_no_scenario` |

- [ ] **Step 2:** 新增 `## Severity 调整`：`finding_category == dry_duplicate` 或标题含「重复代码」「DRY」→ **强制 `severity: P3`**（保留在 merged）。

- [ ] **Step 3:** 增加启发式说明（供 merger 模型执行）：标题含「核心功能范围」「影响三种」且 trigger 空 → `meta_scope_not_a_defect`。

- [ ] **Step 4: Commit**

```bash
git add plugins/audit-code/agents/finding-merger.md
git commit -m "feat(audit-code): merger meta-scope, noise, and scenario gates"
```

---

### Task 9: report-writer — 四节终稿 + R15

**Files:**
- Modify: `plugins/audit-code/agents/report-writer.md`

- [ ] **Step 1:** 删除 `### 做得好的地方`、`### 验证说明`（可选：§1 末尾允许一行「建议验证：…」）。

- [ ] **Step 2:** 将 `## 结构` 整段替换为 spec §5 四节模板（`## Code Review 报告` → `## 1. 修改意图分析` … `## 4. 结论`）。

- [ ] **Step 3:** §1 从 `change-context.pr_narrative` 填四个 bullet；scope 来自 `scope.json`。

- [ ] **Step 4:** §2 仅 `issue_origin=pr_introduced`；§3 仅 `residual_existing`；按 P0→P1→P2→P3 排序；无则「无。」

- [ ] **Step 5:** 每条 finding 使用列表字段（位置、相关、场景、生产后果、可达性、建议）——**禁止 pipe 表**。

- [ ] **Step 6:** 新增 `## R15` 小节，粘贴 spec §11.1 反例/正例全文。

- [ ] **Step 7:** `REVIEW_RESULT` 规则不变；§4 仅一行；将原 `### 结论` 改为 `## 4. 结论`。

- [ ] **Step 8: Commit**

```bash
git add plugins/audit-code/agents/report-writer.md
git commit -m "feat(audit-code): four-section report template without tables"
```

---

### Task 10: review SKILL.md 同步

**Files:**
- Modify: `plugins/audit-code/skills/review/SKILL.md`

- [ ] **Step 1:** 将 `### 终稿结构` 替换为与 report-writer 一致的四节（删除「做得好的地方」）。

- [ ] **Step 2:** 在阶段 3b 说明产出含 `pr_narrative`；阶段 6 强调 R15 禁止表格。

- [ ] **Step 3:** 在 finding 全局要求中增加：`trigger.scenario`、扩展 `location`、merger 新 reject_reason 枚举。

- [ ] **Step 4: Commit**

```bash
git add plugins/audit-code/skills/review/SKILL.md
git commit -m "feat(audit-code): sync SKILL with four-section report and gates"
```

---

### Task 11: verify-audit-code-plugin.sh

**Files:**
- Modify: `scripts/verify-audit-code-plugin.sh`

- [ ] **Step 1:** 替换/追加 rg 检查：

```bash
rg -q '## 1. 修改意图分析' plugins/audit-code/agents/report-writer.md
rg -q '## 2. 发现的 PR 自身缺陷' plugins/audit-code/agents/report-writer.md
rg -q '## 3. 发现的仓库中的残留缺陷' plugins/audit-code/agents/report-writer.md
rg -q '## 4. 结论' plugins/audit-code/agents/report-writer.md
rg -q 'pr_narrative' plugins/audit-code/agents/change-context-analyst.md
rg -q 'trigger.scenario' plugins/audit-code/agents/correctness-analyst.md
rg -q 'meta_scope_not_a_defect' plugins/audit-code/agents/finding-merger.md
rg -q 'out_of_scope_style' plugins/audit-code/agents/finding-merger.md
rg -q 'dry_duplicate' plugins/audit-code/agents/architecture-analyst.md
rg -q '禁止' plugins/audit-code/agents/report-writer.md
rg -q 'pipe 表' plugins/audit-code/agents/report-writer.md
# 旧结构应不存在
if rg -q '做得好的地方' plugins/audit-code/agents/report-writer.md 2>/dev/null; then
  echo "report-writer must not require 做得好的地方" >&2
  exit 1
fi
if rg -q '### 摘要' plugins/audit-code/agents/report-writer.md 2>/dev/null; then
  echo "report-writer must use 四节结构 not ### 摘要" >&2
  exit 1
fi
```

- [ ] **Step 2:** 删除对 `### 结论` 的必选 rg（已改为 `## 4. 结论`）；保留 `R16` 在 SKILL 或 report-writer：

```bash
rg -q 'R16' plugins/audit-code/skills/review/SKILL.md
rg -q 'REVIEW_RESULT' plugins/audit-code/agents/report-writer.md
```

- [ ] **Step 3: 运行**

```bash
./scripts/verify-audit-code-plugin.sh
```

Expected: `OK: audit-code plugin structure`

- [ ] **Step 4: Commit**

```bash
git add scripts/verify-audit-code-plugin.sh
git commit -m "chore(audit-code): extend verify script for report-quality gates"
```

---

### Task 12: docs/installation.md（可选简短）

**Files:**
- Modify: `docs/installation.md`（`audit-code` 小节）

- [ ] **Step 1:** 在 audit-code 用法段增加一句：终稿为四节 Markdown（修改意图 / PR 缺陷 / 残留缺陷 / 结论），**不使用表格**。

- [ ] **Step 2: Commit**

```bash
git add docs/installation.md
git commit -m "docs: note audit-code four-section report format"
```

---

### Task 13: 人工试跑验收

- [ ] **Step 1:** 在被审仓库（如 Gateway API）执行 `/audit-code:review` + PR URL（或本地 diff）。

- [ ] **Step 2:** 检查 stdout：

  - 含 `## 1.` … `## 4.` 四节
  - §1 含修改前/后/方案
  - 无 `| ... |` 表格行
  - 无「做得好的地方」
  - §4 仅 `REVIEW_RESULT=...`
  - 无「核心功能范围」类 P0（应在 rejected 或不存在）

- [ ] **Step 3:** 若 `REVIEW_KEEP_TMP=1`，抽查 `merged.json` 含 `location.symbol` 与 `trigger.scenario`。

---

## Plan 自检（对照 spec）

| Spec 要求 | Task |
|-----------|------|
| 四节终稿 | 9, 10 |
| pr_narrative | 3, 9 |
| 扩展 schema + scenario | 2, 6, 7 |
| merger gates | 8 |
| 噪音禁报 | 4, 2, 8 |
| dry_duplicate P3 | 5, 8 |
| meta_scope 拒收 | 6, 8 |
| R15 禁止表格 | 9, 11 |
| P3 同列表 | 9 |
| verify 脚本 | 11 |

无 TBD；无「similar to Task N」省略代码。

---

## 执行方式

Plan 已保存至 `docs/superpowers/plans/2026-06-04-audit-code-report-quality-implementation.md`。

**两种执行方式：**

1. **Subagent-Driven（推荐）** — 每 Task 派生子 agent，Task 间人工/quick review  
2. **Inline Execution** — 本会话按 Task 顺序直接改文件，每 2–3 Task 设检查点

你更倾向哪一种？回复 `1` 或 `2`（或「直接开始做」即 Inline）。
