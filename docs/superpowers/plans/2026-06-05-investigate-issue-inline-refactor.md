# Investigate-Issue 插件内联重构实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Phase 1：将 `investigate-issue` 插件改为 audit 式单 `SKILL.md`；阶段间仅用 Markdown 在 Task sub-agent 与主编排间传递；删除 JSON/jq/`ISSUE_TMP`/独立 `agents/*.md`。

**Architecture:** 重写 `skills/investigate/SKILL.md`（内联 scout / code-tracer / business-context-analyst / writer / challenger 职责与输出模板）；主编排在上下文综合（替代 jq）；终稿仍仅 stdout。Phase 2（`investigate-project`）见统一 spec §5，**不在本计划内**。

**Tech Stack:** Markdown（Cursor / Claude Code skill 格式）、Task sub-agent 委派

**Spec（权威）：** [`docs/superpowers/specs/2026-06-05-investigate-plugins-markdown-handoff-design.md`](../specs/2026-06-05-investigate-plugins-markdown-handoff-design.md) §4 Phase 1

**参考（细节对齐）：** [`docs/superpowers/specs/2026-06-05-investigate-issue-inline-refactor-design.md`](../specs/2026-06-05-investigate-issue-inline-refactor-design.md)

**对照实现：** [`plugins/audit/skills/review/SKILL.md`](../../../plugins/audit/skills/review/SKILL.md)

---

### Task 0: 实施前阅读（约 5 分钟）

**Files:** 只读

- [ ] **Step 1:** 阅读统一 spec Phase 1 完成标准
- [ ] **Step 2:** 浏览当前 `plugins/investigate-issue/skills/investigate/SKILL.md` 与 `agents/*.md`，确认本计划 Task 1 全文覆盖 R15–R20、rollback、三节结构
- [ ] **Step 3:** 浏览 `plugins/audit/skills/review/SKILL.md` 的「委派 + Markdown 输出」写法

---

### Task 1: 重写 SKILL.md（核心工作）

**Files:**
- Modify: `plugins/investigate-issue/skills/investigate/SKILL.md`

- [ ] **Step 1: 用以下内容完整替换 SKILL.md**

用以下全文覆盖 `plugins/investigate-issue/skills/investigate/SKILL.md`：

````markdown
---
name: investigate
description: 对软件项目的某个故障进行深入分析，对代码调用链、业务功能进行详细解读，理解业务背景、根因和影响
---

你是本次故障分析的**主编排者**。接收用户描述的问题，顺序委派各阶段 sub-agent，最终组装并输出完整的问题分析报告。禁止修改被分析仓库代码；禁止运行测试。

## 调用场景

**适用于如下场景**
- **故障解读** 对软件项目的某个故障进行深入分析，对代码调用链、业务功能进行详细解读，理解业务背景、根因和影响

**不适用于如下场景**
- 本地代码变更的质量审查
- 在线 PR 的质量评审
- 用户没有明确要求调用本 skill

---

## 全局规则

委派任何 sub-agent 时，**必须**在 prompt 中复述本节全部规则。

### 分析规则

- **只读**：禁止修改代码；禁止运行测试。
- **证据优先**：每个主张须声明证据层级：
  - `(confirmed)`：代码可印证，随句附 `path:line`（≥1 条）
  - `(doc_declared)`：文档/CHANGELOG/ADR 声明，附文档路径
  - `(inference)`：设计判断，未能从代码确认；句末注 `(inference)` 并说明「未能从代码确认」
- **禁止编造**：不确定时写「未能从文档和代码中确认」；无证据不写入正向触发清单。
- **必须函数级调用链**（本插件核心）：每步须有 `path:line` 和业务含义。
- **禁止无对比的局部分析**：问题描述须含兄弟分支对比，或明确说明未找到 peer。
- **分工约束**：
  - 代码追踪 sub-agent 禁止修改分析源文件；
  - 报告撰写 sub-agent 不得与 confirmed 主张矛盾；
  - 报告评审 sub-agent 输出缺失清单后，报告撰写 sub-agent 必须逐条补充。

### 报告规则

