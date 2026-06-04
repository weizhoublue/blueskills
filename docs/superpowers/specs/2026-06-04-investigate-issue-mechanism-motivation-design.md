# 设计文档：investigate-issue — 机制动机层（W1–W3）与质检强化

- 日期：2026-06-04
- 状态：已审阅（brainstorming 确认）
- 父文档：[`2026-06-03-investigate-issue-plugin-design.md`](2026-06-03-investigate-issue-plugin-design.md)
- 兄弟 spec：[`2026-06-05-investigate-project-mechanism-motivation-design.md`](2026-06-05-investigate-project-mechanism-motivation-design.md)（同 W1–W3 语义，`key_mechanisms[]` 落点）；[`2026-06-05-investigate-issue-scenario-evidence-design.md`](2026-06-05-investigate-issue-scenario-evidence-design.md)（R20 场景证据，与 W 层正交）
- 背景：报告常出现「用于保持长连接等待新请求」类表述——说明了手段，未交代业务上为何需要长连接、不用会怎样，因果链缺「动机」层。

## 1. 问题陈述

读者（未读过仓库的新手）在 `problem-description` 中需要同时理解：

1. **发生了什么**（症状、架构）
2. **关键机制为何存在**（W 层：角色、动机、失灵后果）
3. **缺陷如何介入**（现有 B/C 层）

现有 **B1–B5**、**C0–C4**、**R16 叙事优先**、**R17 条件严谨** 未单独约束「中间机制的业务动机」。`issue-challenger` 亦未像 `investigate-project` 的 L3 那样检查「为何需要该设计」。

## 2. Brainstorming 决策摘要

| 决策点 | 选择 |
| --- | --- |
| 改造范围 | **C** — 优先 `issue-challenger` + `issue-writer` 小改 |
| 质检力度 | **B** — 动机缺失 = **major**；3 轮后可 `partial`，附录 C 列未补项 |
| 实现方案 | **方案 2** — `motivation_audit` + writer 固定子节 + 可选 `design_rationale[]` |
| 明确不做 | 新 sub-agent、编排新阶段、动机缺失误判 blocking、stdout 四节结构变更 |

## 3. 因果模型：W 层（与 B/C 正交）

在 **B1–B5（业务）**、**C0–C4（代码）** 之外，为**问题因果链上的关键机制**增加 **W1–W3（动机，业务抽象，非函数链）**：

| 层 | 含义 |
| --- | --- |
| **W1** | 该组件/配置在部署架构中的**业务角色** |
| **W2** | **为何**采用该手段（相对替代方案的好处/要解决的问题） |
| **W3** | 手段**失效或与对方不匹配**时如何衔接到可观察坏结果（B2） |

**规则：**

- W 层用业务语言；`path:line` 仅作括注或「代码佐证」子节。
- 不要求对文中每个术语做 W1–W3；仅 **关键机制**（用户描述、配置对比、超时/连接冲突中出现的项）。
- W2/W1 常为 `inference`；challenger **不得**要求升格为 `confirmed`（与现有 challenger 红线一致）。
- 禁止用「用于保持长连接等待新请求」等同义反复代替 W2。

**与既有规则：**

- **R16**：先业务故事、后 path:line。
- **R18（本设计新增）**：关键机制须可回答 W1–W3；由 challenger 以 **major** 执行，writer 用推荐子节承载。

## 4. issue-challenger 改造

### 4.1 新维度 `mechanism_motivation`

| 节 | 扫描 |
| --- | --- |
| `problem-description` | **必扫** |
| `consequences` | 仅当引用机制但未写「动机落空」 |
| `trigger-conditions` | 仅当配置键为主语且无业务目的 |
| `issue-verdict` | 不扫 |

**关键机制启发式：** 超时数值、keep-alive/idle/长连接/连接池、sidecar/proxy/router、与兄弟路径不同的配置项；同一机制重复出现仍无 W2 → 开 gap。

### 4.2 反模式 → gap（`severity: major`）

| 反模式 | dimension |
| --- | --- |
| 有手段无目的（缺 W2） | `mechanism_motivation` |
| 有配置无架构角色（缺 W1） | `mechanism_motivation` |
| 有动机未接到症状（缺 W3） | `mechanism_motivation` |
| 动机与后文矛盾 | `cross_section` |
| 术语挡 W1 | `terminology` |

`suggested_addition` 必须使用 **M1–M3 模板**（可粘贴骨架），禁止「写长一点」。

**M1（缺 W2）：** 读者知道 {手段}，但不知道在 {部署} 下为何不用 {替代方案}。

**M2（缺 W1）：** 未说明 {组件} 在请求路径中的角色即谈 timeout。

