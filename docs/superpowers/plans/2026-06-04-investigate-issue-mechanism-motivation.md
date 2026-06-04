# investigate-issue 机制动机层（R18 / W1–W3）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `investigate-issue` 报告对关键机制写出 W1–W3（角色、动机、失灵后果），由 `issue-challenger` 以 **major** 检出浅层「用于…等待…」类表述，并由 `issue-writer` 用固定子节承载。

**Architecture:** 不新增 sub-agent、不改 stdout 四节标题。在现有 R16/R17/R19 上叠加 **R18**：challenger 输出 `motivation_audit[]` + `gaps[].dimension=mechanism_motivation`；writer 增加 `### 关键机制为何如此设计`；`business-context-analyst` 可选 `design_rationale[]` 经 jq 合并进 `issue-analysis.json`。

**Tech Stack:** Claude Code sub-agent Markdown、`SKILL.md` 编排、`verify-investigate-issue-plugin.sh`（grep 结构校验）。

**Reference:** [`docs/superpowers/specs/2026-06-04-investigate-issue-mechanism-motivation-design.md`](../specs/2026-06-04-investigate-issue-mechanism-motivation-design.md)

**Conventions:**

- 插件内 agent/skill **正文中文**；`description` 可补一句 R18。
- 无 pytest；每 task 末尾跑 `bash plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh`。
- 动机缺失 **不得** 标为 `blocking`（仅 `major`），与 spec §4.4 一致。

---

## 文件结构

| 路径 | 改动 | Task |
|------|------|------|
| `plugins/investigate-issue/agents/issue-challenger.md` | R18 检查、`motivation_audit`、M1–M3 | 1 |
| `plugins/investigate-issue/agents/issue-writer.md` | 新子节、R18、supplement 指引 | 2 |
| `plugins/investigate-issue/agents/business-context-analyst.md` | `design_rationale[]` | 3 |
| `plugins/investigate-issue/agents/code-tracer.md` | `business_meaning` 一句 W2 提示 | 4 |
| `plugins/investigate-issue/skills/investigate/SKILL.md` | 红线 14、jq 合并、终稿 §1 提示 | 5 |
| `plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh` | grep R18 相关关键词 | 6 |

---

## Task 1: issue-challenger — R18 与 motivation_audit

**Files:**

- Modify: `plugins/investigate-issue/agents/issue-challenger.md`

- [ ] **Step 1: 在「深化检查维度」中 R17 之后插入「机制动机 R18」小节**

在 `### 条件严谨性 R17` 与 `### 结论 R19` 之间插入：

```markdown
### 机制动机 R18（`problem-description` 必扫；`consequences` / `trigger-conditions` 按 spec 条件扫）

**W 层（业务抽象，非函数链）：** W1=组件/配置在架构中的角色；W2=为何采用该手段（相对替代）；W3=失灵或与对方不匹配时如何接到可观察坏结果。

| 反模式 | 级别 |
| --- | --- |
| 只写手段、同义反复（如「用于保持长连接等待新请求」）而无 W2 | `major` |
| 谈 timeout/连接策略但未交代组件在请求路径中的角色（缺 W1） | `major` |
| 已写动机但未接到用户/运维可见症状（缺 W3） | `major` |
| 动机与后文后果/触发表述矛盾 | `major`（`dimension: cross_section`） |

**关键机制启发式（须逐条审计）：** 超时数值；keep-alive/idle/长连接/连接池；sidecar/proxy/router；与用户问题或兄弟对比相关的配置项。

**禁止：** 因缺 W2 单独判 `blocking`；要求将 inference 动机升格为 `confirmed`；`suggested_addition` 写「写长一点」。

**M1（缺 W2）** — `question` + `suggested_addition` 骨架：
「读者知道 {手段}，但不知道在 {部署} 下为何不用 {替代方案}。」
「在「业务上发生了什么」或「关键机制为何如此设计」补：在 {部署} 下，{组件} 通过 {手段} 以便 {业务目的}；若改为 {替代}，则 {代价}。」

**M2（缺 W1）** — 「未说明 {组件} 在请求路径中的角色即谈 timeout。」

**M3（缺 W3）** — 「当 {A} keep-alive {Ta} 与 {B} {Tb} 不一致时，{symptom} → {业务影响}。」
```

- [ ] **Step 2: 扩展「其他」与「提问模板」**

在 `### 其他` 列表增加：

```markdown
- 机制动机 W1–W3：`problem-description`（必查）；`consequences` / `trigger-conditions`（条件扫）
```

在「提问模板」末尾增加：

```markdown
10. **缺机制动机 W2**（target: problem-description，`dimension: mechanism_motivation`，用 M1）
11. **缺机制角色 W1**（target: problem-description，用 M2）
12. **动机未接症状 W3**（target: problem-description 或 consequences，用 M3）
13. **读者检验（机制）**：遮住 path:line，对每个关键机制能否回答「为什么要有它？」「没有它会怎样？」— 任一不能 → `mechanism_motivation` major
```

