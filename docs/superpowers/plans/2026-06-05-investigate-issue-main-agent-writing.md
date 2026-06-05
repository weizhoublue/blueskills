# Investigate-Issue 主线程撰写初稿 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `investigate-issue` 原阶段 3（综合）+ 阶段 4（撰写初稿）合并为阶段 3 由主编排完成；阶段 5 评审员与补充员仍委派；版本 bump 并更新安装文档。

**Architecture:** 仅改 `SKILL.md` 工作流与分工约束：删除「报告撰写员」委派，把原阶段 4 的三节模板与 R16–R20 写作要求并入「阶段3」；rollback 改为「重跑 2a → 主编排重做阶段 3」。阶段 5 评审/补充 prompt 去掉对已删除撰写员的引用。无 jq/脚本/新文件。

**Tech Stack:** Markdown skill 定义、`plugin.json`、人工试跑验收。

**设计依据:** `docs/superpowers/specs/2026-06-05-investigate-issue-main-agent-writing-design.md`

---

## 文件映射

| 文件 | 职责 |
|------|------|
| `plugins/investigate-issue/skills/investigate/SKILL.md` | 工作流、分工、阶段 3 合并、阶段 5 rollback/prompt |
| `plugins/investigate-issue/.claude-plugin/plugin.json` | 版本与 description |
| `docs/installation.md` | investigate-issue 流程说明（步骤 3–5） |

---

### Task 0: 实施前阅读

**Files:**
- Read: `docs/superpowers/specs/2026-06-05-investigate-issue-main-agent-writing-design.md`
- Read: `plugins/investigate-issue/skills/investigate/SKILL.md`（全文）
- Read: `plugins/audit/skills/review/SKILL.md`（阶段 4 报告拼装，对齐主线程写作模式）

- [ ] **Step 1:** 通读设计 spec，确认采用方案 A（仅合并 3+4）
- [ ] **Step 2:** 在 `SKILL.md` 中标记所有需改处：`阶段3：综合分析`、`阶段4：撰写`、`报告撰写`、`重委派撰写`、`draft_all`

---

### Task 1: 更新开篇与全局分工约束

**Files:**
- Modify: `plugins/investigate-issue/skills/investigate/SKILL.md:6-7`
- Modify: `plugins/investigate-issue/skills/investigate/SKILL.md:34-37`

- [ ] **Step 1: 改主编排角色句**

将第 6 行附近：

```markdown
你是本次故障分析的**主编排者**。接收用户描述的问题，顺序委派各阶段 sub-agent，最终组装并输出完整的问题分析报告。
```

替换为：

```markdown
你是本次故障分析的**主编排者**。接收用户描述的问题，顺序委派搜集与分析 sub-agent；在阶段 3 由你综合上游 Markdown 并撰写三节初稿；阶段 5 委派评审与补充 sub-agent；最终组装并输出完整的问题分析报告。
```

- [ ] **Step 2: 改分工约束**

将 `### 分析规则` 下「分工约束」bullets 替换为：

```markdown
- **分工约束**：
  - 代码追踪 sub-agent 禁止修改分析源文件；
  - **主编排**撰写初稿时不得与 `confirmed` 主张矛盾；
  - 报告补充 sub-agent 不得与 `confirmed` 主张矛盾；
  - 报告评审 sub-agent 输出缺失清单后，报告补充 sub-agent 必须逐条补充（无法补充时说明「综合分析中暂无依据」）。
```

- [ ] **Step 3: Commit**

```bash
git add plugins/investigate-issue/skills/investigate/SKILL.md
git commit -m "refactor(investigate-issue): main orchestrator writes draft; update role constraints"
```

---

### Task 2: 合并阶段 3 与 4（删除阶段 4 小节）

**Files:**
- Modify: `plugins/investigate-issue/skills/investigate/SKILL.md`（`### 阶段3` 至 `### 阶段5` 之间）

- [ ] **Step 1: 删除原 `### 阶段3：综合分析` 与 `### 阶段4：撰写三节初稿` 两个小节**

- [ ] **Step 2: 插入合并后的阶段 3**

在 `### 阶段2b` 输出模板之后、`### 阶段5` 之前插入：

