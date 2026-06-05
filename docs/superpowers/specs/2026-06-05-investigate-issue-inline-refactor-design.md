# Investigate-Issue 插件重构设计：单 SKILL.md 内联方案

## 背景与问题

`investigate-issue` 插件当前有 1 个主编排 SKILL.md + 5 个独立 agent 文件 + 1 个验证脚本。agent 之间通过 ISSUE_TMP 临时目录下的 JSON 文件传递中间产物（scout.json、trace.json、business-context.json、issue-analysis.json），并用 bash/jq 脚本合并。

**问题：**

- 读者需打开 6 个文件才能理解完整工作流；
- JSON schema 对人类不直观；
- ISSUE_TMP + jq 脚本增加了无谓复杂度，LLM 实际上不通过文件系统传递中间状态；
- 调试困难：中间产物散落在各文件，难以追踪。

## 目标

将所有逻辑内联到单一 `skills/investigate/SKILL.md`，所有阶段通过自然语言 Markdown 在 LLM 上下文中传递，消除文件系统依赖和 bash 脚本，同时保留所有质量规则（R15–R20、全局红线）。

## 方案选择

| 方案 | 描述 | 取舍 |
|------|------|------|
| **A（选定）** | 全内联自然语言，仿 audit 模式 | 最符合目标；人类可读；LLM 遵循自然 |
| B | 精简 JSON + 自然语言混合 | 仍有 JSON，未完全达成目标 |
| C | 拆多个 SKILL.md | 用户明确不要拆分 |

## 重构后架构

### 文件变更

| 操作 | 文件 |
|------|------|
| **重写** | `plugins/investigate-issue/skills/investigate/SKILL.md` |
| **删除** | `plugins/investigate-issue/agents/issue-scout.md` |
| **删除** | `plugins/investigate-issue/agents/code-tracer.md` |
| **删除** | `plugins/investigate-issue/agents/business-context-analyst.md` |
| **删除** | `plugins/investigate-issue/agents/issue-writer.md` |
| **删除** | `plugins/investigate-issue/agents/issue-challenger.md` |
| **删除** | `plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh` |
| **更新** | `plugins/investigate-issue/.claude-plugin/plugin.json`（description 和 version） |

### 工作流（与原相同，表达方式改变）

```
阶段0：自检（确认不在 marketplace 目录中运行）
↓
阶段1：问题信息搜集（inline issue-scout）
↓
阶段2：并行分析
  2a 代码追踪（inline code-tracer）
  2b 业务上下文分析（inline business-context-analyst）
↓
阶段3：主编排综合分析（原 jq 合并 → LLM 上下文内综合）
↓
阶段4：撰写三节初稿（inline issue-writer draft_all 模式）
↓
阶段5：整稿深化（最多3轮，inline issue-challenger + issue-writer supplement）
↓
阶段6：组装 stdout 终稿
```

## SKILL.md 结构设计

### 顶层元数据与角色

```yaml
---
name: investigate
description: ...
---

你是本次故障分析的**主编排者**。...
```

### 调用场景

与原相同，适用/不适用场景。

### 全局规则（自然语言替代原编号列表）

原 15 条全局红线改为两组规则，内嵌在正文：

**分析规则**（原红线 1–4、6–8、13）：
- 只读；禁止修改代码；禁止运行测试
- 证据优先：confirmed = 有 `path:line`；inference = 设计推断，须注明「未能从代码确认」
- 禁止编造；不确定写「未能从文档和代码中确认」
- 必须函数级调用链（本插件核心）
- 禁止无对比的局部分析：`problem-description` 须含兄弟分支对比
- challenger 禁止修改分析源；writer 不得与 confirmed 主张矛盾
- challenger 输出缺失清单后 writer 必须补充

**报告规则**（原红线 9–12、14–15）：
- 叙事优先（R16）：报告以业务前因后果为主体，代码佐证置后
- 条件严谨性（R17）：正向 + 故障表现 + 反向成对表述
- 机制动机（R18）：W1 角色 + W2 动机 + W3 失灵
- 结论格式（R19）：`sections/issue-verdict.md` 整文件仅一行 `REVIEW_RESULT=issue_true|false`
- 场景证据（R20）：运行时状态须 confirmed+refs 或标 (inference) 并移出正向清单
- 终稿 Markdown 禁止表格（R15）

### 证据模型（自然语言描述）