- [ ] **Step 3: 更新输出 schema**

将 `gaps[].dimension` 枚举改为包含 `mechanism_motivation`。

在 schema 示例后增加 `motivation_audit` 说明：

```markdown
### motivation_audit[]（与 gaps 同轮写入 full-report-round-N.json）

对每个关键机制一条：

```json
{
  "mechanism": "sidecar HTTP idle timeout 90s",
  "field_hint": "problem-description §业务上发生了什么 第2段",
  "layers_present": ["W3"],
  "layers_missing": ["W1", "W2"],
  "severity_if_incomplete": "major"
}
```

**resolution 补充：**
- 仅有动机类 `major`、R16/R17/R19 无 blocking → `needs_enrichment`
- 第 3 轮结束仍有动机 `major` → `partial`；`full-report-final.json` 列出 `mechanism_motivation` 未闭合项
```

- [ ] **Step 4: 更新 frontmatter description（一行）**

```yaml
description: 报告深化员（非对抗性质询）。对四节整稿评审；含 R18 机制动机 W1–W3（major）。Write 仅 challenges/。
```

- [ ] **Step 5: 运行校验（本 task 仅 challenger 关键词，完整校验在 Task 6）**

```bash
rg -q 'mechanism_motivation|motivation_audit|R18' plugins/investigate-issue/agents/issue-challenger.md
```

Expected: exit 0

- [ ] **Step 6: Commit**

```bash
git add plugins/investigate-issue/agents/issue-challenger.md
git commit -m "feat(investigate-issue): add R18 mechanism motivation checks to challenger"
```

---

## Task 2: issue-writer — 子节与 R18

**Files:**

- Modify: `plugins/investigate-issue/agents/issue-writer.md`

- [ ] **Step 1: 在「叙事优先 R16」后增加「机制动机 R18」**

```markdown
## 机制动机（R18）

1. `problem-description` 在 `### 业务上发生了什么` 与 `### 前因后果链` 之间**推荐**固定子节 `### 关键机制为何如此设计`（2–4 条机制 bullet）。
2. 每条机制须含 **W1 角色** + **W2 动机**；**W3 失灵**可在本子节或「前因后果链」出现一次。
3. **禁止**用「用于保持长连接等待新请求」等同义反复代替 W2（只复述手段 = 未满足 R18）。
4. 可 Read `issue-analysis.json` 的 `design_rationale[]`（若有）作为素材；新增动机主张标 `(inference)` 或 `(confirmed)`。
5. supplement：`gap.dimension == mechanism_motivation` 时优先改「关键机制为何如此设计」或「业务上发生了什么」首段；`rebuttals.responses[].text` 注明补了 W1/W2/W3 哪层。
```

- [ ] **Step 2: 更新 `problem-description` 结构列表**

在 `### 业务上发生了什么` 与 `### 前因后果链` 之间插入：

```markdown
2. **`### 关键机制为何如此设计`** — 2–4 条；每条含 W1/W2/W3（见 R18）；禁止 code dump
3. **`### 前因后果链`** — …（原第 2 条改为第 3 条，后续序号顺延）
```

- [ ] **Step 3: 轻量更新 consequences / trigger-conditions**

在 `consequences` 必含要素下增加一句：

```markdown
- 「何时不会出现」可点明 **W2 动机不成立** 的情形（如无 disaggregated 部署、无长连接场景）。
```

在 `trigger-conditions` 正向条件处增加：

```markdown
- 配置项后可用一句括注 **业务目的（W2）**，避免仅罗列键值。
```

- [ ] **Step 4: 禁止形态列表增加 R18 反例**

在「禁止的输出形态」增加：

```markdown
- 「{组件} 配置 {超时}，用于保持长连接等待新请求」且无 W1/W2（只有手段复述）
```

- [ ] **Step 5: Commit**

```bash
git add plugins/investigate-issue/agents/issue-writer.md
git commit -m "feat(investigate-issue): add W-layer subsection and R18 to issue-writer"
```

---

## Task 3: business-context-analyst — design_rationale[]

**Files:**

- Modify: `plugins/investigate-issue/agents/business-context-analyst.md`

- [ ] **Step 1: 工作步骤增加软性第 6 步**

```markdown
6. （软性）对问题因果链上的连接/超时/路由策略，尽量写 1 条 `design_rationale[]`（W1–W3 句子）；无 code 证据一律 `inference`。
```

- [ ] **Step 2: 在输出 JSON 示例中增加 design_rationale**

在 `business-context.json` 根对象增加：

```json
  "design_rationale": [{
    "mechanism": "sidecar long-lived HTTP to prefill",
    "w1_role": "",
    "w2_why_not_alternative": "",
    "w3_when_breaks": "",
    "evidence_tier": "inference",
    "refs": [],
    "uncertainty_note": ""
  }],
