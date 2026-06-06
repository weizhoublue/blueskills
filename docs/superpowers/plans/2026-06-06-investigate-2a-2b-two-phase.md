# Investigate 2a/2b 两阶段扫描 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `plugins/investigate-issue/skills/investigate/SKILL.md` 阶段 2 的 2a 改为「追踪清单 → C0–C4 骨架 → 逐格核实」；2b 改为「前提核实 → 功能层完整分析」；微调阶段 3/4 以衔接 phantom 前提与 gap。

**Architecture:** 仅改 `SKILL.md` 与 `plugin.json`。阶段 2 仍两次并行 Task；变化在 2a/2b 内部流程与中间输出格式（允许表格，终稿 R15 仍禁表）。阶段 1 Read ≤40 保留；2a/2b 不删 Read 上限。

**Tech Stack:** Markdown skill 定义、`plugin.json`、`rg` 结构验收。

**设计依据:** `docs/superpowers/specs/2026-06-06-investigate-2a-2b-two-phase-design.md`

---

## 文件映射

| 文件 | 职责 |
|------|------|
| `plugins/investigate-issue/skills/investigate/SKILL.md` | 2a/2b 重写、阶段 3/4 微调 |
| `plugins/investigate-issue/.claude-plugin/plugin.json` | version bump、description |
| `docs/superpowers/specs/2026-06-06-investigate-2a-2b-two-phase-design.md` | 完成后「状态」→「已实施」 |

---

### Task 0: 实施前阅读

**Files:**
- Read: `docs/superpowers/specs/2026-06-06-investigate-2a-2b-two-phase-design.md`
- Read: `plugins/investigate-issue/skills/investigate/SKILL.md`（全文）

- [ ] **Step 1:** 确认 v1 不创建 `plugins/investigate-issue/agents/*.md`
- [ ] **Step 2:** 标记替换区间：行 110–158（2a）、160–201（2b）、209–215（阶段3 步骤1）、242–244（R19）、260–266（rollback）、场景证据审核附近（阶段4）

---

### Task 1: 重写 2a — 代码追踪

**Files:**
- Modify: `plugins/investigate-issue/skills/investigate/SKILL.md:110-158`

- [ ] **Step 1:** 将 `#### 2a 代码追踪` 至 `#### 2b` 之前整段替换为：

```markdown
#### 2a 代码追踪

sub-agent 扮演**代码追踪员**角色。

**聚焦：** 函数级调用链 C0–C4（每步 `confirmed` + `path:line` + 业务含义）。

**必扫流程（须按序执行）：**

##### 阶段 A1 — 入口与一层调用清单（只建表，不做缺陷判断）

1. 从阶段 1「候选模块」「入口线索」确定 C0 **候选入口**（config/env/api/cli）。
2. 对每个入口在同仓库内找**直接下一跳**（`Grep` + 必要时 `Read` 调用点 / 入口函数体）。
3. 合并去重，在输出中必填 **追踪清单**：

```markdown
### 追踪清单

| ID | 方向 | 符号 | 文件 | 关联入口 | 发现方式 |
|----|------|------|------|----------|----------|
| T1 | 入口 | handleX | pkg/a.go | C0候选 | read/grep |
| T2 | 下一跳 | dispatchY | pkg/b.go | T1 | read body |
```

- 无下一跳：行内注明 `leaf / inline-only`。
- **阶段 A1 禁止**：缺陷判断、无依据的 C0–C4 叙事、无清单项锚定的深搜。

##### 阶段 A2 — C0–C4 骨架（仅引用清单）

仅用追踪清单行拼出 C0–C4 骨架；每行须带 `清单ID`；清单无对应 hop → 标 `gap`，**禁止**编造符号：

```markdown
### 调用链骨架（待核实）

| 层 | 清单ID | 候选符号 | 业务含义（待核实） |
|----|--------|----------|-------------------|
| C0 | T1 | handleX | ... |
| C1 | T2 | dispatchY | ... |
| gap | — | — | 清单无下一跳；阶段 B 扩层或标未能确认 |
```

##### 阶段 B — 逐格落地核实

- 对骨架每一行（含 `gap`）Read 填 `path:line`、业务含义、证据层级 `(confirmed)`。
- **C2** 允许 guard/分支等非 callee 行，但须 `path:line`。
- **按需扩展**：核实中发现具体疑点时，可向下一层扩一层；须在输出记录：**扩展项 | 疑点 | 扩到哪 | 结论**。
- 骨架 `gap` 未解决 → 该 hop **不得**标 `(confirmed)`，写入 **未能确认的主张**。
- 填写缺陷落点、触发条件（R17）、后果（代码层 + 用户影响）、场景证据（R20）。

**不做：** 业务前提是否属实（2b）；修改源文件。

**输出格式（Markdown，在对话中返回，不写文件）：**

```
## 代码追踪结果

### 追踪清单
（阶段 A1 表格）

### 调用链骨架（待核实）
（阶段 A2 表格）

