# 设计文档：investigate-issue — 取消「问题后果」独立节，故障表现并入「触发条件」

- 日期：2026-06-04
- 状态：已实现（plan 2026-06-04）
- 父 spec：[`2026-06-03-investigate-issue-plugin-design.md`](2026-06-03-investigate-issue-plugin-design.md)
- 相关：R17 条件严谨性、R20 场景证据、[`2026-06-04-investigate-issue-mechanism-motivation-design.md`](2026-06-04-investigate-issue-mechanism-motivation-design.md)

## 1. 背景与问题

当前四节终稿中，**§2 问题后果** 与 **§3 触发条件** 在 R17（正向 + 反向条件）驱动下大量重复：§2 的「当 … 且 … 时」与 §3 的「须同时满足」往往是同一套配置/场景清单，读者需读两遍。

用户决策：

1. **取消独立「问题后果」节** — 该节不再讨论触发前提，也不讨论「代码层机制」（机制与因果归 **问题描述**；何时触发归 **触发条件**）。
2. **故障表现写入触发条件节** — 在「正向：须同时满足」清单**之后**，用固定子节 **「### 故障表现」** 集中描述满足条件时的用户/功能可见坏结果（方案 A：先条件、后表现）。

## 2. 目标

| 目标 | 说明 |
| --- | --- |
| 消除重复 | 正向触发清单只在报告中出现一次 |
| 读者路径清晰 | §1 懂「为什么/怎么坏的」→ §2 懂「何时坏 + 坏成什么样」→ §3 一行结论 |
| 实现成本可控 | **方案 1**：JSON 分析层可暂保留 `consequences`，由 writer 合并呈现 |

## 3. 非目标

- 不在本变更中重构 `trace.json` schema（不删除 `consequences` 字段）。
- 不改变结论节 R19（仍仅一行 `REVIEW_RESULT=`）。
- 不改变 issue-scout / business-context-analyst 职责。

## 4. 终稿结构（stdout）

| 节号 | 标题 | section id | 说明 |
| --- | --- | --- | --- |
| 1 | 问题描述 | `problem-description` | 业务叙事、机制动机 R18、前因后果链、兄弟对比 |
| 2 | 触发条件 | `trigger-conditions` | 正向清单 + **故障表现** + 不触发 + 输入到落点 |
| 3 | 结论 | `issue-verdict` | 仅 `REVIEW_RESULT=issue_true\|issue_false` |

附录 B（深化摘要）、附录 C（未闭合缺失项）不变。

**删除**：原 §2「问题后果」及 `sections/consequences.md` 的组装。

## 5. `trigger-conditions` 小节结构（issue-writer 必遵）

撰写顺序固定：

1. **`### 触发条件（正向：须同时满足）`**  
   - 仅 **confirmed** 且带 refs 的运行时状态/配置（R20）。  
   - 配置项可括注一句 **业务目的（W2）**。  
   - **禁止**在本子节写长段故障/症状叙事。

2. **`### 故障表现`**（**新增，必填**）  
   - 紧接正向清单之后。  
   - 描述：当上一节条件**同时**满足时，用户/评估/功能上**可观察到的坏结果**（如缺少 thinking 块、基准结果失真、panic、静默降级等）。  
   - 素材主要来自 `issue-analysis.json` 的 `consequences.user_impact`；若仅有 `code_level` 且用户不可感知，writer **不得**单独开「代码层机制」子节，可省略或并入一句用户可感知后果。  
   - **禁止**：再列一套与第 1 子节同文的「须同时满足」bullet。  
   - 证据 tier 与 refs 规则同全局。

3. **`### 未能从代码确认的前提（不应计入触发清单）`**  
   - 有 `inference` / `unverified[]` 场景时**必填**（R20）；不得与正向清单重复编号。

4. **`### 不触发 / 表现为正常的情形`**（**必填**，R17 反向）  
   - 吸收原「问题后果」节中的「何时不会出现该后果」类内容。  
   - 说明即使缺陷代码存在，因 dataset/参数/guard/cache 等**未走缺陷路径**而表现正常的情形。

5. **`### 从输入到落点的过程`**  
   - 业务化叙述配置/输入如何到达缺陷落点；可引用 `call_chain`。

6. **`### 代码佐证`**（可选）

## 6. 三节分工（防重复）

| 节 | 必须写 | 禁止写 |
| --- | --- | --- |
| 问题描述 | 业务故事、W1–W3、前因后果链、兄弟对比 | 完整正向触发编号清单；故障表现 bullet 清单 |
| 触发条件 | 正向清单、故障表现、不触发、路径过程 | 长段根因/机制复述（应已在 §1） |
| 结论 | 一行 verdict | 任何解释文字 |