原 EvidenceClaim JSON schema → 三层文字说明：
- `confirmed`：代码可印证，随句附 `path:line`
- `doc_declared`：文档/CHANGELOG/ADR 声明，附文档路径
- `inference`：设计判断，句末注 `(inference)` 并说明「未能从代码确认」

### 阶段0：自检

自然语言描述：
- 检查当前是否在 marketplace 目录（存在 `plugins/investigate-issue/.claude-plugin/plugin.json`），若是则提示切换到被分析项目目录
- 提取 issue_brief（用户问题一行摘要）

### 阶段1：问题信息搜集

委派 sub-agent，附 issue_brief 和全局规则。

**工作内容**（来自 issue-scout.md）：
- 解析 issue_brief：提取现象、组件、错误类型、配置线索
- 建索引：Glob 文档/配置，Grep 关键词（限定路径）
- Read 预算：≤40 次（每次 ≤200 行）；Grep ≤15；Glob ≤10
- 排除：test/、vendor/、node_modules/ 等

**输出格式**（Markdown，非 JSON）：

```markdown
## 问题信息搜集结果

**问题摘要**：（≤150字，agent 对问题的理解）

**关键词**：[...]

**候选模块**：
- 模块名：... 代码路径：[...] 文档路径：[...] 原因：...

**入口线索**：
- 类型（config/env/api/cli）：... 线索：... refs：[...]

**相关文档**：
- 路径：... 相关性：...

**未解问题**：[...]
```

### 阶段2：并行分析

**2a 代码追踪**，委派 sub-agent，输入为阶段1 Markdown 输出 + issue_brief + 全局规则。

**工作内容**（来自 code-tracer.md）：
- 从候选模块和入口线索确定追踪起点
- 追踪函数级调用链 C0–C4（必须 confirmed + path:line）
- 填写触发条件（正向 + 反向）和后果（code_level + user_impact）
- 条件严谨性 R17：须找 guard、缓存、fallback、早退分支
- 场景证据 R20：运行时状态主张须 Grep/Read 创建路径

调用链层级说明（内嵌，代替 code-tracer.md 中的表格）：
- C0：用户可见入口（config/env/API/CLI/输入）
- C1：入口 → 第一层分发/路由
- C2：中间关键分支（guard、错误处理）
- C3：缺陷落点函数/分支
- C4：落点 → 可观察后果

**输出格式**（Markdown，代替 trace.json）：

```markdown
## 代码追踪结果

**入口点**：
- 类型：... ref：path:line 描述：...

**函数级调用链**：
- C0 `path:line` 函数名：动作... 业务含义：...
- C1 ...
- ...（每步须有 path:line 和业务含义）

**缺陷落点**：path:line，条件/分支：...

**触发条件**：
- 须同时满足：
  - 条件1（config）：... refs: path:line
  - 条件2（runtime_state）：... refs: path:line 或 (inference)
- 不触发情形：
  - 情形1：... 原因：... refs 或 (inference)

**后果**：
- 代码层：... conditional_on: [...] (confirmed) refs: path:line
- 用户影响：... (confirmed/inference)

**未能确认的主张**：
- 主张：... 搜索尝试：... 未确认原因：...
```

**2b 业务上下文分析**，委派 sub-agent，输入为阶段1 Markdown + issue_brief + 全局规则。

**工作内容**（来自 business-context-analyst.md）：
- 梳理业务上下游（B1–B5）
- 兄弟分支对比（必填，或说明 peer_not_found 原因）
- non_trigger_scenarios：业务/部署角度不触发情形
- design_rationale（软性）：W1–W3

**输出格式**（Markdown，代替 business-context.json）：

```markdown
## 业务上下文分析结果

**业务因果**：
- B1 情境（谁、什么部署/配置）：...
- B2 可观察坏结果：...
- B3 兄弟/默认路径为何不同：...
- B4 缺陷在业务流哪一段介入：...
- B5 功能/性能/可靠性影响：...

**业务流**：
- 上游：... (confirmed/inference) refs: [...]
- 下游：...
- 场景：...

**兄弟分支对比**：
- 对比对象：... 差异：... 是否同样有 bug：yes/no/unknown refs: [...]
- （或）未找到兄弟分支：原因...

**不触发场景**：
- 场景：... 原因：... (confirmed/inference)

**关键机制动机**（可选）：
- 机制：... W1 角色：... W2 为何不用替代：... W3 失灵接到症状：... (inference)
```

### 阶段3：综合分析

