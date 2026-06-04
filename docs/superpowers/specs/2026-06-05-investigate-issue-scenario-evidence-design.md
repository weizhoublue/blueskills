# 设计文档：investigate-issue — 场景证据（R20）与模糊前提核实

- 日期：2026-06-05
- 状态：已审阅（brainstorming 确认）
- 父文档：[`2026-06-03-investigate-issue-plugin-design.md`](2026-06-03-investigate-issue-plugin-design.md)
- 相关 spec：[`2026-06-04-investigate-issue-mechanism-motivation-design.md`](2026-06-04-investigate-issue-mechanism-motivation-design.md)（R18 W 层；本设计 R20 与 W 层正交）
- 背景：触发条件等章节常出现「在某些情况下可能为空，例如 endpoint 刚创建但网络栈未初始化完成」——读者无法区分代码已证明 vs 合理猜测，且猜测被写进「须同时满足」清单。

## 1. 问题陈述

报告（尤其 **§3 触发条件**，亦含 §1、§2）把**未证实的运行时场景**写成触发前提或业务事实，典型表述：

- 「在某些情况下可能…」
- 「例如 {对象} 刚创建时 {字段} 为 nil」
- 「或从旧版本迁移时缺失」（无 path:line）

读者会误以为这些场景已被代码印证。现有 **R17** 管正/反向逻辑结构，**R18** 管机制动机，**证据对齐（9.6）** 仅查 `confirmed` 是否缺 refs，**不**专门拦截「模糊 hedge + 无依据举例」。

## 2. Brainstorming 决策摘要

| 决策点 | 选择 |
| --- | --- |
| 无证据时的处理 | **B** — 标 **major**，要求补 `path:line`；3 轮仍无证据 → `unverified` / open question，**不得**作为已确认正向触发前提 |
| 执行链路 | **B** — **upstream + downstream**：`code-tracer` 结构化 + `issue-challenger` 扫终稿 |
| 覆盖范围 | **C** — §1–§3 凡含「例如 / 可能 / 某些情况下」等的**运行时状态断言**均适用（含 §2 `conditional_on` 叙述） |
| 3 轮后无证据 | 仅保留在「未能从代码确认的前提」子节，**不计入**「须同时满足」 |
| 严重级别 | **major**（同 R18）；不单独 **blocking**；3 轮后可有 `partial` |
| 明确不做 | 新 sub-agent、要求把纯 inference **升格**为 confirmed、改动 stdout 四节标题结构 |

## 3. 因果模型：R20 与证据 tier（与 R17/R18 正交）

| 规则 | 说明 |
| --- | --- |
| **R20** | 凡断言运行时状态/时序（刚创建、字段 nil、迁移缺字段、某分支会执行等），须 **confirmed + refs** 或 **inference + 未能从代码确认** |
| **禁止伪装** | 无 refs 时不得用 hedge 语把猜测写进「须同时满足」正向清单 |
| **与 challenger 红线** | 仍**不得**要求将纯 inference **证实**为 confirmed；但**必须**要求将 disguised-confirmed **降级或补证** |
| **与 R17** | R17 = 逻辑结构（正反向、非充分条件）；R20 = 场景是否有代码依据 |
| **与 R18** | R18 = 机制为何存在（W1–W3）；R20 = 触发/前提中的**状态是否真实可达** |

**`confirmed` 对场景主张的最低标准（须满足其一）：**

- 赋值/构造路径：`Networking` 被显式置 nil 或未初始化即写入
- 分支/守卫：代码在 `Networking == nil` 时走缺陷路径
- 测试/fixture/e2e：存在 nil 实例或等价 setup
- CRD/OpenAPI：仅证明 **optional** 不足以 `confirmed`「运行时会出现 nil」——须另有实例路径（否则 inference）

## 4. Upstream：`code-tracer` 改造

### 4.1 `when_triggers[]` / `consequences.conditional_on` 字段

在现有 `condition`、`evidence_tier`、`refs`、`uncertainty_note` 基础上：

| 字段 | 说明 |
| --- | --- |
| `scenario_kind` | `runtime_state` \| `config` \| `code_path` |
| `uncertainty_note` | `inference` 时必填；含「未能从代码确认」及简述已搜索范围 |

### 4.2 工作步骤（新增）

1. 每条**运行时状态**条件：在仓库内查找 nil 来源、未初始化路径、测试或 fixture。
2. 找到 → `evidence_tier: confirmed`，`refs` ≥1。
3. 找不到 → `evidence_tier: inference`，填 `uncertainty_note`，并写入 `unverified[]`：

```json
{
  "claim": "endpoint 刚创建时 CEP.Networking 为 nil",
  "search_attempted": "grep Networking, Read CEP create path",
  "reason_unverified": "仅见 optional 字段定义，未见创建时省略 Networking 的赋值路径"
}
```

4. **禁止**在 `when_triggers` 中单条混写「例如 A 或 B」而无各自 refs；多场景拆多条，各自 tier。
5. **禁止**无 code 分支证据时写「一定 / 必然」；与 R17 一致。

### 4.3 `issue-analysis.json` merge