- **叙事优先（R16）**：报告以业务前因后果为主体；函数级调用链与 `path:line` 是分析依据，禁止把「文件:行号清单」当作根因正文。`problem-description` 须先写「业务上发生了什么」，再写因果链，代码佐证置后或括注。
- **条件严谨性（R17）**：触发条件须**正向（须同时满足）+ 故障表现 + 反向（不触发情形）**成对表述；禁止把单一配置/字段写成充分条件；须说明须同时满足的前置条件，以及即使缺陷存在也不触发的情形（如本地 cache、fallback、guard 早退）。
- **机制动机（R18）**：`问题描述` 对关键机制须可回答：W1 角色（组件/配置在架构中的角色）、W2 动机（为何采用该手段而非替代方案）、W3 失灵（失灵时如何导致可观察症状）；禁止仅用「用于…保持…等待…」等同义反复代替 W2；禁止因缺 W2 单独判 blocking。
- **结论格式（R19）**：结论节**整节仅一行** `REVIEW_RESULT=issue_true` 或 `REVIEW_RESULT=issue_false`；禁止任何其他文字、空行或说明。
- **场景证据（R20）**：正向触发清单仅列 `confirmed`+`path:line` 的运行时状态；`inference`/未验证的场景移到「未能从代码确认的前提」子节，不得计入正向清单；禁止「在某些情况下可能…」「例如…时」无 refs 进正向清单。
- **终稿禁止表格（R15）**：最终报告禁止使用 `| ... |` 或 HTML 表格；用 `###` 与列表。

---

## 工作流（严格顺序）

**MAX_REVIEW_ROUNDS = 3**（整份三节报告合计最多 3 轮深化，非每节独立计数）。

每次委派 sub-agent 时 prompt 必须含：
- 本节「全局规则」全文
- `issue_brief`（用户问题一行摘要）
- 本阶段所需的上游输出（Markdown 原文，完整粘贴）

### 阶段0：自检

1. 检查当前工作目录：若存在 `plugins/investigate-issue/.claude-plugin/plugin.json` 或根目录 `.claude-plugin/marketplace.json` 且无被分析项目特征，提示用户 `cd` 到待分析项目目录后退出。
2. 从用户输入提取 `issue_brief`（一行摘要，保留在编排上下文）。
3. 若输入不明确（只说「帮我分析」未指定问题），只问 1 个澄清问题，不猜测。

### 阶段1：问题信息搜集

委派 sub-agent（扮演**问题信息搜集员**角色），附 `issue_brief` 和全局规则。

**工作内容：**
- 从 `issue_brief` 提取：现象、可能组件、错误类型（panic/错误/性能等）、配置或环境线索
- 建立索引（先索引、后读取）：
  - Glob：`**/*.md`（限 `docs/`、根 README、模块 README）
  - Glob：配置/暴露面 `**/*config*.{go,py,yaml,json}`、`**/*crd*.yaml`、`**/cmd/**`、`**/api/**`
  - Grep：问题关键词、`panic`、`error`、用户提到的组件名（限定路径，禁止全仓无界 Grep）
  - Read 预算：≤40 次（每次 ≤200 行）；Grep ≤15；Glob ≤10
- 排除：`test/`、`tests/`、`__tests__/`、`spec/`、`.github/`、`vendor/`、`node_modules/`、`third_party/`

**输出格式（Markdown，在对话中返回，不写文件）：**

```
## 问题信息搜集结果

**问题摘要**：（≤150字，你对问题的理解）

**关键词**：[词1, 词2, ...]

**候选模块**：
- **模块名**：代码路径：[...] 文档路径：[...] 原因：...

**入口线索**：
- 类型（config/env/api/cli）：... 线索：... refs：[path:line]

**相关文档**：
- path/to/doc.md：相关性说明

**未解问题**：[...]
```

### 阶段2：并行分析

**并行**委派两个 sub-agent，均附阶段1 Markdown 输出 + `issue_brief` + 全局规则。

#### 2a 代码追踪

sub-agent 扮演**代码追踪员**角色。

**工作内容：**
- 从候选模块和入口线索确定追踪起点
- 追踪函数级调用链 C0–C4（每步须 `confirmed` + `path:line`；禁止无 refs 步骤）：
  - **C0**：用户可见入口（config/env/API/CLI/输入）
  - **C1**：入口 → 第一层分发/路由
  - **C2**：中间关键分支（guard、错误处理）
  - **C3**：缺陷落点函数/分支
  - **C4**：落点 → 可观察后果
