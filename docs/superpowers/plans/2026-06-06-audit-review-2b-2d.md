# Audit Review 2b 重构 & 2d 残留 Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `plugins/audit/skills/review/SKILL.md` 的 2b 改为「一层上下游清单 → 逐项核实」两阶段流程；新增条件委派的 2d 同类残留 agent；删除全文 Read 预算；更新主编排合并与门禁。

**Architecture:** 仅改 `SKILL.md` 与 `plugin.json`。阶段 2 始终并行 2a/2b/2c；当阶段 1「变更性质」含 `bugfix` 时追加并行 2d。2b 负责一层调用关系 + 兄弟对比；2d 负责全仓 Grep 残留；2c 保留修复完整性并明确边界。通信仍为 Markdown 粘贴，无 JSON/脚本。

**Tech Stack:** Markdown skill 定义、`plugin.json`、`rg` 结构验收。

**设计依据:** `docs/superpowers/specs/2026-06-06-audit-review-2b-2d-design.md`

---

## 文件映射

| 文件 | 职责 |
|------|------|
| `plugins/audit/skills/review/SKILL.md` | 2b 重写、2d 新增、2c 边界、Read 预算删除、主编排/委派更新 |
| `plugins/audit/.claude-plugin/plugin.json` | version bump、`description` 一句 |
| `docs/superpowers/specs/2026-06-06-audit-review-2b-2d-design.md` | 完成后「状态」→「已实施」 |

---

### Task 0: 实施前阅读

**Files:**
- Read: `docs/superpowers/specs/2026-06-06-audit-review-2b-2d-design.md`
- Read: `plugins/audit/skills/review/SKILL.md`（全文）

- [ ] **Step 1:** 确认 v1 不创建 `plugins/audit/agents/*.md`
- [ ] **Step 2:** 标记替换区间：行 5–6、74–81、125–128、132–345、377–381

---

### Task 1: 更新开篇、总体流程、阶段 1 限制

**Files:**
- Modify: `plugins/audit/skills/review/SKILL.md:5-6`
- Modify: `plugins/audit/skills/review/SKILL.md:74-81`
- Modify: `plugins/audit/skills/review/SKILL.md:125-128`

- [ ] **Step 1: 改主编排角色句（第 5 行）**

将：

```markdown
你是本次审计的**主编排者**。接收用户输入，委派阶段 1；**并行**委派阶段 2 的 2a/2b/2c 三个 specialist agent，由你合并候选缺陷并做覆盖说明门禁；再委派阶段 3 质检；最后由你执行阶段 4 报告拼装并输出最终报告。禁止修改被审仓库代码；禁止运行测试。
```

替换为：

```markdown
你是本次审计的**主编排者**。接收用户输入，委派阶段 1；**并行**委派阶段 2 的 2a/2b/2c 三个 specialist agent（若阶段 1「变更性质」含 **bugfix**，同时并行委派 **2d**），由你合并候选缺陷并做覆盖说明门禁；再委派阶段 3 质检；最后由你执行阶段 4 报告拼装并输出最终报告。禁止修改被审仓库代码；禁止运行测试。
```

- [ ] **Step 2: 改总体流程图（第 76–81 行 code block）**

```text
1. 变更意图分析
2. 代码缺陷扫描（并行 2a / 2b / 2c [+ 条件 2d] → 主编排合并）
3. 缺陷质检
4. 报告拼装
```

- [ ] **Step 3: 改阶段 1 限制（第 127–128 行）**

将：

```markdown
本阶段不得输出缺陷，不得判断代码是否正确，不得裁剪主审的审计范围。
- 不得因「变更简单」而暗示 2b/2c 可跳过；是否 skip 由阶段 2 各 agent 在覆盖说明中论证。
```

替换为：

```markdown
本阶段不得输出缺陷，不得判断代码是否正确，不得裁剪主审的审计范围。
- 不得因「变更简单」而暗示 2b/2c/2d 可跳过；是否 skip 由阶段 2 各 agent 在覆盖说明中论证。
- 不得暗示非 bugfix 变更可由 2b 代做全仓同类残留扫描（残留属 2d，仅 bugfix 委派）。
```