**入口点**：
- 类型：config/env/api/cli ref：path:line 描述：...

**函数级调用链**：
- **C0** `path:line` 函数：`func_name` 清单ID：T1 业务含义：...
- **C1** `path:line` 函数：`func_name` 清单ID：T2 业务含义：...
- **C2** `path:line` 函数/分支：... 业务含义：...
- **C3** `path:line` 函数：`func_name` 业务含义：（缺陷落点）
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

## 扫描覆盖说明
- [ ] 追踪清单已覆盖阶段 1 全部候选入口
- [ ] C0–C4 骨架每行有清单ID或 gap 标记
- [ ] 骨架每一行已核实或记入未能确认的主张
- [ ] 扩展项（若有）已记录
```

- [ ] **Step 2: Commit**

```bash
git add plugins/investigate-issue/skills/investigate/SKILL.md
git commit -m "refactor(investigate): rewrite 2a as inventory-skeleton-verify workflow"
```

---

### Task 2: 重写 2b — 业务上下文分析

**Files:**
- Modify: `plugins/investigate-issue/skills/investigate/SKILL.md`（`#### 2b` 段至 `### 阶段3` 之前）

- [ ] **Step 1:** 将 `#### 2b 业务上下文分析` 整段替换为：

```markdown
#### 2b 业务上下文分析

sub-agent 扮演**业务上下文分析员**角色。

**聚焦：** ① 用户主张是否属实；② 功能层面完整解读问题。

**必扫流程（须按序执行）：**

##### 阶段 A — 前提核实（只建表，不写 B1–B5 因果结论）

从 `issue_brief` + 阶段 1 输出拆解每条**可核对主张**（功能、接口、配置行为、用户可见现象等），在代码/文档中核实：

```markdown
### 前提核实

| ID | 用户主张 | 核实结果 | 证据 | 说明 |
|----|----------|----------|------|------|
| P1 | 「支持功能 X」 | exists | path:line | 有完整实现路径 |
| P2 | 「Y 会报错」 | partial | path:line | 仅部分路径实现 |
| P3 | 「Z 接口可用」 | missing | 搜索：... | 无实现或仅 stub |
| P4 | 「文档称支持 W」 | doc_only | docs/... | 代码无对应 |
```

**核实结果枚举：** `exists`（完整或主路径实现）| `partial`（入口/flag/API 有但主路径未实现、stub 或默认关）| `missing`（代码无对应能力）| `doc_only`（仅文档/注释，代码无实现）。

**阶段 A 禁止**：写 B1–B5 因果结论；将用户原话标为 `(confirmed)`。

##### 阶段 B — 功能层完整分析

在前提表基础上输出：

**1. 业务因果 B1–B5**（须引用 P* ID；遵守全局证据层级）：

- **B1** 情境：谁、部署/配置、**代码实际能力边界**（用户声称与代码不符须点明）
- **B2** 可观察坏结果：核心前提 `missing`/`doc_only` → 不得 `(confirmed)`；区分「实际」vs「若前提成立则…」`(inference)`
- **B3** 兄弟/默认路径为何不同：必填；无 peer 须说明
- **B4** 缺陷在业务流哪一段介入：须对齐 2a C3 或说明无法对齐原因
- **B5** 功能/性能/可靠性影响：区分实际影响 vs 假设前提下的影响

**2. 必填 `### 功能层面完整解读`**：2–4 段叙事——业务上应做什么、代码实际怎么做、二者差异（R16，禁止 path 清单代替叙事）。

**3. 保留项**：兄弟分支对比（必填）、不触发场景、关键机制动机 W1–W3（可选）。

**规则摘要：**

- `issue_brief` 每条**核心主张**须在阶段 A 有 P* 行。
- 核心能力 `missing` / `doc_only`：**禁止**在 B2–B5 用 `(confirmed)` 描述该能力已上线。
- `partial`：必须写清「已实现哪段 / 缺哪段」。
- `inference` 须有 uncertainty_note（含「未能从代码确认」）。
- B4 不得描述 2a 未 `(confirmed)` 的链路 hop。

**不做：** 函数级调用链深挖（2a）；修改源文件。

**输出格式（Markdown，在对话中返回，不写文件）：**

```
## 业务上下文分析结果

### 前提核实
（阶段 A 表格）

### 功能层面完整解读
（2–4 段叙事）

**业务因果**：
- B1 情境：...（refs: P1, ...）
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

## 扫描覆盖说明
- [ ] 前提核实表已覆盖 issue_brief 核心主张
- [ ] 功能层面完整解读已填写
- [ ] B1–B5 已执行或注明 skip（及原因）
- [ ] 无 phantom 功能被标为 confirmed
```

- [ ] **Step 2: Commit**

```bash
git add plugins/investigate-issue/skills/investigate/SKILL.md
git commit -m "refactor(investigate): add premise gate and functional narrative to 2b"
```

---

### Task 3: 微调阶段 3 主编排综合