- 调用链每步须填写**业务含义**（该步在业务/用户视角下的含义，禁止仅写函数名）
- 填写缺陷落点：`path:line` + 触发条件/分支
- 填写触发条件（R17）：须从代码中找 guard、缓存、fallback、早退分支，写正向和反向；禁止把单一配置写成充分条件
- 填写后果（代码层 + 用户影响），每条须条件化（须同时满足 + 不适用情形）
- 场景证据（R20）：对每条运行时状态主张，Grep/Read 创建路径、nil 赋值、guard 分支；找到 → `confirmed`；找不到 → `inference` 并加入「未能确认的主张」

**输出格式（Markdown，在对话中返回，不写文件）：**

```
## 代码追踪结果

**入口点**：
- 类型：config/env/api/cli ref：path:line 描述：...

**函数级调用链**：
- **C0** `path:line` 函数：`func_name` 业务含义：（该步在业务上意味着什么）
- **C1** `path:line` 函数：`func_name` 业务含义：...
- **C2** `path:line` 函数：`func_name` 业务含义：...
- **C3** `path:line` 函数：`func_name` 业务含义：（缺陷落点的业务意义）
- **C4** `path:line` 函数：`func_name` 业务含义：（可观察后果）

**缺陷落点**：`path:line` 条件/分支：...

**触发条件**：
- 须同时满足：
  - 条件1（config）：... refs: path:line (confirmed)
  - 条件2（runtime_state）：... refs: path:line (confirmed) 或 (inference)
- 不触发情形：
  - 情形1：... 原因：... refs 或 (inference)

**后果**：
- 代码层：...（须同时满足：[...]，不适用情形：[...]）(confirmed) refs: path:line
- 用户影响：... (confirmed/inference)

**未能确认的主张**：
- 主张：... 搜索尝试：... 未确认原因：...
```

#### 2b 业务上下文分析

sub-agent 扮演**业务上下文分析员**角色。

**工作内容：**
- 梳理业务因果 B1–B5：
  - **B1**：业务情境（谁、什么部署/配置）
  - **B2**：用户可观察的坏结果
  - **B3**：为何默认/兄弟路径没问题或也有隐患
  - **B4**：缺陷在业务流哪一段介入
  - **B5**：对用户功能/性能/可靠性的实际影响
- **兄弟分支对比**（必填）：≥1 个对比条目，或明确说明未找到 peer 及原因
- `inference` 须有 uncertainty_note（含「未能从代码确认」）；禁止把行业常识标为 `confirmed`
- 可选：对问题因果链上的关键机制写 W1–W3 动机说明（无 code 证据一律标 inference）

**输出格式（Markdown，在对话中返回，不写文件）：**

```
## 业务上下文分析结果

**业务因果**：
- B1 情境：...
- B2 可观察坏结果：...
- B3 兄弟/默认路径为何不同：...
- B4 缺陷在业务流哪一段介入：...
- B5 功能/性能/可靠性影响：...

**业务流**：
- 上游：... (confirmed/doc_declared/inference) refs: [...]
- 下游：...
- 场景：...

**兄弟分支对比**：
- 对比对象：... 差异：... 是否同样有 bug：yes/no/unknown refs: [...]
（或）未找到兄弟分支：原因...

**不触发场景**：
- 场景：... 原因：... (confirmed/inference)

**关键机制动机**（可选）：
- 机制：... W1 角色：... W2 为何不用替代：... W3 失灵接到症状：... (inference)
```

### 阶段3：综合分析

主编排者在上下文中综合阶段1、2a、2b 的 Markdown 输出，整合为分析摘要。委派阶段4 sub-agent 时，将此综合摘要完整粘贴到 prompt 中。

综合内容涵盖：
- 问题摘要与关键词（来自阶段1）
- 调用链、缺陷落点、触发条件、后果（来自阶段2a）
- 业务因果 B1–B5、兄弟对比、不触发场景（来自阶段2b）
- 关键机制动机（来自阶段2b，若有）
- 未能确认的主张（来自阶段2a）

### 阶段4：撰写三节初稿

委派 sub-agent（扮演**报告撰写员**角色），输入为阶段3综合分析摘要 + `issue_brief` + 全局规则。

