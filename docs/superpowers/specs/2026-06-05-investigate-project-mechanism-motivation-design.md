# 设计文档：investigate-project — 机制动机层（W1–W3）增强（A+B）

- 日期：2026-06-05
- 状态：已审阅（brainstorming 确认）
- 兄弟 spec：[`2026-06-04-investigate-issue-mechanism-motivation-design.md`](2026-06-04-investigate-issue-mechanism-motivation-design.md)
- 上游：[`2026-06-02-report-depth-and-quality-agent-design.md`](2026-06-02-report-depth-and-quality-agent-design.md)（L1–L5、`report-quality-challenger`）
- 背景：功能/项目叙事常写「通过 sidecar / ext-proc / 长连接」却未交代机制在架构中的角色、相对替代方案的设计动机、配错时的后果；与 issue 插件同类浅层表述。

## 1. 问题陈述

`investigate-project` 已有 **L1–L5** 多层因果与 `causal_chain` / `contrast` / `mechanism_at_a_glance`，但：

- **L3** 覆盖「行业/默认做法为何不够」；
- **L4** 覆盖「本项目在哪一抽象阶段介入」；
- **未单独约束**叙事中出现的**中间机制**（长连接、idle 超时、sidecar、某 CRD 策略等）的 **W1 角色 / W2 动机 / W3 失灵后果**。

读者仍可能看到「用于保持长连接等待请求」类同义反复，而不知该机制为何存在。

## 2. Brainstorming 决策摘要

| 决策点 | 选择 |
| --- | --- |
| 范围 | **A** `features/<slug>.json` + **B** `project-overview.json` |
| 不做（本轮） | integrations、overview-md 专项 W 强制、feature-plan 变更、函数级调用链 |
| 方案 | **方案 2**：`key_mechanisms[]` + `report-quality-challenger` 审计 + scout/digger/principle 写作 + writer 渲染 |
| W vs L | L1–L5 不变；W 仅管具名机制，不替代 L3/L4 |
| 力度 | 动机缺失 → **major**；**不**单独 blocking |

## 3. W 层与 L1–L5 分工

| 层级 | 含义 | 落点 |
| --- | --- | --- |
| L1 | 触发情境 | `causal_chain` layer 1 / narrative |
| L2 | 可观察坏结果 | layer 2、`contrast` |
| L3 | 默认/行业做法为何不够 | layer 3（复杂主题必填） |
| L4 | 本项目在哪一抽象阶段介入 | layer 4、`mechanism_at_a_glance` |
| L5 | 用户侧改善/风险 | layer 5 |
| **W1** | 机制在架构/路径中的角色 | `key_mechanisms[].w1_role` |
| **W2** | 为何采用该手段（相对替代） | `key_mechanisms[].w2_why_not_alternative` |
| **W3** | 失灵/不一致时接到 L2 | `key_mechanisms[].w3_when_breaks` |

**口诀：** L3 = 不用本项目时大家怎么做仍痛；L4 = 本项目打断链的哪一段；W2 = 这一段里**某个零件**为何这样设计。

**关键机制启发式：** 超时、keep-alive/idle/连接池、sidecar/proxy/router、调度/解析组件名、与兄弟模块不同的配置策略。

## 4. 结构化字段：`key_mechanisms[]`

挂在 `scenarios[]` / `problems_solved[]` 每一项（项目级与功能级相同）：

```json
"key_mechanisms": [{
  "name": "ext-proc 长连接 / sidecar 90s idle",
  "w1_role": "≤120 字",
  "w2_why_not_alternative": "≤150 字",
  "w3_when_breaks": "≤120 字",
  "evidence_tier": "confirmed | doc_declared | industry_context",
  "refs": [],
  "uncertainty_note": ""
}]
```

- 建议每条 narrative **1–2** 个机制；简单能力可 `[]`。
- `mechanism_at_a_glance` = L4 一句摘要；**不能**代替 W2。
- `causal_chain` **禁止**新增 layer 6；W 只进 `key_mechanisms` 或 narrative。
- 无材料 → `[]`；challenger **不得**因空数组 gap 分析 agent。