- [ ] **Step 4: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "refactor(audit): describe conditional 2d in overview and stage-1 limits"
```

---

### Task 2: 更新阶段 2 目标、委派表、共享规则适用范围

**Files:**
- Modify: `plugins/audit/skills/review/SKILL.md:132-159`

- [ ] **Step 1: 替换阶段 2「目标」段（第 134–145 行）**

```markdown
## 目标

**并行**委派 specialist sub-agent：**始终** 2a / 2b / 2c；**当且仅当**阶段 1「变更性质」含 **bugfix** 时，**同时**委派 2d。

各 agent 输入均为：（1）diff 原文；（2）阶段 1「变更意图分析」Markdown 全文；（3）本节下方「共享规则」全文（缺陷成立条件、候选格式等）。

全部 agent 返回后，由**主编排**合并候选缺陷、执行覆盖说明门禁，将合并结果交给阶段 3。主编排在本节**不得**以证据不足删除候选（交给质检）。

每次委派 sub-agent 时，prompt **必须**包含：

- 本 agent 职责与 checklist（见 2a/2b/2c/2d）
- diff 原文 + 阶段 1 输出全文
- 下方「共享规则」全文
- 输出格式（含必填「扫描覆盖说明」）
```

- [ ] **Step 2: 替换「并行委派」段（第 147–155 行）**

```markdown
## 并行委派

使用 `Task` **同时**发起 sub-agent：

- **非 bugfix**（阶段 1 变更性质不含 `bugfix`）：单条消息内 **三次** Task（2a / 2b / 2c）。
- **bugfix**（阶段 1 变更性质含 `bugfix`）：单条消息内 **四次** Task（2a / 2b / 2c / 2d）。

| 子阶段 | 角色名（description） | 职责摘要 | 委派条件 |
|--------|----------------------|----------|----------|
| **2a** | 变更代码本身审查 | 语言缺陷、安全、边界条件 | 始终 |
| **2b** | 变更周边影响审查 | 一层上下游清单与核实、兄弟对比 | 始终 |
| **2c** | 目的与兼容性审查 | 修复完整性、升级兼容性 | 始终 |
| **2d** | 同类残留审查 | 全仓同模式 Grep 与核实 | 仅 bugfix |
```

- [ ] **Step 3: 改共享规则适用范围（第 157–159 行）**

将 `以下规则对 2a/2b/2c **均适用**。` 替换为：

```markdown
以下规则对 2a/2b/2c/2d **均适用**。
```

- [ ] **Step 4: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "refactor(audit): add conditional 2d dispatch and update stage-2 goal"
```

---

### Task 3: 删除 2a Read 预算，保留 Grep/Glob

**Files:**
- Modify: `plugins/audit/skills/review/SKILL.md:284`

- [ ] **Step 1:** 将第 284 行

```markdown
**Read 预算：** Read ≤35；Grep ≤12；Glob ≤8。
```

替换为：

```markdown
**工具预算：** Grep ≤12；Glob ≤8。
```

- [ ] **Step 2: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "refactor(audit): remove Read budget from 2a scanner"
```

---

### Task 4: 重写 2b — 变更周边影响审查

**Files:**
- Modify: `plugins/audit/skills/review/SKILL.md:288-305`

- [ ] **Step 1:** 将 `#### 2b — 变更周边影响审查` 至 `#### 2c` 之前整段替换为：

