# investigate-issue 场景证据（R20）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `investigate-issue` 对 §1–§3 中的运行时状态断言（「可能」「例如」「某些情况下」）强制代码核实：upstream 写入 `unverified[]` 与 tier；downstream challenger 以 **major** 检出 disguised-confirmed；writer 不得把 inference 场景列入「须同时满足」。

**Architecture:** 不新增 sub-agent。在 R16–R19 上叠加 **R20**：`code-tracer` 结构化 `when_triggers` + `unverified[]`；`issue-challenger` 输出 `scenario_evidence_audit[]` + S1–S3 gap 模板；`issue-writer` 增加「未能从代码确认的前提」子节；`SKILL.md` jq 合并 `unverified`。

**Tech Stack:** Claude Code sub-agent Markdown、`SKILL.md` 编排、`verify-investigate-issue-plugin.sh`（grep 结构校验）。

**Reference:** [`docs/superpowers/specs/2026-06-05-investigate-issue-scenario-evidence-design.md`](../specs/2026-06-05-investigate-issue-scenario-evidence-design.md)

**Conventions:**

- 插件 agent/skill **正文中文**；`description` 可补 R20 一句。
- 无 pytest；每 task 末尾跑 `bash plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh`（Task 1–5 可仅 rg 局部；Task 6 全量）。
- 场景未证实 **不得** 标 `blocking`（仅 `major`），与 spec §5.6 一致。

---

## 文件结构

| 路径 | 改动 | Task |
|------|------|------|
| `plugins/investigate-issue/agents/code-tracer.md` | `scenario_kind`、`unverified[]` 结构、R20 工作步骤 | 1 |
| `plugins/investigate-issue/agents/issue-challenger.md` | R20、`scenario_evidence_audit`、S1–S3 | 2 |
| `plugins/investigate-issue/agents/issue-writer.md` | 未能确认子节、正向清单规则、supplement | 3 |
| `plugins/investigate-issue/agents/business-context-analyst.md` | `non_trigger_scenarios` tier 软性对齐 | 4 |
| `plugins/investigate-issue/skills/investigate/SKILL.md` | 红线 15（R20）、jq `unverified`、终稿 §3 提示 | 5 |
| `plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh` | grep R20 关键词 | 6 |
| `docs/installation.md` | investigate-issue 流程一句 R20 | 7 |

---

## Task 1: code-tracer — upstream 场景证据

**Files:**

- Modify: `plugins/investigate-issue/agents/code-tracer.md`

- [ ] **Step 1: 在「条件严谨性 R17」后插入「场景证据 R20」小节**

在 `## 条件严谨性 R17（trace 层）` 表格之后、`## 输出 trace.json` 之前插入：

```markdown
## 场景证据 R20（trace 层）

| 要求 | 说明 |
| --- | --- |
| **运行时状态** | 每条 `when_triggers` / `consequences.conditional_on` 若描述对象状态（nil、未初始化、刚创建、迁移缺字段），须 `refs` 或 `inference` + `uncertainty_note` |
| **scenario_kind** | `when_triggers[]` 每项填 `runtime_state` \| `config` \| `code_path` |
| **禁止混写** | 单条 condition 不得写「例如 A 或 B」而无各自 refs；多场景拆多条 |
| **unverified** | 无法在仓库找到赋值/分支/测试路径时写入 `unverified[]`，**不得**标 `confirmed` |

**confirmed 对「会出现 nil」的最低标准：** 赋值/构造路径、缺陷分支、测试/fixture 之一；**仅** optional 字段类型定义 → 最多 `inference`。

**工作步骤（在填写 trigger 前执行）：**

1. 对每条运行时状态主张：Grep/Read 创建路径、nil 赋值、guard 分支、`_test.go`。
2. 找到 → `evidence_tier: confirmed`，`refs` ≥1。
3. 找不到 → `evidence_tier: inference`，`uncertainty_note` 含「未能从代码确认」，并追加 `unverified[]`：

```json
{
  "claim": "endpoint 刚创建时 CEP.Networking 为 nil",
  "search_attempted": "grep Networking; Read CEP reconcile create",
  "reason_unverified": "仅见 types.go optional，未见创建时省略 Networking"
}
```
```

- [ ] **Step 2: 更新 `when_triggers` JSON 示例**

将 `when_triggers` 数组项改为：