```markdown
### 阶段3：综合分析与撰写三节初稿（主编排，不委派）

主编排在上下文中完成原阶段 3+4：**不**委派 sub-agent。

**输入：** `issue_brief`、阶段 1 Markdown 全文、阶段 2a/2b Markdown 全文、全局规则。

**步骤 1 — 内部分析综合**（编排上下文保留，供阶段 5 评审/补充粘贴；可不单独对外输出标题）：

- 问题摘要与关键词（阶段 1）
- 调用链、缺陷落点、触发条件、后果（阶段 2a）
- 业务因果 B1–B5、兄弟对比、不触发场景（阶段 2b）
- 关键机制动机（阶段 2b，若有）
- 未能确认的主张（阶段 2a）

**步骤 2 — 撰写三节初稿**（在编排上下文中保留完整三节，供阶段 5 使用）：

- 按叙事优先 R16 写 `## 1. 问题描述`
- 按条件严谨性 R17 写 `## 2. 触发条件`
- 按 R19 写 `## 3. 结论`（仅一行 `REVIEW_RESULT=issue_true` 或 `REVIEW_RESULT=issue_false`）
- **R18**：`问题描述` 中含 `### 关键机制为何如此设计`（2–4 条，每条 W1+W2+W3）
- **R20**：`inference`/未验证场景放入 `### 未能从代码确认的前提`，不得计入正向清单
- 禁止 markdown 表格；专名/缩写首现须同段解释

**三节必含要素：**

`## 1. 问题描述` 子节顺序：
1. `### 业务上发生了什么`（2–4 段；禁止以文件路径或配置键开篇）
2. `### 关键机制为何如此设计`（2–4 条；每条含 W1/W2+W3）
3. `### 前因后果链`（C0/B1 → C3/B4 → C4/B2；业务含义 + 括注 refs）
4. `### 为何此处有问题、兄弟路径没有`
5. `### 代码佐证`（可选）

`## 2. 触发条件` 子节顺序：
1. `### 触发条件（正向：须同时满足）`（仅 confirmed）
2. `### 故障表现`（**必填**）
3. `### 未能从代码确认的前提（不应计入触发清单）`（若有 inference 则必填）
4. `### 不触发 / 表现为正常的情形`（**必填**）
5. `### 从输入到落点的过程`

`## 3. 结论`：**整节仅一行**；`issue_true` / `issue_false` 选定依据与原阶段 4 一致。

**输出：** 完整三节 Markdown 保留在编排上下文（不写磁盘文件）。
```

- [ ] **Step 3: 全文搜索确认无残留 `### 阶段4` 或「委派阶段4」**

Run: `rg -n "阶段4|报告撰写员|撰写 sub-agent" plugins/investigate-issue/skills/investigate/SKILL.md`

Expected: 无匹配（阶段 5 内 rollback 修复后亦不应出现「撰写 sub-agent」）

- [ ] **Step 4: Commit**

```bash
git add plugins/investigate-issue/skills/investigate/SKILL.md
git commit -m "refactor(investigate-issue): merge synthesis and draft into stage 3"
```

---

### Task 3: 更新阶段 5 rollback 与评审/补充 prompt

**Files:**
- Modify: `plugins/investigate-issue/skills/investigate/SKILL.md`（阶段 5 伪代码与评审/补充小节）

- [ ] **Step 1: 替换 rollback 伪代码块**

将阶段 5 内：

```text
      重执行阶段3合并
      重委派撰写 sub-agent（draft_all）
```

替换为：

```text
      主编排重做阶段 3（综合 + 三节初稿）
```

- [ ] **Step 2: 更新评审员输入说明**

将「委派 sub-agent，输入为三节报告 Markdown + 综合分析摘要 + 全局规则」改为：

```markdown
委派 sub-agent，输入为：当前三节报告 Markdown 全文 + `issue_brief` + 全局规则 +（建议）阶段 1/2a/2b 关键块或阶段 3 分析要点粘贴。
```

删除任何「仅供阶段 4 撰写员」类表述。

- [ ] **Step 3: 更新补充员输入说明**

将补充员输入改为：

```markdown
委派 sub-agent，输入为：当轮缺失清单 Markdown + 当前完整三节 Markdown + 全局规则 +（可选）阶段 1/2a/2b 或阶段 3 分析要点。
```

确认补充工作内容小节**保留**，且仍写「报告补充员角色」。

- [ ] **Step 4: Commit**

```bash
git add plugins/investigate-issue/skills/investigate/SKILL.md
git commit -m "refactor(investigate-issue): stage 5 prompts and rollback for merged stage 3"
```

---

### Task 4: 更新 plugin.json

**Files:**
- Modify: `plugins/investigate-issue/.claude-plugin/plugin.json`

- [ ] **Step 1:  bump 版本**

当前若为 `0.5.0`，改为 `0.5.1`；若为 `0.4.0`，改为 `0.4.1`（与 spec 一致）。`description` 设为：

```json
"description": "针对软件项目单个故障做深度分析（单 SKILL.md；主线程撰写初稿；评审/补充仍委派）"
```

完整示例（版本按仓库当前值 +1 patch）：