**Files:**
- Modify: `plugins/investigate-issue/skills/investigate/SKILL.md:209-215` 及 `242-244`

- [ ] **Step 1:** 在「步骤 1 — 内部分析综合」列表**最前**插入：

```markdown
- **先读** 2b `### 前提核实` 与 2a 骨架 `gap` / **未能确认的主张**；核心前提 `missing`/`doc_only` 不得升格为 confirmed 因果
```

- [ ] **Step 2:** 在步骤 1 列表中增补：

```markdown
- 前提核实 P* 表、功能层面完整解读（阶段 2b）
- 追踪清单与调用链骨架（阶段 2a）
```

- [ ] **Step 3:** 将 `issue_false` 选定依据 bullet 扩展为：

```markdown
- `issue_false`：无法 confirmed 用户前提（功能不存在/未实现/doc_only），或典型条件下反向说明问题不会出现
```

- [ ] **Step 4: Commit**

```bash
git add plugins/investigate-issue/skills/investigate/SKILL.md
git commit -m "refactor(investigate): stage-3 merge premise verification and gaps first"
```

---

### Task 4: 微调阶段 4 rollback 与评审

**Files:**
- Modify: `plugins/investigate-issue/skills/investigate/SKILL.md`（rollback 块与场景证据审核）

- [ ] **Step 1:** 在 rollback 条件块（`call_chain 维度 blocking`）后追加同级条件：

```markdown
    若评审缺失清单中 phantom 前提 / 业务上下文 维度 major 条数 ≥ 1 且 2b 前提核实含 missing/doc_only:
      重委派业务上下文分析 sub-agent（附 suggested_addition 列表）
      主编排重做阶段 3（综合 + 三节初稿）
      rollback_used ← true
      round ← 1
      continue
```

- [ ] **Step 2:** 在「场景证据 R20」审核 bullets 末尾追加：

```markdown
- major：正文将 2b 前提核实为 `missing`/`doc_only` 的能力写作 confirmed 业务链或正向触发条件
```

- [ ] **Step 3: Commit**

```bash
git add plugins/investigate-issue/skills/investigate/SKILL.md
git commit -m "refactor(investigate): stage-4 phantom premise review and 2b rollback"
```

---

### Task 5: 结构验收（rg）

**Files:**
- Test: `plugins/investigate-issue/skills/investigate/SKILL.md`

- [ ] **Step 1: 确认 2a 新结构**

```bash
rg -n '阶段 A1 — 入口与一层调用清单|调用链骨架（待核实）|扫描覆盖说明' plugins/investigate-issue/skills/investigate/SKILL.md
```

Expected: ≥3 匹配行

- [ ] **Step 2: 确认 2b 新结构**

```bash
rg -n '前提核实|功能层面完整解读|missing|doc_only|phantom' plugins/investigate-issue/skills/investigate/SKILL.md
```

Expected: ≥5 匹配行

- [ ] **Step 3: 确认阶段 3 先读前提**

```bash
rg -n '先读.*前提核实' plugins/investigate-issue/skills/investigate/SKILL.md
```

Expected: 1 匹配行

- [ ] **Step 4: 确认阶段 1 Read 预算仍保留**

```bash
rg -n 'Read 预算：≤40' plugins/investigate-issue/skills/investigate/SKILL.md
```

Expected: 1 匹配行

---

### Task 6: 更新 plugin.json

**Files:**
- Modify: `plugins/investigate-issue/.claude-plugin/plugin.json`

- [ ] **Step 1:** `version` `0.7.0` → `0.7.1`

- [ ] **Step 2:** `description` 改为：

```json
"description": "针对单个故障做深度分析；2a 追踪清单+C0-C4核实，2b 前提核实+功能层解读，主线程撰写初稿"
```

- [ ] **Step 3: Commit**

```bash
git add plugins/investigate-issue/.claude-plugin/plugin.json
git commit -m "chore(investigate-issue): bump plugin to 0.7.1 for 2a/2b two-phase"
```

---

### Task 7: 标记设计 spec 已实施

**Files:**
- Modify: `docs/superpowers/specs/2026-06-06-investigate-2a-2b-two-phase-design.md:4`

- [ ] **Step 1:** `**状态：** 待实施` → `**状态：** 已实施`

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-06-06-investigate-2a-2b-two-phase-design.md
git commit -m "docs: mark investigate 2a/2b two-phase design as implemented"
```

---

## Spec 覆盖自检

| Spec 要求 | 对应 Task |
|-----------|-----------|
| 2a A1/A2/B 流程 | Task 1 |
| 2b 前提核实 + 功能解读 | Task 2 |
| phantom 防护规则 | Task 2 |
| 阶段 3 先读前提/gap | Task 3 |
| 阶段 4 rollback/评审 | Task 4 |
| 阶段 1 Read 保留 | Task 5 step 4 |
| plugin.json | Task 6 |
| rg 验收 | Task 5 |