## 5. report-quality-challenger

### 5.1 target

| target | 路径 |
| --- | --- |
| B | `project-overview.json` |
| A | `features/<slug>.json` |

### 5.2 `mechanism_motivation` 反模式（`severity: major`）

| 反模式 | 说明 |
| --- | --- |
| 手段复述 | 「用于保持连接…」无 W2 |
| 缺 W1 | 组件名无架构角色 |
| 缺 W3 | 未接 L2 后果 |
| `mechanism_at_a_glance` 过浅 | 仅组件+动词 |
| principle 步骤无动机 | 只有动作无为何 |

与 L 层：缺 L2/L4 仍 **blocking**；L3 已够但机制浅 → 仅 `mechanism_motivation` major。

### 5.3 `mechanism_motivation_audit[]`

```json
{
  "mechanism": "Gateway 侧 ext-proc 长连接",
  "field_path": "problems_solved[1].narrative",
  "layers_present": ["W1"],
  "layers_missing": ["W2", "W3"],
  "severity_if_incomplete": "major"
}
```

`issues[].suggestion` 使用 M1–M3 骨架（与 issue spec 一致，指向 `key_mechanisms` 或 narrative）。

**质询模板增补：** 14 机制 W2；15 机制 W1；16 机制 W3。

### 5.4 checklist_scores

- `project-overview` / `features/<slug>` 增加 `mechanism_motivation_ok`。
- `status: passed` 须该项为 `true`（可有 informational）。

### 5.5 收尾

第 5 轮仍有动机 major → `*-final.json` 的 `unresolved_issues`。

## 6. project-scout（B）

- 步骤 +1：识别关键机制，填 `key_mechanisms[]`。
- 八项自检 + 机制动机（W1+W2）。
- 回灌：优先补 `key_mechanisms` 与 narrative。

## 7. feature-digger（A）

- `principle` 各维度 statement：**动作 + 动机（W2 一句）**。
- 复杂主题（Disaggregated、Gateway+EPP、连接复用等）建议 `key_mechanisms` ≥1。
- 两阶段写作不变；禁止无 ref 的 W2 标 `confirmed`。

## 8. report-writer

- 若存在 `key_mechanisms[]`，在对应 `### <title>` 下渲染 **「关键机制与设计动机」** bullet（W1/W2/W3 小标题）。
- 无字段则不造节；禁止补造 W 内容。

## 9. validate-analysis-report.sh

- 若存在 `key_mechanisms[]`：每项 `name` 非空，`w1_role` 与 `w2_why_not_alternative` 长度 ≥ 10。
- **不**强制每条 `problems_solved` 必须有该字段。

## 10. 验收样例

**不合格：** 「Decode sidecar 通过长连接把请求转发到 prefill。」

**合格：** L4 at_a_glance + `key_mechanisms` 含 W1–W3（见 issue spec §8.1 P/D 样例，字段名改为 `key_mechanisms`）。

## 11. 与 investigate-issue 对齐

| 概念 | issue | project |
| --- | --- | --- |
| W 语义 | W1–W3 | 同左 |
| 字段 | `design_rationale[]` | `key_mechanisms[]` on NarrativeBlock |
| 质检 | `motivation_audit` | `mechanism_motivation_audit` |
| 力度 | major, 3 轮 | major, 5 轮 per target |

## 12. 实现文件清单

```text
plugins/investigate-project/agents/report-quality-challenger.md
plugins/investigate-project/agents/project-scout.md
plugins/investigate-project/agents/feature-digger.md
plugins/investigate-project/agents/report-writer.md
plugins/investigate-project/skills/report-features/SKILL.md
plugins/investigate-project/scripts/validate-analysis-report.sh
```

## 13. Rollout

- 旧 JSON 无 `key_mechanisms` → `[]`；challenger 仍扫 narrative 反模式。
- integrations / overview-md W 强制留待后续 spec。
