# audit-code 根因机制、性能 P3 与聚类去重 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 audit-code 全链路加入 `trigger.defect_mechanism`（终稿 **根因原理**）、performance 纯性能封顶 P3 + 误分类拒收、merger 启发式 cluster 去重，消除「有场景无机制」与同根因重复 P2+P3。

**Architecture:** 扩展 canonical finding schema（correctness 为源）→ performance/correctness 维度分流 → finding-merger 在 line÷20 去重前做 cluster pass + 新 gate → report-writer 插入根因原理行。验收靠 `scripts/verify-audit-code-plugin.sh` 的 `rg` 断言，无 pytest。

**Tech Stack:** Claude Code plugin（Markdown agents + SKILL.md）、bash verify。

**Reference:** [`docs/superpowers/specs/2026-06-04-audit-code-mechanism-dedup-design.md`](../specs/2026-06-04-audit-code-mechanism-dedup-design.md)

**Conventions:** 插件正文中文；`REVIEW_TMP`；不修改 `plugins/audit/*`。

---

## 文件结构

| 路径 | 变更 |
|------|------|
| `plugins/audit-code/agents/correctness-analyst.md` | `defect_mechanism` + 三要素说明（canonical） |
| `plugins/audit-code/agents/performance-analyst.md` | 纯性能范围；自评 ≤P3；禁语义类 |
| `plugins/audit-code/agents/security-analyst.md` | schema 同步 |
| `plugins/audit-code/agents/architecture-analyst.md` | schema 同步 |
| `plugins/audit-code/agents/residual-defect-scout.md` | schema 同步 |
| `plugins/audit-code/agents/finding-merger.md` | cluster pass、新 gate、performance 封顶 |
| `plugins/audit-code/agents/report-writer.md` | **根因原理** 行与字段顺序 |
| `plugins/audit-code/skills/review/SKILL.md` | spec 指针、reject_reason、终稿字段 |
| `scripts/verify-audit-code-plugin.sh` | 新 rg 断言 |
| `docs/superpowers/specs/2026-06-04-audit-code-mechanism-dedup-design.md` | 状态 → 已审阅 |
| `docs/installation.md` | 可选一句（根因原理） |

---

## 共享片段：`defect_mechanism`（Task 2 写入 correctness，其它引用）

在 canonical schema 的 `trigger` 内增加：

```json
"trigger": {
  "defect_mechanism": "错在哪 + 为何该写法破坏不变量/语义 + 如何导致 bad_outcome（可含 1–3 行关键逻辑）",
  "description": "…",
  "failure_mode": "生产后果 + 具体字段/输入取值",
  "scenario": {
    "precondition": "…",
    "trigger": "…",
    "bad_outcome": "…"
  }
}
```

**硬性要求（P0–P2）：** `defect_mechanism` 非空且含：具体符号/字段、错误语义（如 `==` vs DeepEqual / nil 默认）、一步因果到后果。

**Analyst 分流（performance vs correctness）：**

- `slices.Contains` / `reflect.DeepEqual` / `ParentReference` 状态重复或误删 → **correctness**，可 P2。
- 仅复杂度、分配、热路径、无界循环 → **performance**，**最高 P3**。

---

### Task 1: Spec 状态

**Files:**
- Modify: `docs/superpowers/specs/2026-06-04-audit-code-mechanism-dedup-design.md`