主线程 jq 合并 `trace.json` 时保留 `unverified[]`（若 `business-context-analyst` 有同类场景，可并集去重）。

### 4.4 `business-context-analyst`（软性对齐）

`non_trigger_scenarios[]` 中业务侧「例如」场景：尽量 `refs` 或 `inference` + `uncertainty_note`；不作为 R20 blocking 来源，供 writer/challenger 交叉引用。

## 5. Downstream：`issue-challenger` 改造

### 5.1 新维度 `scenario_evidence`（R20）

**扫描范围：** `problem-description`、`consequences`、`trigger-conditions` 全文；优先 `trigger-conditions` 正向清单。

### 5.2 反模式 → `major`

| 反模式 | 说明 |
| --- | --- |
| hedge + 无 refs | 「在某些情况下可能」「例如 … 时」且无 path:line |
| 正向清单含 disguised inference | 条件条未标 `(inference)` 却含「可能/例如」 |
| confirmed 与 refs 不对题 | refs 仅 optional 定义，未证明 nil 实例可达 |
| 与 `unverified[]` 矛盾 | 分析中已 unverified，正文仍列为须同时满足 |

### 5.3 `scenario_evidence_audit[]`

与 `motivation_audit[]` 同轮写入 `challenges/full-report-round-<N>.json`：

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

`hedge_detected: true` 且 `refs_present: false` 时，`gaps[]` 须有 `dimension: scenario_evidence`、`severity: major`。

### 5.4 Gap 模板 S1–S3

**S1（补证或降级）：**  
「条件 N 称『{场景}』。请给出创建/赋值/分支/测试的 path:line，或标 `(inference)` 并移出『须同时满足』清单。」

**S2（refs 不对题）：**  
「refs 仅证明字段 optional，未证明运行时会出现 nil。请补实例路径，或降级并写入未能确认前提。」

**S3（与 unverified 对齐）：**  
「`issue-analysis.json` / `trace.json` 的 `unverified[]` 已含该主张，正文不得列为须同时满足条件。」

### 5.5 `gaps[].dimension` 扩展

增加：`scenario_evidence`。

### 5.6 resolution

- 仅有场景证据类 `major`、无 blocking → `needs_enrichment`。
- 第 3 轮结束仍有场景证据 `major` → `partial`（与 R18 一致）。
- **禁止**因场景未证实单独判 `blocking`。

### 5.7 读者检验（追加）

对每个进入正向触发清单的运行时状态：遮住 path:line，能否指出**哪段代码**保证该状态会出现？不能 → `scenario_evidence` major。

## 6. `issue-writer` 改造

### 6.1 正向触发清单

- 仅 **`confirmed`** 且带 refs 的场景可编号列入「须同时满足」。
- **`inference`** 场景不得进入该清单。

### 6.2 新子节（推荐）

在 `trigger-conditions`（必要时 `problem-description` / `consequences`）增加：

```markdown
### 未能从代码确认的前提（不应计入触发清单）
```

- 逐条列出 `unverified[]` / inference 场景，标 `(inference)`。
- supplement：`gap.dimension == scenario_evidence` 时优先改对应节；`rebuttals.responses[].text` 注明补证 / 降级 / 移出清单。

### 6.3 禁止形态

- 「在某些情况下可能为空，例如 …」且无 refs 出现在正向清单
- 将 `unverified` 主张写为「须同时满足」之一

## 7. 编排 `skills/investigate/SKILL.md`

1. 全局红线新增 **R20（场景证据）**；委派时与 R16–R19 一并复述。
2. `issue-analysis.json` schema 文档化 `unverified[]`（来自 trace merge）。
3. 终稿 §3 说明可选子节「未能从代码确认的前提」。
4. `verify-investigate-issue-plugin.sh`（可选）：grep 检查 challenger 含 `scenario_evidence`、`code-tracer` 含 `unverified` 说明。

## 8. 验收标准

| # | 标准 |
| --- | --- |
| 1 | 含「例如 endpoint 刚创建…nil」类句且无 refs 时，challenger 产出 `scenario_evidence` **major** gap |
| 2 | writer supplement 后：要么有条件级 refs，要么移出正向清单并标 inference |
| 3 | `trace.json` 中 inference 场景出现在 `unverified[]`，不与 `when_triggers` confirmed 混条 |
| 4 | 3 轮后 `partial` 时，未闭合项列入 final challenge / 未能确认子节 |
| 5 | 不破坏 R18：动机 inference 仍不必升格；R20 只禁止伪装成 confirmed 场景 |

## 9.  rollout

1. 改 `code-tracer.md` → `issue-challenger.md` → `issue-writer.md` → `SKILL.md` → `verify-investigate-issue-plugin.sh`
2. 更新 [`docs/installation.md`](../installation.md) investigate-issue 小节（R20 一句）
3. 不修改 stdout 四节标题；§3 仅多可选子节

## 10. 非目标

- investigate-project 同步（可后续单独 spec）
- 自动 grep 脚本替代 challenger 判断
- 要求为每个 open question 再跑一轮 code-tracer（除非主线程显式回流）