```json
    "when_triggers": [{
      "condition": "须同时满足的条件（配置/输入/运行时状态）",
      "business_meaning": "",
      "scenario_kind": "runtime_state|config|code_path",
      "evidence_tier": "confirmed|inference",
      "refs": ["path:line"],
      "uncertainty_note": ""
    }],
```

`consequences.code_level[].conditional_on` 说明处加一句：元素结构同 `when_triggers`（含 `scenario_kind`、`evidence_tier`、`refs`）。

- [ ] **Step 3: 扩展 `unverified[]` 示例**

将根级 `"unverified": []` 改为带一条示例的对象数组（与 Step 1 一致），并注：无则 `[]`。

- [ ] **Step 4: 更新 frontmatter description**

```yaml
description: 代码追踪员。基于 scout.json 追踪调用链；R17 条件化 + R20 场景 refs/unverified。Write 仅 trace.json。
```

- [ ] **Step 5: 局部校验**

```bash
rg -q 'scenario_kind|unverified|R20' plugins/investigate-issue/agents/code-tracer.md
```

Expected: exit 0

- [ ] **Step 6: Commit**

```bash
git add plugins/investigate-issue/agents/code-tracer.md
git commit -m "feat(investigate-issue): R20 scenario evidence in code-tracer"
```

---

## Task 2: issue-challenger — R20 与 scenario_evidence_audit

**Files:**

- Modify: `plugins/investigate-issue/agents/issue-challenger.md`

- [ ] **Step 1: 在 R18 与 R19 之间插入「场景证据 R20」**

```markdown
### 场景证据 R20（§1–§3 全文；优先 `trigger-conditions` 正向清单）

**目标：** 禁止把未证实的运行时场景写进「须同时满足」或 disguised-confirmed 叙述。

| 反模式 | 级别 |
| --- | --- |
| hedge + 无 refs（「在某些情况下可能」「例如 … 时」） | `major` |
| 正向清单含 disguised inference（有「可能/例如」未标 `(inference)`） | `major` |
| `confirmed` 但 refs 仅 optional 定义，未证明 nil 实例可达 | `major` |
| `issue-analysis.json` / trace `unverified[]` 有该项，正文仍列正向条件 | `major` |

**禁止：** 要求将纯 inference **升格**为 confirmed；因场景未证实单独判 `blocking`。

**S1（补证或降级）：**  
「条件 N 称『{场景}』。请给出创建/赋值/分支/测试的 path:line，或标 `(inference)` 并移出『须同时满足』。」

**S2（refs 不对题）：**  
「refs 仅证明字段 optional，未证明运行时 nil。请补实例路径或降级至未能确认前提。」

**S3（与 unverified 对齐）：**  
「分析产物 `unverified[]` 已含该主张，正文不得列为须同时满足。」
```

- [ ] **Step 2: 更新「其他」与「提问模板」**

`### 其他` 列表增加：

```markdown
- 场景证据 R20：`problem-description`、`consequences`、`trigger-conditions`（凡运行时状态断言）
```

提问模板末尾增加：

```markdown
14. **场景无证据**（target: trigger-conditions 或 consequences，`dimension: scenario_evidence`，用 S1）
15. **refs 不对题**（`dimension: scenario_evidence`，用 S2）
16. **与 unverified 矛盾**（`dimension: scenario_evidence`，用 S3）
17. **读者检验（场景）**：正向清单每条状态能否指向具体 path:line？不能 → `scenario_evidence` major
```

- [ ] **Step 3: 扩展输出 schema**

`gaps[].dimension` 枚举增加 `scenario_evidence`。

在 `motivation_audit` 说明后增加：

```markdown
### scenario_evidence_audit[]（与 gaps 同轮写入）

```json
{
  "claim": "endpoint 刚创建时 Networking 可能为 nil",
  "field_hint": "trigger-conditions §正向 条件2",
  "hedge_detected": true,
  "evidence_tier_in_text": "implied_confirmed|explicit_inference|ambiguous",
  "refs_present": false,
  "severity_if_incomplete": "major"
}
```

`hedge_detected: true` 且 `refs_present: false` → `gaps[]` 须有 `dimension: scenario_evidence`、`severity: major`。
```

更新 **complete 前提** 一句为：

```markdown
**complete 前提**：四节满足 R16/R17/R19；无 blocking。仅有动机/场景类 `major` → `needs_enrichment`；第 3 轮结束仍有动机或场景 `major` → `partial`。
```

- [ ] **Step 4: 更新 frontmatter description**

```yaml
description: 报告深化员。整稿评审；R18 机制动机 + R20 场景证据（major）。Write 仅 challenges/。
```