```markdown
#### 2b — 变更周边影响审查

sub-agent 扮演**变更周边影响审查员**。

**聚焦：** 以变更符号为锚的**一层**调用关系 + 兄弟/同类并行实现对比。

**必扫流程（须按序执行，并全部写入「扫描覆盖说明」）：**

##### 阶段 A — 锚点与一层扫描（只建清单，不做缺陷判断）

1. **提取锚点**：从 diff 列出所有变更的函数/方法（含新增、修改、删除体；纯类型/常量变更则锚点为所在作用域最近的可调用单元）。
2. **对每个锚点扫描一层**：
   - **上游（callers）**：在同仓库内找**直接调用**该锚点的函数/方法（`Grep` 符号引用 + 必要时 `Read` 调用点上下文）。
   - **下游（callees）**：`Read` 锚点**完整函数体**，列出其**直接调用**的函数/方法（不猜测间接调用链）。
3. **合并去重**：跨锚点汇总，在「扫描覆盖说明」中必填 **一层上下游清单**：

```markdown
### 一层上下游清单

| 方向 | 符号 | 文件 | 关联锚点 | 发现方式 |
|------|------|------|----------|----------|
| 上游 | callerFn | path/to/a.go | anchorFn | grep |
| 下游 | calleeFn | path/to/b.go | anchorFn | read body |
```

- 无直接 caller：行内注明 `无直接 caller（可能为入口/回调/仅测试引用）`。
- 无直接 callee：注明 `无直接 callee（叶子/内联逻辑）`。

**阶段 A 禁止**：输出缺陷结论、使用「可能有问题」等判断性表述、无清单项锚定地追第二层。

##### 阶段 B — 清单逐项核实

对清单**每一行**在覆盖说明中勾选 `- [x]` 核实：

| 方向 | 核实项 |
|------|--------|
| 上游 caller | 传入参数类型/个数/语义；前置状态；错误处理；并发/重入；变更后调用是否仍合法 |
| 下游 callee | 新参数/返回值/错误码；共享状态；下游对 nil/空/默认值假设是否仍成立 |

**按需扩展**（仅当核实中发现**具体疑点**，如参数透传未校验、新错误码未处理）：

- 可向该方向**再扩一层** caller 或 callee；
- 须在覆盖说明追加子表：**扩展项 | 因何疑点 | 扩到哪一层 | 结论**；
- **禁止**无清单项锚定的全仓深搜。

##### 阶段 C — 兄弟/同类对比

- 同文件、同包、同业务模式的**并行实现**对比（非全仓 Grep 残留，后者属 2d）。

**不做：** 变更函数内纯局部问题（2a），除非由链路透传导致；全仓同类残留 Grep（2d）；本 PR 是否修好声称问题（2c）。

**工具预算：** Grep ≤15。

**输出：** 统一输出格式；ID 前缀 `2b-`。

**覆盖说明门禁（主编排检查）：**

- `- [ ] 一层上下游清单已生成且覆盖全部锚点`
- `- [ ] 清单每一行已核实或注明 skip 原因`
- `- [ ] 扩展项（若有）已记录疑点与结论`
- `- [ ] 兄弟/同类对比已执行或注明 skip 原因`
```

- [ ] **Step 2: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "refactor(audit): rewrite 2b as two-phase one-hop call graph scan"
```

---

### Task 5: 新增 2d — 同类残留审查

**Files:**
- Modify: `plugins/audit/skills/review/SKILL.md`（紧接 2b 段之后、`#### 2c` 之前插入）

- [ ] **Step 1:** 在 `#### 2c — 目的与兼容性审查` **之前**插入：

```markdown
#### 2d — 同类残留审查

sub-agent 扮演**同类残留审查员**。

**触发：** 仅当阶段 1「变更性质」含 **bugfix** 时由主编排委派；非 bugfix 不委派本 agent。

**聚焦：** 当前 PR 修了一处，仓库中是否仍有**相同根因或高度相似模式**的残留（缺陷性质第 3 类）。

**必扫流程（须按序执行）：**

##### 阶段 A — 残留模式提取（只建清单）

1. 从 diff + 阶段 1「变更声称要解决的问题」提取本次修复的**根因模式**（关键字、条件结构、错误处理缺口、API 误用方式等）。
2. 生成 1～3 条可 `Grep` 的**搜索模式**（写入覆盖说明；禁止空泛描述如「类似逻辑」）。
3. 全工程 `Grep`，在「扫描覆盖说明」中必填 **同类残留候选清单**（去重）：

```markdown
### 同类残留候选清单