**M3（缺 W3）：** 未把 {A 端 Ta} 与 {B 端 Tb} 不一致接到 {symptom}。

### 4.3 `motivation_audit[]`

写入 `challenges/full-report-round-<N>.json`：

```json
{
  "mechanism": "sidecar HTTP idle timeout 90s",
  "field_hint": "problem-description §业务上发生了什么 第2段",
  "layers_present": ["W3"],
  "layers_missing": ["W1", "W2"],
  "severity_if_incomplete": "major"
}
```

### 4.4 resolution 与 R16 blocking

- 仅动机类 **major**、R16/R17/R19 已满足 → `needs_enrichment`。
- 第 3 轮仍有动机 major → `partial` + `full-report-final.json` / 附录 C。
- 动机 major **不单独**升级为 blocking（与用户选的 B 一致）。
- R16 blocking（如 code dump）优先于动机 major 的结构修复。

### 4.5 读者检验（增补）

遮住 `path:line` 后，对每个关键机制能否回答「为什么要有它？」「没有它会怎样？」— 任一不能 → `mechanism_motivation` major。

## 5. issue-writer 改造

### 5.1 `problem-description` 结构

在 `### 业务上发生了什么` 与 `### 前因后果链` 之间增加：

```markdown
### 关键机制为何如此设计
- **{机制名}**：
  - **角色（W1）**：…
  - **动机（W2）**：…；相对 {替代} …
  - **失灵时（W3）**：…
```

（2–4 条 bullet；每条 2–4 句。）

### 5.2 R18（writer）

1. 因果链上机制 ≥1 条含 W1+W2；W3 可在本子节或「前因后果链」出现一次。
2. supplement：`gap.dimension == mechanism_motivation` 时优先改本子节或「业务上发生了什么」首段；`rebuttals` 标明补了哪层。

### 5.3 其他节（轻量）

- `consequences`：「何时不会出现」可点明 W2 不成立的情形。
- `trigger-conditions`：配置项后括注一句 W2 业务目的。

## 6. business-context-analyst（可选）

`business-context.json` 增加可选 `design_rationale[]`：

```json
{
  "mechanism": "",
  "w1_role": "",
  "w2_why_not_alternative": "",
  "w3_when_breaks": "",
  "evidence_tier": "confirmed|doc_declared|inference",
  "refs": [],
  "uncertainty_note": ""
}
```

- analyst 软性步骤：对比兄弟模块时尽量写 1 条；无 code 证据用 `inference`。
- challenger **不得**因 analyst 未写而 gap analyst。
- `investigate/SKILL.md` 合并 `issue-analysis.json` 时透传 `design_rationale // []`。

## 7. 其他组件

| 组件 | 改动 |
| --- | --- |
| `code-tracer` | `business_meaning` 提示：连接/超时类步骤须写业务目的（W2） |
| `issue-scout` | 无 |
| `investigate/SKILL.md` | 全局红线 +R18；合并字段；终稿 §1 说明可有「关键机制为何如此设计」 |
| `verify-investigate-issue-plugin.sh` | grep R18、mechanism_motivation、motivation_audit、关键机制为何如此设计 |

## 8. 验收

### 8.1 回归样例（P/D + sidecar 90s vs prefill 5s）

**不合格：** 「Sidecar 配置 HTTP idle 90s，用于保持长连接等待新请求。」

**合格须含：** W1（sidecar 路由角色）、W2（复用连接、降延迟/开销 vs 短连接）、W3（5s vs 90s → RST/转发失败）。

### 8.2 自动化

- `verify-investigate-issue-plugin.sh` 通过扩展 grep。
- 不新增 LLM e2e eval。

## 9. Rollout

- 仅 marketplace 内 agent/skill 变更；`design_rationale` 缺失时合并为 `[]`。
- 报告可能变长：机制 bullet 上限 2–4 条；major 非 blocking，3 轮 partial 可接受。

## 10. 实现文件清单

```text
plugins/investigate-issue/agents/issue-challenger.md
plugins/investigate-issue/agents/issue-writer.md
plugins/investigate-issue/agents/business-context-analyst.md
plugins/investigate-issue/agents/code-tracer.md
plugins/investigate-issue/skills/investigate/SKILL.md
plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh
docs/superpowers/specs/2026-06-03-investigate-issue-plugin-design.md  # 可选：R18 交叉引用一段
```

## 11. 规则一览

| 规则 | 含义 |
| --- | --- |
| R16 | 叙事优先 |
| R17 | 条件严谨（正/反向） |
| R18 | 机制动机 W1–W3；challenger major |
| R19 | 结论仅一行 REVIEW_RESULT |