- [ ] **Step 5: Commit**

```bash
git add plugins/investigate-issue/agents/issue-challenger.md
git commit -m "feat(investigate-issue): add R20 scenario evidence to challenger"
```

---

## Task 3: issue-writer — 未能确认子节与正向清单

**Files:**

- Modify: `plugins/investigate-issue/agents/issue-writer.md`

- [ ] **Step 1: 在「机制动机 R18」后增加「场景证据 R20」**

```markdown
## 场景证据（R20）

1. **正向触发清单**仅列 `issue-analysis.json` / trace 中 `evidence_tier: confirmed` 且带 refs 的运行时状态。
2. `inference` 或 `unverified[]` 中的场景 → **`### 未能从代码确认的前提（不应计入触发清单）`**（`trigger-conditions` 必填若存在此类主张；`problem-description` / `consequences` 按需）。
3. **禁止**无 refs 的「在某些情况下可能…」「例如 … 时」出现在正向编号条件中。
4. supplement：`gap.dimension == scenario_evidence` 时补 path:line、或标 `(inference)` 并移出清单；`rebuttals.responses[].text` 注明补证/降级/移出。
5. 可 Read `issue-analysis.json` 的 `unverified[]` 作为素材。
```

- [ ] **Step 2: 更新 `trigger-conditions` 结构**

在 `### 不触发 / 表现为正常的情形` **之前**插入：

```markdown
2. **`### 未能从代码确认的前提（不应计入触发清单）`** — 若有 inference/unverified 场景则必填；每条标 `(inference)` + 一句「未能从代码确认」；**禁止**与正向清单重复编号
```

原 `### 触发条件（正向）` 为第 1 条；后续序号顺延（不触发 → 3，从输入到落点 → 4，代码佐证 → 5）。

- [ ] **Step 3: 禁止形态增加 R20**

```markdown
- 「在某些情况下可能…」「例如 {场景}」且无 path:line 出现在「须同时满足」列表
- 将 `unverified[]` 主张写为正向触发条件之一
```

- [ ] **Step 4: 更新 frontmatter description**

```yaml
description: 问题报告撰写员。四节 Markdown；R18 机制动机 + R20 场景证据。Write 仅 sections/ 与 rebuttals/。
```

- [ ] **Step 5: Commit**

```bash
git add plugins/investigate-issue/agents/issue-writer.md
git commit -m "feat(investigate-issue): R20 unverified subsection in issue-writer"
```

---

## Task 4: business-context-analyst — 软性 tier 对齐

**Files:**

- Modify: `plugins/investigate-issue/agents/business-context-analyst.md`

- [ ] **Step 1: 在 `non_trigger_scenarios` 工作步骤补充**

找到填写 `non_trigger_scenarios[]` 的步骤，追加：

```markdown
- 每条若含「例如/可能」的业务场景：须 `evidence_tier` + `refs` 或 `inference` + `uncertainty_note`（未能从代码确认）；供 writer/challenger 交叉引用，**不**单独因缺失而 blocking。
```

- [ ] **Step 2: JSON 示例中 `non_trigger_scenarios` 项已有 `evidence_tier` 则确认含 `uncertainty_note` 说明**

在 `non_trigger_scenarios` 数组项示例确保：

```json
    "evidence_tier": "confirmed|inference",
    "refs": [],
    "uncertainty_note": ""
```

- [ ] **Step 3: Commit**

```bash
git add plugins/investigate-issue/agents/business-context-analyst.md
git commit -m "chore(investigate-issue): align non_trigger_scenarios with R20 tier"
```

---

## Task 5: investigate SKILL — R20 红线与 jq merge

**Files:**

- Modify: `plugins/investigate-issue/skills/investigate/SKILL.md`

- [ ] **Step 1: 全局红线追加第 15 条**

在现有第 14 条（R18）之后：

```markdown
15. **场景证据（R20）**：§1–§3 运行时状态断言须 `confirmed`+`path:line` 或标 `(inference)` 并移出「须同时满足」。禁止「在某些情况下可能」「例如…」无 refs 进正向清单。challenger 以 `major`（`scenario_evidence`）检出；3 轮后可 `partial`。upstream `code-tracer` 须写 `unverified[]`。
```

- [ ] **Step 2: issue-analysis.json schema 增加 unverified**

在 `design_rationale` 后增加：

```json
  "unverified": [{
    "claim": "",
    "search_attempted": "",
    "reason_unverified": ""
  }],
```