- [ ] **Step 1:** 将文首 `状态：待审阅` 改为 `状态：已审阅（2026-06-04）`

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-06-04-audit-code-mechanism-dedup-design.md
git commit -m "docs(audit-code): mark mechanism-dedup spec reviewed"
```

---

### Task 2: correctness-analyst（canonical schema）

**Files:**
- Modify: `plugins/audit-code/agents/correctness-analyst.md`

- [ ] **Step 1:** 在「硬性要求」增加第 10 条：

```markdown
10. P0–P2 必填 `trigger.defect_mechanism`（错在哪 / 为何这么写会错 / 如何连到 bad_outcome）；禁止只写「可能影响」「语义不一致」而无字段级机制。
11. 比较语义、协调状态重复/误删类问题用 `finding_category: correctness`，即使 PR 动机含性能优化。
```

- [ ] **Step 2:** 在 schema JSON 的 `trigger` 中加入 `defect_mechanism` 字段（见上文共享片段）。

- [ ] **Step 3: Commit**

```bash
git add plugins/audit-code/agents/correctness-analyst.md
git commit -m "feat(audit-code): require defect_mechanism in correctness findings"
```

---

### Task 3: performance-analyst

**Files:**
- Modify: `plugins/audit-code/agents/performance-analyst.md`

- [ ] **Step 1:** 在「硬性要求」追加：

```markdown
- **仅**上报纯性能（复杂度、分配、热路径、锁竞争、无界循环）；**禁止**用 performance 描述状态错乱、parent status 重复/误删、DeepEqual/等价语义问题（由 correctness 上报）。
- `severity` **不得超过 P3**；`finding_category` 固定 `performance`。
- P0–P2 不适用本维度；若影响达到 P2 级语义错误，**不得**写入本文件。
- `trigger.defect_mechanism`：说明为何该复杂度/实现在规模下成为瓶颈（非状态逻辑）。
```

- [ ] **Step 2:** 将返回模板 `max_severity: P2` 改为 `max_severity: P3`。

- [ ] **Step 3: Commit**

```bash
git add plugins/audit-code/agents/performance-analyst.md
git commit -m "feat(audit-code): performance analyst pure-perf and cap P3"
```

---

### Task 4: security / architecture / residual schema 同步

**Files:**
- Modify: `plugins/audit-code/agents/security-analyst.md`
- Modify: `plugins/audit-code/agents/architecture-analyst.md`
- Modify: `plugins/audit-code/agents/residual-defect-scout.md`

- [ ] **Step 1:** 各文件 finding schema 的 `trigger` 增加 `defect_mechanism`（与 correctness 相同定义）。

- [ ] **Step 2:** 各文件硬性要求增加一句：`P0–P2 必填 trigger.defect_mechanism（同 correctness-analyst §硬性要求 10）。`

- [ ] **Step 3: Commit**

```bash
git add plugins/audit-code/agents/security-analyst.md \
  plugins/audit-code/agents/architecture-analyst.md \
  plugins/audit-code/agents/residual-defect-scout.md
git commit -m "feat(audit-code): sync defect_mechanism across analysts"
```

---

### Task 5: finding-merger — gate + performance + cluster

**Files:**
- Modify: `plugins/audit-code/agents/finding-merger.md`

- [ ] **Step 1:** 在「去重」之前插入新节「## 聚类合并（cluster pass）」：

```markdown
## 聚类合并（cluster pass，先于 line÷20 去重）

对全部待合并 finding，若 **同时满足 ≥2 条** 则视为同根因簇：

1. `finding_category` 相同；或均为 `correctness`。
2. `defect_mechanism` + `failure_mode` 归一化（小写、去标点、分词）后共享 ≥3 个实词（长度≥4 或：parentreference、deepequal、slices、contains、reflect、mergestatus、prune、group、kind、parent、status）。
3. 位置相关：`location.file` 的目录名相同；或一方 `location` 在另一方 `related_symbols` 中；或双方 `related_symbols` 有相同 `file`+`symbol`。

**合并策略：**

- 保留 severity 最高者；`related_symbols` 并集；`dimensions[]` 合并。
- 标题取更具体者；`defect_mechanism` 取更完整者。
- 被合并项 → `rejected.json`，`reject_reason: duplicate_cluster`，可选 `merged_into: <保留 id>`。