| 文件 | 函数/位置 | 匹配模式 | 与本次修复相似点 | 是否已读上下文 |
|------|-----------|----------|------------------|----------------|
```

##### 阶段 B — 逐项核实

对清单每一行 `Read` 上下文，判断是否满足共享「缺陷成立条件」中的**真实残留缺陷**。若该处已有 validation/兜底、或并非同根因 → 不输出。

**不做：** 上下游调用链（2b）；本 PR 变更范围内是否修好声称问题（2c）；变更函数内局部缺陷（2a）。

**工具预算：** Grep ≤20。

**输出：** 统一输出格式；ID 前缀 `2d-`。

**覆盖说明门禁（主编排检查，仅已委派时）：**

- `- [ ] 搜索模式（1～3 条）已列出`
- `- [ ] 同类残留候选清单已生成`
- `- [ ] 清单每一行已核实或注明 skip 原因`

```

- [ ] **Step 2: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): add 2d same-pattern residue scanner for bugfix PRs"
```

---

### Task 6: 更新 2c — 边界句 + 删除 Read 预算

**Files:**
- Modify: `plugins/audit/skills/review/SKILL.md`（`#### 2c` 段）

- [ ] **Step 1:** 将 2c 的「必扫 checklist」中「意图」条替换为：

```markdown
- 意图：对照 commit message、PR 标题/描述、comments——审的是**本 PR 变更范围内**是否达成声称修复（是否修好、是否只修部分路径、修复逻辑是否不可达）；**不**负责全仓同类残留（属 2d）
- 兼容性：API 签名/行为、配置项、schema/CRD、默认值、数据迁移、滚动升级、回滚
```

- [ ] **Step 2:** 将 `**Read 预算：** Read ≤30；Grep ≤10。` 替换为 `**工具预算：** Grep ≤10。`

- [ ] **Step 3: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "refactor(audit): clarify 2c intent boundary and remove Read budget"
```

---

### Task 7: 更新统一输出格式与主编排合并

**Files:**
- Modify: `plugins/audit/skills/review/SKILL.md:324-345`

- [ ] **Step 1:** 将 `### 三 agent 统一输出格式` 标题改为 `### 各 agent 统一输出格式`

- [ ] **Step 2:** 将候选标题示例句中的 `2b-1` 保留即可；在 bullet 中补一句：`标题形如 ### 候选缺陷 2d-1：…（2d 已委派时）。`

- [ ] **Step 3:** 替换 `### 主编排合并（不委派）` 整段为：

```markdown
### 主编排合并（不委派）

已委派的 agent 输出收齐后，**主编排**执行：

1. **收集**：保留来源前缀 `2a-` / `2b-` / `2c-` / `2d-`（有则并）直至合并完成。
2. **合并去重**：
   - 相同根因 + 相同落点 → 合并为一条，保留最全证据；
   - 不同根因（如 2a 局部 nil 与 2b 上游未校验）→ **保留多条**；
   - **2b 兄弟对比** 与 **2d 残留** 若命中同一代码落点 → 合并为一条，保留最全证据；
   - **禁止**以「可能性低」或证据不足删除（交给阶段 3）。
3. **覆盖说明门禁**：
   - 已委派 agent 的 checklist 须全部勾选或合理 skip；
   - **2b**：须含完整一层上下游清单及逐项核实记录；
   - **2d**（已委派）：须含残留候选清单及逐项核实记录；
   - 未委派 2d（非 bugfix）→ 不检查 2d 覆盖说明；
   - 任一份存在应扫未扫且无合理 skip → 主编排须 **轻量补查** 或 **再委派该 agent 一次**（附 diff、阶段 1 输出、指出漏项）。
4. **重编号**：合并后改为连续序号 `### 候选缺陷 1` … 供阶段 3 使用。
5. **交给阶段 3**：粘贴合并后的完整「候选缺陷列表」Markdown（可不附原始覆盖说明，但主编排须已处理门禁）。

