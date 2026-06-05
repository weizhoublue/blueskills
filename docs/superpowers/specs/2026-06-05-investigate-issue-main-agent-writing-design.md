# Investigate-Issue：主线程撰写与改稿设计

## 文档关系

| 文档 | 关系 |
|------|------|
| `2026-06-05-investigate-plugins-markdown-handoff-design.md` | Phase 1 总设计（Markdown handoff、单 SKILL） |
| 本文 | **增量修订**：将原阶段 3+4 合并、阶段 5 补充员并入主编排；冲突时以本文为准 |

## 背景

`investigate-issue` v0.4.0 已采用单 `SKILL.md` + Markdown 阶段流转。当前工作流中：

- **阶段 3**：主编排仅在上下文中综合阶段 1、2a、2b 输出，不委派。
- **阶段 4**：再委派「报告撰写员」sub-agent，根据综合摘要写三节初稿。
- **阶段 5**：`needs_enrichment` 时委派「报告补充员」按缺失清单改稿。

这与 `plugins/audit/skills/review/SKILL.md` 不一致：audit 在 sub-agent 完成分析/质检后，由**主编排**执行「报告拼装」，不再委派撰写角色。

用户诉求：阶段 3（综合分析）与阶段 4（三节初稿）合并，由主编排直接完成；阶段 5 的改稿也并入主编排，**仅保留评审 sub-agent**（方案 B）。

## 目标

1. 主编排在**阶段 3**内完成：内部分析综合 + 三节初稿（原阶段 3+4）。
2. 阶段 5 在 `needs_enrichment` 时由**主编排**按缺失清单更新完整三节，不再委派「报告补充员」。
3. **保留**独立「报告评审员」sub-agent，避免自审盲区。
4. 保留 R15–R20、C0–C4、B1–B5、W1–W3、`MAX_REVIEW_ROUNDS=3`、rollback 逻辑（载体与委派对象调整）。
5. 对外行为不变：终稿仍仅 **stdout** 输出，含 `REVIEW_RESULT=`。

## 非目标

- 不修改 `investigate-project`。
- 不改变阶段 1、2a、2b 的 sub-agent 委派与 Markdown 模板。
- 不将「报告评审员」并入主编排（方案 C 拒绝）。
- 不新增磁盘中间产物或 JSON/jq。

## 方案选择

| 方案 | 描述 | 结论 |
|------|------|------|
| A | 仅合并阶段 3+4；阶段 5 评审+补充仍委派 | 拒绝：用户选择 B |
| **B** | 合并 3+4；阶段 5 仅委派评审，改稿在主线程 | **采用** |
| C | 评审与改稿均在主线程 | 拒绝：自审盲区过大 |

## 新工作流

```text
阶段0：自检 + issue_brief
阶段1：问题信息搜集（sub-agent）→ ## 问题信息搜集结果
阶段2：并行
  2a 代码追踪（sub-agent）→ ## 代码追踪结果
  2b 业务上下文（sub-agent）→ ## 业务上下文分析结果
阶段3：主编排 — 综合 + 撰写三节初稿（不委派）    ← 原阶段 3+4
阶段5：整稿深化 ≤3 轮
  - 委派：报告评审员
  - needs_enrichment：主编排按缺失清单输出完整三节（不委派补充员）
  - rollback：重跑 2a → 主编排重做阶段 3；round ← 1；最多 1 次
阶段6：主编排组装 stdout 终稿
```

**阶段编号**：保留 0/1/2/3/5/6，不插入新编号；SKILL 内阶段 3 标题注明「含原综合分析与三节初稿」。

## 主编排：阶段 3

### 输入

- `issue_brief`
- 阶段 1 Markdown 全文
- 阶段 2a、2b Markdown 全文
- 全局规则全文

### 步骤

1. **内部分析综合**（编排上下文，可不作为对外标题输出）  
   合并：问题摘要与关键词、C0–C4 与缺陷落点、触发条件与后果、B1–B5 与兄弟对比、不触发场景、关键机制动机（若有）、未能确认的主张。

2. **撰写三节初稿**  
   直接按 SKILL 中既有模板与 R16–R20 写出完整三节 Markdown（对话内返回，不写文件）。

### 三节结构与规则

与原阶段 4 完全一致，包括但不限于：

- `## 1. 问题描述`：`### 业务上发生了什么` → `### 关键机制为何如此设计`（W1/W2/W3）→ `### 前因后果链` → `### 为何此处有问题、兄弟路径没有` → `### 代码佐证`（可选）
- `## 2. 触发条件`：正向须同时满足 → 故障表现 → 未能从代码确认的前提（若有）→ 不触发/正常情形 → 从输入到落点的过程
- `## 3. 结论`：整节仅一行 `REVIEW_RESULT=issue_true` 或 `REVIEW_RESULT=issue_false`