```json
{
  "name": "investigate-issue",
  "displayName": "Investigate Issue",
  "version": "0.5.1",
  "description": "针对软件项目单个故障做深度分析（单 SKILL.md；主线程撰写初稿；评审/补充仍委派）",
  "keywords": ["issue-analysis", "code-tracing", "debugging"],
  "license": "MIT"
}
```

- [ ] **Step 2: Commit**

```bash
git add plugins/investigate-issue/.claude-plugin/plugin.json
git commit -m "chore(investigate-issue): bump to 0.5.1, update plugin description"
```

---

### Task 5: 更新 docs/installation.md

**Files:**
- Modify: `docs/installation.md`（`## investigate-issue` 小节）

- [ ] **Step 1: 更新插件形态一句**

将 `v0.4.0+` 改为 `v0.5.1+`（或实际 bump 版本），并补充主线程初稿：

```markdown
**插件形态（v0.5.1+）**：仅一个 skill 文件 `investigate`（`SKILL.md`）；搜集与分析委派 sub-agent；**初稿由主编排在阶段 3 撰写**；深化阶段仍委派评审与补充；阶段间 Markdown 在对话中传递（无 `ISSUE_TMP`、无 `jq`、无独立 `agents/*.md`）。
```

- [ ] **Step 2: 合并流程步骤 3–4，修正步骤 5**

将原流程项 3–5 替换为：

```markdown
3. **综合并撰写初稿（主编排，不委派）**：合并搜集与并行分析结果，写出 `## 1. 问题描述`、`## 2. 触发条件`、`## 3. 结论`（**仅一行** `REVIEW_RESULT=issue_true|false`）。
4. **整稿深化（≤3 轮）**：质审 sub-agent（R16–R20）；`needs_enrichment` 时由**补充** sub-agent 按缺失清单输出完整三节；call_chain 类 blocking 过多时可 **回滚重追踪 1 次** 后主编排重做步骤 3。
```

- [ ] **Step 3: Commit**

```bash
git add docs/installation.md
git commit -m "docs: investigate-issue v0.5.1 workflow (main-thread draft)"
```

---

### Task 6: 验收（人工试跑清单）

**Files:**
- Verify: `plugins/investigate-issue/skills/investigate/SKILL.md`

- [ ] **Step 1: 静态检查**

```bash
rg -n "阶段4|报告撰写员|ISSUE_TMP|jq |scout\.json" plugins/investigate-issue/
```

Expected: 无匹配（`investigate-issue` 目录内）

```bash
rg -n "阶段3：综合" plugins/investigate-issue/skills/investigate/SKILL.md
```

Expected: 命中合并后的阶段 3 标题

```bash
rg -n "报告补充员|补充工作内容" plugins/investigate-issue/skills/investigate/SKILL.md
```

Expected: 阶段 5 仍保留补充员

- [ ] **Step 2: 人工试跑（可选但推荐）**

在任一真实仓库根目录执行 skill，输入含组件/现象线索的 `issue_brief`。

检查：
- stdout 含 `# 问题分析报告` 与 `REVIEW_RESULT=issue_true|false`
- §3 结论下仅一行 `REVIEW_RESULT=…`
- 终稿无 `| ... |` 表格行

- [ ] **Step 3: 更新设计 spec 完成标准（可选）**

在 `docs/superpowers/specs/2026-06-05-investigate-issue-main-agent-writing-design.md` 将「完成标准」checkbox 勾为 `[x]`（若实施方完成验收）。

- [ ] **Step 4: 最终 commit（若有 spec checkbox 变更）**

```bash
git add docs/superpowers/specs/2026-06-05-investigate-issue-main-agent-writing-design.md
git commit -m "docs: mark investigate-issue main-agent writing spec complete"
```

---

## Spec 覆盖自检

| Spec 要求 | 任务 |
|-----------|------|
| 阶段 3 主线程综合+初稿 | Task 2 |
| 删除撰写员 | Task 2, Task 3 搜索 |
| 保留评审+补充员 | Task 3（保留补充小节） |
| rollback 重做阶段 3 | Task 3 |
| 分工约束更新 | Task 1 |
| plugin.json bump | Task 4 |
| installation.md | Task 5 |
| 人工试跑 | Task 6 |

## 完成标准（计划级）

- [ ] `SKILL.md` 无阶段 4 / 报告撰写员委派
- [ ] 阶段 3 标题含「综合分析与撰写三节初稿」
- [ ] 阶段 5 仍含评审员与补充员；rollback 无「撰写 sub-agent」
- [ ] `plugin.json` 版本与 description 已更新
- [ ] `docs/installation.md` 流程与 v0.5.1+ 一致