```

并注明：**可选**；无则 `[]`；challenger 不得因缺失 gap 本 agent。

- [ ] **Step 3: Commit**

```bash
git add plugins/investigate-issue/agents/business-context-analyst.md
git commit -m "feat(investigate-issue): optional design_rationale in business-context"
```

---

## Task 4: code-tracer — business_meaning W2 提示

**Files:**

- Modify: `plugins/investigate-issue/agents/code-tracer.md`

- [ ] **Step 1: 在「目的」段或 business_meaning 说明处增加一句**

在 `business_meaning` 字段说明处改为/补充：

```markdown
`business_meaning`: 该步在业务/用户视角下的含义（必填）。若该步体现连接复用、keep-alive、idle timeout、路由策略，须写清 **业务目的（W2：为何需要该策略）**，禁止仅写函数动作或「保持连接」。
```

- [ ] **Step 2: Commit**

```bash
git add plugins/investigate-issue/agents/code-tracer.md
git commit -m "chore(investigate-issue): prompt W2 in code-tracer business_meaning"
```

---

## Task 5: investigate SKILL — 红线 14、合并、终稿提示

**Files:**

- Modify: `plugins/investigate-issue/skills/investigate/SKILL.md`

- [ ] **Step 1: 全局红线追加第 14 条（原 13 条后）**

```markdown
14. **机制动机（R18）**：`problem-description` 对关键机制须可回答 W1–W3；禁止仅用「用于…保持…等待…」代替动机。challenger 以 `major`（`mechanism_motivation`）检出；3 轮后可 `partial`。**禁止**因缺 W2 单独判 blocking。
```

（若 SKILL 内红线编号与 spec 父文档一致为 13 条，则插入为第 14 条并检查编排「复述全局红线」处条数。）

- [ ] **Step 2: issue-analysis.json 合并 jq 增加 design_rationale**

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
    non_trigger_scenarios: .[2].non_trigger_scenarios
  }' ...
```

在 `issue-analysis.json` schema 示例（§证据模型附近）根级增加：

```json
  "design_rationale": [],
```

- [ ] **Step 3: 终稿模板 §1 问题描述说明补一句**

在「## 1. 问题描述」组装说明中增加：

```markdown
（可含 `### 关键机制为何如此设计`：W1 角色 / W2 动机 / W3 失灵，见 R18。）
```

- [ ] **Step 4: 委派 challenger/writer 的「全局红线」提示与条数一致**

确认阶段 5 prompt 模板写「全局红线: （14 条）」若主编排有硬编码条数则同步。

- [ ] **Step 5: Commit**

```bash
git add plugins/investigate-issue/skills/investigate/SKILL.md
git commit -m "feat(investigate-issue): R18 global rule and design_rationale merge in SKILL"
```

---

## Task 6: verify 脚本 + 全量验收

**Files:**

- Modify: `plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh`

- [ ] **Step 1: 在 agent 检查块末尾追加 grep**

在 `grep -q 'R19\|verdict' "$ROOT/agents/issue-challenger.md"` 之后追加：

```bash
grep -q 'mechanism_motivation\|motivation_audit\|R18' "$ROOT/agents/issue-challenger.md" || err "challenger missing R18 mechanism_motivation"
grep -q '关键机制为何如此设计\|R18' "$ROOT/agents/issue-writer.md" || err "writer missing R18 subsection"
grep -q 'design_rationale' "$ROOT/agents/business-context-analyst.md" || err "business-context missing design_rationale"
grep -q 'R18\|design_rationale' "$SKILL" || err "SKILL missing R18 or design_rationale merge"
```

- [ ] **Step 2: 运行全量 verify**

```bash
bash plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh
```

Expected: `verify OK`

- [ ] **Step 3: 人工回归样例（可选，非 CI）**

用 spec §8.1 不合格句作为 mock `sections/problem-description.md` 片段， mentally 或本地草拟 challenger 应产出：

- `motivation_audit[0].layers_missing` 含 `W2`
- `gaps[0].dimension == "mechanism_motivation"` 且 `severity == "major"`

不要求自动化 LLM 测试。

- [ ] **Step 4: Commit**

```bash
git add plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh
git commit -m "test(investigate-issue): verify R18 and mechanism_motivation in plugin"
```

---

## Plan self-review（已完成）

| Spec 章节 | Task |
|-----------|------|
| W1–W3 模型 | Task 1–2 正文 |
| challenger major + motivation_audit | Task 1 |
| writer 子节 + supplement | Task 2 |
| design_rationale 可选 | Task 3, 5 jq |
| code-tracer 提示 | Task 4 |
| verify grep | Task 6 |
| 不做 blocking / 新 agent | 各 task 已遵守 |

无 TBD；无「similar to Task N」省略。

---

## Execution handoff

计划已保存至 `docs/superpowers/plans/2026-06-04-investigate-issue-mechanism-motivation.md`。

**两种执行方式：**

1. **Subagent-Driven（推荐）** — 每 Task 派生子 agent，Task 间你做 review  
2. **Inline Execution** — 本会话按 Task 1→6 直接改文件并跑 verify  

你更倾向哪一种？回复 **1** 或 **2**（或「直接开始做」即 Inline）。