禁止 markdown 表格；专名/缩写首现须解释。

## 主编排：阶段 5 改稿

当评审结论为 `needs_enrichment` 时：

- **不**委派 sub-agent。
- 主编排读取：当轮「缺失清单」Markdown、当前完整三节、全局规则、（建议）阶段 3 使用的分析综合要点或阶段 1/2a/2b 摘要。
- 按每条缺失项更新对应节（含 `结论`）；须逐条回应；无法补充时写「综合分析中暂无依据」。
- 输出：**完整三节** Markdown（非增量 diff）。
- 禁止与 `confirmed` 主张矛盾；新增主张须标 `(confirmed)` / `(doc_declared)` / `(inference)`。

## 仍委派的 sub-agent

| 阶段 | 角色 | 输出 |
|------|------|------|
| 1 | 问题信息搜集员 | `## 问题信息搜集结果` |
| 2a | 代码追踪员 | `## 代码追踪结果` |
| 2b | 业务上下文分析员 | `## 业务上下文分析结果` |
| 5 | 报告评审员 | `## 整稿评审（第 N 轮）` + 缺失清单 |

### 报告评审员 prompt 调整

- 输入：三节全文 + `issue_brief` + 全局规则 + 分析综合要点（或阶段 1/2a/2b 关键块粘贴）。
- 删除：「仅供阶段 4 撰写员使用的综合摘要」等仅面向已删除角色的表述。

### 删除的角色块

从 `SKILL.md` 移除：

- 「报告撰写员」（原阶段 4）
- 「报告补充员」（原阶段 5 补充）

## Rollback（阶段 5 内，最多 1 次）

条件不变：第 1 轮评审、`call_chain` 维度 `blocking` 条数 ≥ 2、且尚未 rollback。

新行为：

```text
重委派代码追踪 sub-agent（附 suggested_addition）
主编排重做阶段 3（综合 + 三节初稿）
rollback_used ← true
round ← 1
continue
```

不再出现「重委派撰写 sub-agent」。

## 全局规则：分工约束

**原：**

- 报告撰写 sub-agent 不得与 confirmed 主张矛盾
- 报告补充 sub-agent …
- 报告评审 sub-agent 输出缺失清单后，报告撰写 sub-agent 必须逐条补充

**改为：**

- 主编排撰写初稿与按清单改稿时，不得与 `confirmed` 主张矛盾。
- 报告评审 sub-agent 输出缺失清单后，主编排必须逐条回应（补充或说明暂无依据）。

## 文件变更

| 操作 | 路径 |
|------|------|
| 重写/修订 | `plugins/investigate-issue/skills/investigate/SKILL.md` |
| 更新 | `plugins/investigate-issue/.claude-plugin/plugin.json` → `0.4.1` |
| 更新 | `docs/installation.md`（工作流步骤描述） |
| 增补引用 | `docs/superpowers/specs/2026-06-05-investigate-plugins-markdown-handoff-design.md`（可选：文首「后续修订」链接本文） |

## plugin.json

```json
{
  "version": "0.4.1",
  "description": "针对软件项目单个故障做深度分析（单 SKILL.md；主线程撰写/改稿；仅评审委派）"
}
```

## 完成标准

- [ ] `SKILL.md` 无「报告撰写员」「报告补充员」委派步骤
- [ ] 阶段 3 明确由主编排完成综合+初稿；阶段 5 `needs_enrichment` 由主编排改稿
- [ ] rollback 伪代码指向「重做阶段 3」，无阶段 4 引用
- [ ] `docs/installation.md` 与 v0.4.1 描述一致
- [ ] 人工试跑：能完成分析并 stdout 含 `REVIEW_RESULT=`；`needs_enrichment` 路径可由主编排完成改稿

## 风险与缓解

| 风险 | 缓解 |
|------|------|
| 主编排上下文过长 | 阶段 3 先写内部分析摘要再写三节；2a/2b 模板已结构化 |
| 主线程改稿漏项 | 评审清单逐条回应；blocking 未闭合则 `partial` + 附录 C |
| 与 audit 模式不一致 | 明确对齐：分析委派、报告写作/拼装/改稿在主线程 |

## 测试策略

- 无新增 jq/脚本；以 SKILL 自检清单 + 人工试跑为主。
- 试跑一条真实 `issue_brief`，确认 stdout 结构与 `REVIEW_RESULT`。
- 若可构造 `needs_enrichment`，确认主编排能输出完整更新三节且无表格违规。