**工作内容：**
- 按叙事优先 R16 写 `## 1. 问题描述`
- 按条件严谨性 R17 写 `## 2. 触发条件`
- 按 R19 写 `## 3. 结论`（仅一行 `REVIEW_RESULT=issue_true` 或 `REVIEW_RESULT=issue_false`）
- **R18 机制动机**：在 `问题描述` 中加 `### 关键机制为何如此设计` 子节（2–4 条，每条含 W1+W2+W3）
- **R20 场景证据**：`inference`/未验证的场景移到 `### 未能从代码确认的前提` 子节，不得计入正向清单
- 禁止 markdown 表格；专名/缩写首现须在同段用一句话解释

**三节必含要素：**

`## 1. 问题描述` 子节顺序：
1. `### 业务上发生了什么`（2–4 段；禁止以文件路径或配置键开篇）
2. `### 关键机制为何如此设计`（2–4 条；每条含 W1/W2+W3；禁止 code dump）
3. `### 前因后果链`（C0/B1 → C3/B4 → C4/B2；业务含义 + 括注 refs；禁止重复上一节全文）
4. `### 为何此处有问题、兄弟路径没有`
5. `### 代码佐证`（可选）

`## 2. 触发条件` 子节顺序：
1. `### 触发条件（正向：须同时满足）`（仅 confirmed 场景；配置项后可括注 W2 业务目的）
2. `### 故障表现`（**必填**；当正向条件同时满足时用户/评估可见坏结果；禁止重复正向条件清单）
3. `### 未能从代码确认的前提（不应计入触发清单）`（若有 inference/unverified 则必填）
4. `### 不触发 / 表现为正常的情形`（**必填**；反向）
5. `### 从输入到落点的过程`

`## 3. 结论`：**整节仅一行**，选定依据：
- `issue_true`：≥1 条 `confirmed` 核心落点，且前两节因果成立
- `issue_false`：无法 confirmed 用户前提，或典型条件下反向说明问题不会出现

**输出**：三节 Markdown 文本，在对话中返回（不写文件）。

### 阶段5：整稿深化（最多3轮）

```
rollback_used ← false
round ← 1

while round ≤ MAX_REVIEW_ROUNDS:
  委派报告评审 sub-agent（见下方"评审工作内容"）
  if resolution in [complete, partial]: break
  if resolution == needs_enrichment:
    委派报告补充 sub-agent（见下方"补充工作内容"）

  if round == 1 and not rollback_used:
    若评审缺失清单中 call_chain 维度 blocking 条数 ≥ 2:
      重委派代码追踪 sub-agent（附 suggested_addition 列表）
      重执行阶段3合并
      重委派撰写 sub-agent（draft_all）
      rollback_used ← true
      round ← 1
      continue

  round ← round + 1

if round == MAX_REVIEW_ROUNDS 且仍有 blocking/major 未补全:
  保留最终评审报告附入终稿附录C
```

#### 评审工作内容（报告评审员角色）

委派 sub-agent，输入为三节报告 Markdown + 综合分析摘要 + 全局规则。

**扫描维度（通读三节后统一评审，非逐节独立）：**

叙事优先 R16（`问题描述` 必查）：
- blocking：开篇或主段落是「根本原因：某文件/配置键」+ path:line 列表
- blocking：连续 ≥3 条仅含文件:行号/函数名、无业务含义
- blocking：缺少 `### 业务上发生了什么` 或等价业务开篇
- blocking：遮住 path:line 后新手无法复述因果
- major：代码佐证段落长于业务叙事段落

条件严谨性 R17（`触发条件` 必查）：
- blocking：单一配置 = 充分条件（「X=false 即报错」）
- blocking：缺少 `### 故障表现` 子节
- blocking：`### 故障表现` 重复粘贴正向触发条件清单（同文 bullet）
- blocking：缺 `### 不触发 / 表现为正常的情形` 反向子节
- major：正向触发缺运行时状态要素
- major：故障表现仅有代码内部状态、无用户可观察描述

机制动机 R18（`问题描述` 必扫；`触发条件` 按条件扫）：
- major：只写手段、同义反复（「用于保持长连接等待新请求」）而无 W2
- major：谈 timeout/连接策略但未交代组件架构角色（缺 W1）
- major：已写动机但未接到用户/运维可见症状（缺 W3）
- major：动机与后文后果/触发表述矛盾（cross_section）