主编排者在上下文中综合阶段1、2a、2b 的 Markdown 输出，形成分析摘要（不写文件）。委派阶段4 sub-agent 时，将此综合摘要完整粘贴到 prompt 中作为输入。

综合内容：
- issue_summary（来自阶段1问题摘要）
- entry_points（来自阶段2a）
- call_chain（来自阶段2a）
- causal_narrative（来自阶段2b B1–B5）
- business_flow + sibling_comparison（来自阶段2b）
- design_rationale（来自阶段2b）
- consequences + trigger_conditions（来自阶段2a）
- non_trigger_scenarios（来自阶段2b）
- unverified（来自阶段2a）

### 阶段4：撰写三节初稿

委派 sub-agent（writer 角色），输入为阶段3综合分析 + 全局规则。

**工作内容**（来自 issue-writer.md draft_all 模式）：
- 按叙事优先 R16 写 `## 1. 问题描述`
- 按条件严谨性 R17 写 `## 2. 触发条件`
- 写 `## 3. 结论`（仅一行 `REVIEW_RESULT=...`）
- 机制动机 R18：`### 关键机制为何如此设计` 子节（W1+W2+W3）
- 场景证据 R20：inference/unverified 移到 `### 未能从代码确认的前提`

输出三节 Markdown 文本（不写文件，直接在对话中返回）。

### 阶段5：整稿深化（最多3轮）

**challenger 评审**，委派 sub-agent，输入为三节报告 Markdown + 全局规则。

**工作内容**（来自 issue-challenger.md）：
- 通读三节报告，以新手读者视角提问
- 检查维度：R16 叙事、R17 条件、R18 机制动机、R19 结论、R20 场景证据
- motivation_audit：对每个关键机制逐条扫描 W1/W2/W3
- scenario_evidence_audit：对正向清单每条运行时状态扫描

**输出格式**（Markdown，代替 challenges/full-report-round-N.json）：

```markdown
## 整稿评审（第N轮）

**评审结论**：needs_enrichment / complete / partial

**缺失清单**：
- [目标节] 严重程度（blocking/major）：... 建议补充：...

**机制动机审核**：
- 机制：... 已有层：[W1/W2/W3] 缺失层：[...] 严重程度：major

**场景证据审核**：
- 主张：... 是否有 refs：yes/no 严重程度：major
```

**rollback 规则**（第1轮，若 call_chain 维度 blocking ≥2）：重新委派代码追踪 sub-agent，重新综合，重新写初稿。rollback 最多1次。

**writer 补充**，委派 sub-agent，输入为当轮缺失清单 + 三节报告。

**输出**：更新后的三节 Markdown（或增量补充段落）。

循环最多3轮。若第3轮后仍有 blocking/major，保留最终评审报告附入附录C。

### 阶段6：组装 stdout 终稿

主编排者读取三节，按模板组装输出：

```markdown
# 问题分析报告

> 分析目标：<仓库名>
> 问题摘要：<issue_brief>

## 1. 问题描述
...

## 2. 触发条件
...

## 3. 结论
REVIEW_RESULT=issue_true

---
- 已代码确认：随句 path:line 或 (confirmed)
- 文档声明：(doc_declared)
- 未能从代码确认：(inference)

## 附录 B：报告深化摘要
- 整稿深化：N/3 complete|partial
- （若有 rollback）分析回滚：已执行 1 次 code-tracer 重追踪

## 附录 C：仍未补全的缺失项（若有）
- [target_section] blocking: ...
```

组装后自检：若含 `| ... |` 表格行，改写为 bullet 列表。

## plugin.json 更新

```json
{
  "name": "investigate-issue",
  "displayName": "Investigate Issue",
  "version": "0.4.0",
  "description": "针对软件项目单个故障做深度分析，生成完整报告（单 SKILL.md 内联，自然语言流转）",
  "keywords": ["issue-analysis", "code-tracing", "debugging"],
  "license": "MIT"
}
```

## 实现边界

**不在本次范围内**：
- `investigate-project` 插件（结构类似，但用户未要求）
- 对已有设计文档的修改

**保留不变**：
- 三节输出格式（problem-description、trigger-conditions、issue-verdict）
- 所有质量规则（R15–R20、全局红线）
- C0–C4 调用链深度模型
- W1/W2/W3 机制动机框架
- MAX_REVIEW_ROUNDS = 3
- rollback 逻辑（最多1次）