**合理 skip 示例（须在覆盖说明写明）：** 纯 `docs`/`*.md`；纯注释/格式化无行为变化。
```

- [ ] **Step 4: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "refactor(audit): update merge gate for 2b inventory and conditional 2d"
```

---

### Task 8: 阶段 3 删除 Read 上限 + 防漏报措辞

**Files:**
- Modify: `plugins/audit/skills/review/SKILL.md:377-381`

- [ ] **Step 1:** 将防漏报第二条 bullet 中的 `2a/2b/2c` 改为 `2a/2b/2c/2d`：

```markdown
- 仅当反证后**证据不足**才可删除；**不得**因「2a/2b/2c/2d 中其他 agent 未报同一问题」而删除。
```

- [ ] **Step 2:** 将第三条 bullet

```markdown
- 不重新全量审计；允许对单条候选 **Read 锚点函数** 核实反证（建议 ≤10 Read/条）。
```

替换为：

```markdown
- 不重新全量审计；允许对单条候选 **Read 锚点函数** 核实反证（不设 Read 数量上限）。
```

- [ ] **Step 3: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "refactor(audit): remove Read cap from stage-3 QA rules"
```

---

### Task 9: 结构验收（rg）

**Files:**
- Test: `plugins/audit/skills/review/SKILL.md`

- [ ] **Step 1: 确认无 Read 预算残留**

```bash
rg -n 'Read ≤|Read 预算' plugins/audit/skills/review/SKILL.md
```

Expected: **无匹配**（exit code 1）

- [ ] **Step 2: 确认 2b 旧表述已删除**

```bash
rg -n '顶层可达入口|关键下游|bugfix 残留' plugins/audit/skills/review/SKILL.md
```

Expected: **无匹配**

- [ ] **Step 3: 确认新结构存在**

```bash
rg -n '一层上下游清单|同类残留候选清单|#### 2d —|条件 2d|Grep ≤15|Grep ≤20' plugins/audit/skills/review/SKILL.md
```

Expected: 至少匹配 6 行

- [ ] **Step 4: 确认 2c 边界句**

```bash
rg -n '不负责全仓同类残留' plugins/audit/skills/review/SKILL.md
```

Expected: 匹配 1 行（2c 意图条）

---

### Task 10: 更新 plugin.json

**Files:**
- Modify: `plugins/audit/.claude-plugin/plugin.json`

- [ ] **Step 1:** 将 `version` 从 `0.7.6` 改为 `0.7.7`

- [ ] **Step 2:** 将 `description` 改为：

```json
"description": "对 PR/commit/diff 做缺陷审计；阶段2 并行扫描（2a/2b/2c + bugfix 时 2d 残留），2b 一层上下游清单，主编排合并后质检"
```

- [ ] **Step 3: Commit**

```bash
git add plugins/audit/.claude-plugin/plugin.json
git commit -m "chore(audit): bump plugin to 0.7.7 for 2b/2d scanner split"
```

---

### Task 11: 标记设计 spec 已实施

**Files:**
- Modify: `docs/superpowers/specs/2026-06-06-audit-review-2b-2d-design.md:4`

- [ ] **Step 1:** 将 `**状态：** 待实施` 改为 `**状态：** 已实施`

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-06-06-audit-review-2b-2d-design.md
git commit -m "docs: mark audit 2b/2d design spec as implemented"
```

---

## Spec 覆盖自检

| Spec 要求 | 对应 Task |
|-----------|-----------|
| 2b 两阶段一层清单 | Task 4 |
| 多锚点合并去重 | Task 4 阶段 A step 3 |
| 按需扩展 | Task 4 阶段 B |
| 兄弟对比留 2b | Task 4 阶段 C |
| 2d 仅 bugfix | Task 1, 2, 5 |
| 2c 修复完整性边界 | Task 6 |
| 删除 Read 预算 | Task 3, 4, 6, 8 + Task 9 |
| 主编排合并 2d | Task 7 |
| plugin.json | Task 10 |
| 验收 rg | Task 9 |