## 7. 实现方案（推荐：方案 1 — 仅改报告层）

### 7.1 数据与分析链

- **code-tracer** 继续输出 `consequences`（`user_impact` / `code_level`）与 `trigger_conditions`。  
- 在 code-tracer 注释中注明：`consequences` **仅**供 writer 写入 `trigger-conditions` 的「故障表现」，**不**再生成独立报告节。  
- **主编排** 合并 `issue-analysis.json` 不变（仍含 `consequences` 字段）。  
- **issue-writer** `draft_all` 只 Write 三个 section 文件。

### 7.2 需修改的文件

| 文件 | 变更 |
| --- | --- |
| `plugins/investigate-issue/skills/investigate/SKILL.md` | section 表去掉 `consequences`；阶段 4/6 三节；stdout 模板；素材映射；全局红线 R17 表述改为仅针对 `trigger-conditions` |
| `plugins/investigate-issue/agents/issue-writer.md` | 删除 `consequences` 节模板；扩展 `trigger-conditions` 含「故障表现」 |
| `plugins/investigate-issue/agents/issue-challenger.md` | R17 扫描范围改为 `trigger-conditions`；新增反模式；`target_section` 去掉 `consequences`；原 consequences 类 gap 改指向 `trigger-conditions` |
| `plugins/investigate-issue/agents/code-tracer.md` | 注释/说明：`consequences` 供故障表现子节使用 |
| `plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh` | 断言三节文件、关键词「故障表现」、无 `consequences.md` 组装要求 |
| `docs/installation.md` | 终稿结构说明改为三节 |

### 7.3 不修改（本阶段）

- `issue-analysis.json` merge jq 字段列表  
- `business-context.json` / `scout.json` schema  
- 机制动机 R18、场景证据 R20 的实质规则（仅调整落节位置）

## 8. Challenger 规则增量

在 `trigger-conditions` 上增加：

| 反模式 | 级别 |
| --- | --- |
| 缺少 `### 故障表现` | blocking |
| 故障表现子节重复粘贴正向触发 bullet（同文条件清单） | blocking |
| 正向清单缺 R17 同时满足表述 | blocking |
| 缺 `### 不触发 / 表现为正常的情形` | blocking |
| 故障表现仅有代码内部状态、无用户/评估可观察描述 | major |

**删除**：对独立 `consequences` 文件的 R17 扫描。

`gaps[].target_section` 合法值：`problem-description` \| `trigger-conditions` \| `issue-verdict`。

## 9. stdout 组装模板（摘录）

```markdown
# 问题分析报告

> 分析目标：…
> 问题摘要：…

## 1. 问题描述
…

## 2. 触发条件
（须含：正向须同时满足 → 故障表现 → 不触发情形；禁止与 §1 重复机制长文。）

## 3. 结论
REVIEW_RESULT=issue_true
```

## 10. 示例（结构示意，非真实案例）

```markdown
### 触发条件（正向：须同时满足）
1. `dataset_name` 为 `spec_bench`（或 `custom_audio` / `custom_image`）…
2. CLI 传入 `--chat-template-kwargs` 且含 `enable_thinking: true` …
3. 模型为支持 thinking 的 reasoning 系列 …

### 故障表现
- 模型输出不包含 `<think>…</think>` 等 reasoning 块，仅最终答案 …
- spec_bench / 自定义多模态基准的评估结果无法反映 reasoning 能力，结论失真 …

### 不触发 / 表现为正常的情形
- 使用 `custom` 或 `speed_bench` 数据集（路径已正确传递 kwargs）…
- 未传 `--chat-template-kwargs` …
```

## 11. 验收标准

1. 运行 `/investigate-issue:investigate` 样例问题后，stdout **无** `## 2. 问题后果`（或等价独立节）。  
2. `## 2. 触发条件` 下存在 **「### 故障表现」**，且不在该子节重复完整正向条件列表。  
3. `ISSUE_TMP/sections/` 仅含 `problem-description.md`、`trigger-conditions.md`、`issue-verdict.md`（阶段 4 完成后）。  
4. `verify-investigate-issue-plugin.sh` 通过。  
5. challenger 可对「缺故障表现」「故障表现=第二份触发清单」报 blocking。

## 12. 后续可选（不在本 spec 范围）

- **方案 2**：将 `consequences.user_impact` 并入 `trigger_conditions.fault_manifestation[]`，删除顶层 `consequences`，统一 JSON 与报告。