对每个关键机制（超时数值、keep-alive/长连接、sidecar/proxy、相关配置项）逐条写入机制动机审核。

结论格式 R19（`结论` 必查）：
- blocking：非 exactly 一行 `REVIEW_RESULT=issue_true|false`
- blocking：除上述一行外有任何其他文字、空行或说明
- blocking：取值非上述二者
- blocking：选 `issue_true` 但前两节无 confirmed 核心落点
- blocking：选 `issue_false` 但前两节已 confirmed 完整缺陷路径

场景证据 R20（§1–§2 全文）：
- major：hedge + 无 refs（「在某些情况下可能」「例如 … 时」）
- major：正向清单含 disguised inference（有「可能/例如」未标 `(inference)`）
- major：`confirmed` 但 refs 仅 optional 定义，未证明 nil 实例可达
- major：分析产物 unverified 有该项，正文仍列正向条件

**resolution**：`needs_enrichment` | `complete` | `partial`

- **complete 前提**：三节满足 R16/R17/R19；无 blocking
- 仅有动机/场景类 major → `needs_enrichment`
- 第3轮结束仍有动机或场景 major → `partial`

禁止：因缺 W2 单独判 blocking；要求将 inference 升格为 confirmed；suggested_addition 写「写长一点」。

**输出格式（Markdown，在对话中返回）：**

```
## 整稿评审（第N轮）

**评审结论**：needs_enrichment / complete / partial

**缺失清单**：
- **[目标节] [blocking/major]**：... 建议补充：...

**机制动机审核**：
- 机制：... 已有层：[W1/W2/W3] 缺失层：[...] 严重程度：major

**场景证据审核**：
- 主张：... 是否有 refs：yes/no 严重程度：major
```

#### 补充工作内容（报告补充员角色）

委派 sub-agent，输入为当轮缺失清单 Markdown + 三节报告 Markdown + 全局规则。

**工作内容：**
- 按每条缺失项的目标节更新对应节（含 `结论`）
- 须逐条回应缺失清单；无法补充时说明「综合分析中暂无依据」
- 禁止 contradict confirmed 主张；新增主张须标 (confirmed)/(doc_declared)/(inference)
- 禁止 markdown 表格

**输出**：更新后的完整三节 Markdown 文本（非增量，完整三节）。

### 阶段6：组装 stdout 终稿

主编排者组装三节，按以下模板一次输出（禁止 `| ... |` 表格）：

```
# 问题分析报告

> 分析目标：<仓库名>
> 问题摘要：<issue_brief>

## 1. 问题描述

（须含：业务上发生了什么 → 关键机制为何如此设计（W1/W2/W3）→ 前因后果链 → 兄弟路径对比；代码佐证置后。）

## 2. 触发条件

（须含：正向须同时满足 → 故障表现 → 未能从代码确认的前提（若有）→ 不触发/正常情形（反向）→ 从输入到落点的过程。）

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

组装后自检：若 stdout 含 `| ... |` 表格行，改写为 bullet 列表。
````

- [ ] **Step 2: 验证覆盖度**

检查以下要点是否均在新 SKILL.md 中有对应内容：

```
原 SKILL.md 要求                → 新 SKILL.md 位置
-------------------------------------------------
全局红线 15 条                  → ## 全局规则（分析规则 + 报告规则）
ISSUE_TMP 设置                  → 已移除（无文件系统）
证据模型 EvidenceClaim          → 全局规则 > 分析规则 > 证据优先
section id（三节固定名）        → 阶段4 三节必含要素
MAX_REVIEW_ROUNDS = 3          → 工作流开头
阶段0 自检                      → 阶段0：自检
阶段1 issue-scout               → 阶段1：问题信息搜集
阶段2 code-tracer               → 阶段2：2a 代码追踪
阶段2 business-context-analyst  → 阶段2：2b 业务上下文分析
阶段3 jq 合并                   → 阶段3：综合分析（主编排者在上下文中合并）
阶段4 issue-writer draft_all    → 阶段4：撰写三节初稿
阶段5 issue-challenger          → 阶段5：评审工作内容
阶段5 issue-writer supplement   → 阶段5：补充工作内容
阶段5 rollback 逻辑             → 阶段5 伪代码
阶段6 组装终稿                  → 阶段6：组装 stdout 终稿
R15–R20 质量规则                → 全局规则 + 各阶段工作内容
输出模板                        → 阶段6 模板
```

若有缺失，补充到对应位置。

- [ ] **Step 3: 提交**

```bash
cd plugins/investigate-issue
git add skills/investigate/SKILL.md
git commit -s -S -m "refactor(investigate-issue): inline all agents into single SKILL.md"
```

---

### Task 2: 删除 agent 文件和验证脚本

**Files:**
- Delete: `plugins/investigate-issue/agents/issue-scout.md`
- Delete: `plugins/investigate-issue/agents/code-tracer.md`
- Delete: `plugins/investigate-issue/agents/business-context-analyst.md`
- Delete: `plugins/investigate-issue/agents/issue-writer.md`
- Delete: `plugins/investigate-issue/agents/issue-challenger.md`
- Delete: `plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh`

- [ ] **Step 1: git rm 所有 agent 文件和脚本**

```bash
cd /Users/weizhoulan/Documents/git/blueskills
git rm plugins/investigate-issue/agents/issue-scout.md \
       plugins/investigate-issue/agents/code-tracer.md \
       plugins/investigate-issue/agents/business-context-analyst.md \
       plugins/investigate-issue/agents/issue-writer.md \
       plugins/investigate-issue/agents/issue-challenger.md \
       plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh
```

预期输出：
```
rm 'plugins/investigate-issue/agents/business-context-analyst.md'
rm 'plugins/investigate-issue/agents/code-tracer.md'
rm 'plugins/investigate-issue/agents/issue-challenger.md'
rm 'plugins/investigate-issue/agents/issue-scout.md'
rm 'plugins/investigate-issue/agents/issue-writer.md'
rm 'plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh'
```

- [ ] **Step 2: 验证删除后目录结构**

```bash
find plugins/investigate-issue -type f | sort
```

预期输出（仅剩两个文件）：
```
plugins/investigate-issue/.claude-plugin/plugin.json
plugins/investigate-issue/skills/investigate/SKILL.md
```

- [ ] **Step 3: 提交**

```bash
git commit -s -S -m "chore(investigate-issue): remove agent files and verify script"
```

---

### Task 3: 更新 plugin.json

**Files:**
- Modify: `plugins/investigate-issue/.claude-plugin/plugin.json`

- [ ] **Step 1: 用以下内容替换 plugin.json**

```json
{
  "name": "investigate-issue",
  "displayName": "Investigate Issue",
  "version": "0.4.0",
  "description": "针对软件项目单个故障做深度分析，生成完整报告（单 SKILL.md，自然语言流转，无 agent 文件）",
  "keywords": ["issue-analysis", "code-tracing", "debugging"],
  "license": "MIT"
}
```

- [ ] **Step 2: 提交**

```bash
git add plugins/investigate-issue/.claude-plugin/plugin.json
git commit -s -S -m "chore(investigate-issue): bump version to 0.4.0, update description"
```

---

## 完成标准（与统一 spec Phase 1 一致）

- [ ] `plugins/investigate-issue/` 下只有 `.claude-plugin/plugin.json` 和 `skills/investigate/SKILL.md`
- [ ] SKILL.md 包含全部 7 个阶段（阶段0–6）
- [ ] SKILL.md 不含任何 JSON schema（`{}` 键值对格式的数据定义）
- [ ] SKILL.md 不含任何 bash 脚本（`$(mktemp -d)`、`jq` 等）
- [ ] SKILL.md 不含 `ISSUE_TMP`、`scout.json`、`issue-analysis.json` 等文件 handoff
- [ ] plugin.json version = "0.4.0"
- [ ] **人工试跑**：在真实仓库用一条故障描述调用 skill，stdout 含 `# 问题分析报告` 与单行 `REVIEW_RESULT=issue_true|false`

## Spec 覆盖自检（计划撰写时已核对）

| Spec 要求 | 计划任务 |
|-----------|----------|
| 单 SKILL + Markdown handoff | Task 1 |
| 删除 agents + verify 脚本 | Task 2 |
| plugin.json 0.4.0 | Task 3 |
| 保留 R15–R20、rollback、三节 | Task 1 全文 + Step 2 对照表 |
| 无 ISSUE_TMP/jq | Task 1 删除项 + 完成标准 |