然后再执行 `file + line÷20 + 归一化标题` 去重。
```

- [ ] **Step 2:** 在「扩展 Gate」追加：

```markdown
- P0–P2 缺 `trigger.defect_mechanism` 或无法识别三要素（符号/错误语义/因果）→ `rejected`, `reject_reason: vague_no_mechanism`
- `finding_category == performance` 且 title/defect_mechanism/failure_mode 含：`状态`、`重复`、`误删`、`parent status`、`mergeStatus`、`等价`、`DeepEqual`、`语义不一致`、`协调错误` → `rejected`, `reject_reason: misclassified_dimension`
```

- [ ] **Step 3:** 在「Severity 调整」追加：

```markdown
- `finding_category == performance` → **强制 `severity: P3`**（与 dry_duplicate 并列）
```

- [ ] **Step 4:** 更新 `rejected.json` 示例的 `reject_reason` 枚举，加入：
  `vague_no_mechanism|misclassified_dimension|duplicate_cluster`

- [ ] **Step 5: Commit**

```bash
git add plugins/audit-code/agents/finding-merger.md
git commit -m "feat(audit-code): merger cluster dedup and mechanism gates"
```

---

### Task 6: report-writer

**Files:**
- Modify: `plugins/audit-code/agents/report-writer.md`

- [ ] **Step 1:** 在四节模板每条 finding 中，在「相关」与「场景」之间插入：

```markdown
- **根因原理**：…（`trigger.defect_mechanism`）
```

- [ ] **Step 2:** 在「硬性」小节增加：

```markdown
- P0–P2 无 `defect_mechanism` 的 finding 不应出现在 merged（merger 已拒收）；若出现则跳过该条并在内部备注，不编造根因。
- **禁止**用「生产后果」代替「根因原理」；二者分工：机制 vs 后果。
```

- [ ] **Step 3: Commit**

```bash
git add plugins/audit-code/agents/report-writer.md
git commit -m "feat(audit-code): report root-cause mechanism section"
```

---

### Task 7: skills/review/SKILL.md

**Files:**
- Modify: `plugins/audit-code/skills/review/SKILL.md`

- [ ] **Step 1:** 设计 spec 行增加：

```markdown
报告质量（机制/去重）：`docs/superpowers/specs/2026-06-04-audit-code-mechanism-dedup-design.md`
```

- [ ] **Step 2:** 在 finding / merger 说明处增加要点（列表即可）：

```markdown
- `trigger.defect_mechanism`：P0–P2 必填；终稿 **根因原理**
- `finding_category == performance` → merger 强制 P3；语义/状态类不得用 performance
- merger cluster pass → `duplicate_cluster`；缺机制 → `vague_no_mechanism`
```

- [ ] **Step 3:** 终稿 finding 字段顺序与 report-writer 一致（含根因原理）。

- [ ] **Step 4: Commit**

```bash
git add plugins/audit-code/skills/review/SKILL.md
git commit -m "docs(audit-code): SKILL sync mechanism-dedup spec"
```

---

### Task 8: verify-audit-code-plugin.sh

**Files:**
- Modify: `scripts/verify-audit-code-plugin.sh`

- [ ] **Step 1:** 在现有 `rg` 块后追加：

```bash
rg -q 'defect_mechanism' plugins/audit-code/agents/correctness-analyst.md
rg -q 'defect_mechanism' plugins/audit-code/agents/finding-merger.md
rg -q 'vague_no_mechanism' plugins/audit-code/agents/finding-merger.md
rg -q 'duplicate_cluster' plugins/audit-code/agents/finding-merger.md
rg -q 'misclassified_dimension' plugins/audit-code/agents/finding-merger.md
rg -q '根因原理' plugins/audit-code/agents/report-writer.md
rg -q 'finding_category == performance' plugins/audit-code/agents/finding-merger.md
rg -q 'mechanism-dedup-design' plugins/audit-code/skills/review/SKILL.md
rg -q '最高 P3' plugins/audit-code/agents/performance-analyst.md
```

- [ ] **Step 2:** 运行验证：

```bash
./scripts/verify-audit-code-plugin.sh
```

Expected: `OK: audit-code plugin structure`

- [ ] **Step 3: Commit**

```bash
git add scripts/verify-audit-code-plugin.sh
git commit -m "test(audit-code): verify defect_mechanism and cluster gates"
```

---

### Task 9: installation.md（可选一句）

**Files:**
- Modify: `docs/installation.md`

- [ ] **Step 1:** 在 audit-code 报告结构描述处追加：每条 P0–P2 缺陷含 **根因原理**（代码机制）；纯性能项为 P3。

- [ ] **Step 2: Commit**（可与 Task 8 合并提交亦可）

```bash
git add docs/installation.md
git commit -m "docs: mention audit-code root-cause mechanism in installation"
```

---

### Task 10: 本地试跑验收（人工）

- [ ] **Step 1:** 重装或 `/reload-plugins` audit-code@blueskills

- [ ] **Step 2:** 在被审仓库对 PR #46296（或同类 Gateway API PR）执行 `/audit-code:review`

- [ ] **Step 3:** 确认 stdout：

  1. 每条 P0–P2 有 **根因原理**（含 ParentReference/`==`/nil 等机制）
  2. ParentReference 语义类 **≤1 条** P2（correctness），无同义 P2+P3 对
  3. `O(m×n)` 仅 **P3**（performance）
  4. 仍无 Markdown 表格；§4 仅 `REVIEW_RESULT=...`

- [ ] **Step 4:** 若聚类仍漏合并，收紧 merger 实词表或降为「满足 ≥2 条中第 2+3 条即可」——回写 spec 附录后小提交（仅当试跑失败时）

---

## Plan 自检（对照 spec）

| Spec § | 任务 |
|--------|------|
| §5 defect_mechanism | Task 2, 4, 6 |
| §6 性能 vs 正确性 | Task 3, 5 |
| §7 cluster 去重 | Task 5 |
| §8 merger gate | Task 5 |
| §9 report-writer | Task 6 |
| §10 文件清单 | Task 2–9 |
| §11 验收 | Task 8, 10 |

- [x] 无 TBD / 占位步骤
- [x] reject_reason 名称与 spec 一致
- [x] 不引入新依赖