- [ ] **Step 3: jq 合并增加 unverified**

将阶段 3 的 `jq -s` 块改为：

```bash
  jq -s '{
    issue_summary: .[0].issue_summary,
    entry_points: .[1].entry_points,
    call_chain: .[1].call_chain,
    causal_narrative: .[2].causal_narrative,
    business_flow: .[2].business_flow,
    sibling_comparison: .[2].sibling_comparison,
    design_rationale: (.[2].design_rationale // []),
    consequences: .[1].consequences,
    trigger_conditions: .[1].trigger_conditions,
    non_trigger_scenarios: .[2].non_trigger_scenarios,
    unverified: (.[1].unverified // [])
  }' "$ISSUE_TMP/scout.json" "$ISSUE_TMP/trace.json" \
     "$ISSUE_TMP/business-context.json" \
    > "$ISSUE_TMP/issue-analysis.json"
```

- [ ] **Step 4: 终稿 §3 组装说明**

在 stdout 模板「## 3. 触发条件」说明处增加：

```markdown
（可含 `### 未能从代码确认的前提`：inference 场景不得计入「须同时满足」，见 R20。）
```

- [ ] **Step 5: 委派 prompt 红线条数**

若 SKILL 或阶段 5 模板有「全局红线: （N 条）」硬编码，改为 **（15 条）**。

- [ ] **Step 6: Commit**

```bash
git add plugins/investigate-issue/skills/investigate/SKILL.md
git commit -m "feat(investigate-issue): R20 global rule and unverified merge in SKILL"
```

---

## Task 6: verify 脚本 + 全量验收

**Files:**

- Modify: `plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh`

- [ ] **Step 1: 追加 grep（在 R18 检查之后）**

```bash
grep -q 'scenario_evidence\|scenario_evidence_audit\|R20' "$ROOT/agents/issue-challenger.md" || err "challenger missing R20 scenario_evidence"
grep -q '未能从代码确认\|R20' "$ROOT/agents/issue-writer.md" || err "writer missing R20 unverified subsection"
grep -q 'scenario_kind\|unverified' "$ROOT/agents/code-tracer.md" || err "code-tracer missing R20 scenario_kind/unverified"
grep -q 'R20\|unverified' "$SKILL" || err "SKILL missing R20 or unverified merge"
```

- [ ] **Step 2: 全量 verify**

```bash
bash plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh
```

Expected: `verify OK`

- [ ] **Step 3: Commit**

```bash
git add plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh
git commit -m "test(investigate-issue): verify R20 scenario evidence in plugin"
```

---

## Task 7: docs/installation.md

**Files:**

- Modify: `docs/installation.md`

- [ ] **Step 1: 更新 investigate-issue 流程第 2、3 点**

在 code-tracer 行追加：

```markdown
   - code-tracer 从配置/输入往下追函数级调用链；运行时状态（如「字段为 nil」）须有 path:line 或写入 `unverified[]`；
```

在 writer 行 `§1` 说明后或 `§3` 处追加一句（可合并进现有 bullet）：

```markdown
   - **§3 触发条件** 正向清单仅列代码已证实状态；未能证实的场景进「未能从代码确认的前提」，见 R20；
```

在 challenger 行 R18 后追加：

```markdown
、**场景证据是否核实（R20）**（禁止「在某些情况下可能…」无 refs 进正向清单）
```

- [ ] **Step 2: Commit**

```bash
git add docs/installation.md
git commit -m "docs: document investigate-issue R20 scenario evidence"
```

---

## Plan self-review（已完成）

| Spec § | Task |
|--------|------|
| §3 R20 定义 | Task 5 |
| §4 code-tracer | Task 1 |
| §5 challenger | Task 2 |
| §6 writer | Task 3 |
| §4.4 business-context 软性 | Task 4 |
| §7 SKILL + jq | Task 5 |
| §8 验收 grep | Task 6 |
| §9 installation | Task 7 |
| 不做 blocking / 新 agent | 全 plan |

无 TBD；无「similar to Task N」省略。

---

## Execution handoff

计划已保存至 `docs/superpowers/plans/2026-06-05-investigate-issue-scenario-evidence.md`。

**两种执行方式：**

1. **Subagent-Driven（推荐）** — 每 Task 派生子 agent，Task 间你做 review  
2. **Inline Execution** — 本会话按 Task 1→7 直接改文件并跑 verify  

你更倾向哪一种？回复 **1** 或 **2**（或「直接开始做」即 Inline）。
