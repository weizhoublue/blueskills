# audit/review 变更性质扩展 & residue_scan 2d 触发实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `audit/review` SKILL 中扩展 `optimization` 子标签 taxonomy，引入 `residue_scan` 字段，并将 2d 委派条件从「含 bugfix」改为「`residue_scan=yes`」。

**Architecture:** 仅改 `plugins/audit/skills/review/SKILL.md` 与 `plugin.json`；阶段 1 增加 taxonomy + 启发式 + 输出字段；阶段 2 编排与 2d 触发全文替换；2d 内部流程不变；用 `rg` 做结构校验，无 pytest。

**Tech Stack:** Markdown skill；`rg` 结构校验。

**Reference:** [`docs/superpowers/specs/2026-06-07-audit-review-optimization-residue-scan-design.md`](../specs/2026-06-07-audit-review-optimization-residue-scan-design.md)

---

## 文件结构

| 路径 | 改动 | Task |
|------|------|------|
| `plugins/audit/skills/review/SKILL.md` | taxonomy、residue_scan、2d 触发 | 1–4 |
| `plugins/audit/.claude-plugin/plugin.json` | 版本 + description | 5 |
| `docs/superpowers/specs/2026-06-07-audit-review-optimization-residue-scan-design.md` | 状态 → implemented | 5 |

---

## Task 1: 文首流程与总体流程图

**Files:**

- Modify: `plugins/audit/skills/review/SKILL.md`（L5、L150）

- [ ] **Step 1: 替换文首主编排描述（L5）**

将：

```markdown
你是本次审计的**主编排者**。接收用户输入后**先执行阶段 0 变更预处理**；若无可审生产代码变更则快速结束；否则委派阶段 1；**并行**委派阶段 2 的 2a/2b/2c 三个 specialist agent（若阶段 1「变更性质」含 **bugfix**，同时并行委派 **2d**），阶段 2 **禁止串行**等待 scanner；由你合并候选缺陷并做覆盖说明门禁；再委派阶段 3 质检；最后由你执行阶段 4 报告拼装并输出最终报告。禁止修改被审仓库代码；禁止运行测试。
```

改为：

```markdown
你是本次审计的**主编排者**。接收用户输入后**先执行阶段 0 变更预处理**；若无可审生产代码变更则快速结束；否则委派阶段 1；**并行**委派阶段 2 的 2a/2b/2c 三个 specialist agent（若阶段 1「残留扫描（residue_scan）」为 **yes**，同时并行委派 **2d**），阶段 2 **禁止串行**等待 scanner；由你合并候选缺陷并做覆盖说明门禁；再委派阶段 3 质检；最后由你执行阶段 4 报告拼装并输出最终报告。禁止修改被审仓库代码；禁止运行测试。
```

- [ ] **Step 2: 替换总体流程第 2 步（L150）**

将：

```text
2. 代码缺陷扫描（并行 2a / 2b / 2c [+ 条件 2d] → 主编排合并）
```

改为：

```text
2. 代码缺陷扫描（并行 2a / 2b / 2c [+ residue_scan=yes 时 2d] → 主编排合并）
```

- [ ] **Step 3: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): wire 2d dispatch to residue_scan in review flow header"
```

---

## Task 2: 阶段 1 — taxonomy、residue_scan 与输出模板

**Files:**

- Modify: `plugins/audit/skills/review/SKILL.md`（L178–204，在 `## 分析内容` 与 `## 输出` 之间插入新节）

- [ ] **Step 1: 在 `## 分析内容` 段落后、`## 输出` 前插入 `## 变更性质与残留扫描`**

在 L177（`- 变更涉及的函数、类型、配置、API。`）之后、`## 输出` 之前插入：

```markdown
## 变更性质与残留扫描

### 变更性质 taxonomy

**顶层类型（可多选复合）：**

| 标签 | 含义 |
|------|------|
| `bugfix` | 修复已知错误行为、崩溃、数据错误、安全漏洞等 |
| `feature` | 新增能力、API、配置项、用户可见功能 |
| `refactor` | 结构调整、重命名、提取函数；**对外行为声称不变** |
| `test` | 测试代码变更（可审 diff 中仍有生产代码时可与其它标签复合） |
| `docs` | 文档变更（可审 diff 通常已在阶段 0 排除） |
| `optimization/<子标签>` | 改进类变更；**须**带子标签（下表） |
| `other` | 兜底；**不得**与 `optimization` 同时使用 |

**`optimization` 子标签（出现 `optimization` 时必选且仅选一个）：**

| 子标签 | 含义 | 典型示例 |
|--------|------|----------|
| `optimization/correctness` | 正确性 / 安全性 / 健壮性改进 | 补输入校验、防御性 nil 检查、修错误默认值 |
| `optimization/performance` | 性能、资源占用 | 缓存、批处理、减少分配 |
| `optimization/ux` | 体验、文案、交互、可观测性（非缺陷） | 错误提示更清晰、日志更易读 |
| `optimization/consistency` | 与兄弟实现或项目约定对齐，行为声称不变 | 统一错误处理风格 |
| `optimization/workflow` | 开发 / 运维 / 发布流程改进 | CI 步骤、脚本、内部工具链 |

判定以**可审 diff 实际行为**为准，不以 PR 标题用词为准。

### 残留扫描（residue_scan）

除变更性质外，本阶段**必须**独立判定 `residue_scan: yes | no`，供阶段 2 决定是否委派 2d。

**语义：** 本次变更是否修复（或引入防护针对）一种**可能在仓库其他生产代码位置以相同根因复现的缺陷模式**。

**`residue_scan: yes`（满足任一且 diff 体现具体代码模式修复）：**

1. 缺失的条件判断、分支、边界处理被补上
2. 缺失或错误的错误处理、资源清理、rollback 被补上
3. API / 库 / 框架误用方式被纠正
4. 错误的默认值、配置解析、schema 处理被修正
5. 状态机 / enum / mode 分支遗漏被补上
6. nil / 空值 / 越界 / 生命周期 / 并发保护缺失被补上
7. 权限、认证、校验遗漏被补上

**`residue_scan: no`：**

1. 纯文案、注释、日志措辞（无行为变化）
2. 纯性能优化且不改变正确性语义
3. 纯重构 / 一致性调整，未触及上述缺陷模式
4. 单点笔误、单一配置项、单一常量修正，**无可泛化的搜索模式**（须在判定依据中说明）
5. 新增 feature 的主路径实现，非「修复既有错误模式」

**边界：** 不确定时倾向 `yes` 并在「不确定信息」注明；**不得**因 PR 标题含「优化」默认 `no`。**不得**将 `residue_scan` 绑死为「含 bugfix → yes、不含 → no」。

**与 2d 的关系：** `residue_scan` 决定是否委派 2d；变更性质标签（含 `optimization` 子标签）仅用于报告描述，**不**单独决定 2d。

```

- [ ] **Step 2: 替换阶段 1 `## 输出` 模板（L180–195）**

将：

```markdown
```markdown
## 变更意图分析

- 变更性质：
  - bugfix / feature / refactor / test / docs  / other

- 变更声称要解决的问题：

- 变更声称要实现的行为：

- 涉及的主要文件：

- PR comments / review comments 中提到的注意点：

- 不确定信息：
```
```

改为：

```markdown
```markdown
## 变更意图分析

- 变更性质：（可多选）
  - bugfix / feature / refactor / test / docs / optimization/<子标签> / other

- 残留扫描（residue_scan）：yes | no

- 残留扫描判定依据：

- 变更声称要解决的问题：

- 变更声称要实现的行为：

- 涉及的主要文件：

- PR comments / review comments 中提到的注意点：

- 不确定信息：
```
```

- [ ] **Step 3: 替换阶段 1 `## 限制` 中 2d 相关条目（L201）**

将：

```markdown
- 不得暗示非 bugfix 变更可由 2b 代做全仓同类残留扫描（残留属 2d，仅 bugfix 委派）。
```

改为：

```markdown
- 不得暗示非 `residue_scan=yes` 变更可由 2b 代做全仓同类残留扫描（残留属 2d，仅 `residue_scan=yes` 委派）。
- 不得将 `residue_scan` 默认绑死为「含 bugfix → yes、不含 → no」；须按「变更性质与残留扫描」启发式独立判定。
```

- [ ] **Step 4: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): add optimization taxonomy and residue_scan to stage 1"
```

---

## Task 3: 阶段 2 编排 — 2d 触发与并行委派规则

**Files:**

- Modify: `plugins/audit/skills/review/SKILL.md`（L212、L234–235、L248、L258、L267）

- [ ] **Step 1: 替换 `# 2. 代码缺陷扫描` 目标段（L212）**

将：

```markdown
**并行**委派 specialist sub-agent：**始终** 2a / 2b / 2c；**当且仅当**阶段 1「变更性质」含 **bugfix** 时，**同时**委派 2d。
```

改为：

```markdown
**并行**委派 specialist sub-agent：**始终** 2a / 2b / 2c；**当且仅当**阶段 1「残留扫描（residue_scan）」为 **yes** 时，**同时**委派 2d。
```

- [ ] **Step 2: 替换并行委派 Task 数量规则（L234–235）**

将：

```markdown
  - **非 bugfix**（阶段 1 变更性质不含 `bugfix`）：**三次** Task（2a / 2b / 2c）
  - **bugfix**（阶段 1 变更性质含 `bugfix`）：**四次** Task（2a / 2b / 2c / 2d）
```

改为：

```markdown
  - **residue_scan=no**（阶段 1 残留扫描为 `no`）：**三次** Task（2a / 2b / 2c）
  - **residue_scan=yes**（阶段 1 残留扫描为 `yes`）：**四次** Task（2a / 2b / 2c / 2d）
```

- [ ] **Step 3: 替换委派前准备步骤 1（L248）**

将：

```text
1. 确认阶段 1「变更性质」是否含 bugfix → 确定 Task 数量（3 或 4）
```

改为：

```text
1. 确认阶段 1「残留扫描（residue_scan）」为 yes 或 no → 确定 Task 数量（3 或 4）
```

- [ ] **Step 4: 替换阶段 2 委派自检（L258）**

将：

```markdown
- [ ] 2a / 2b / 2c（及 2d 若 bugfix）输出均已收齐
```

改为：

```markdown
- [ ] 2a / 2b / 2c（及 2d 若 residue_scan=yes）输出均已收齐
```

- [ ] **Step 5: 替换子阶段表 2d 委派条件（L267）**

将：

```markdown
| **2d** | 同类残留审查 | 全仓同模式 Grep 与核实 | 仅 bugfix |
```

改为：

```markdown
| **2d** | 同类残留审查 | 全仓同模式 Grep 与核实 | 仅 residue_scan=yes |
```

- [ ] **Step 6: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): dispatch 2d on residue_scan=yes in stage 2 orchestration"
```

---

## Task 4: 2d 触发段、合并门禁与阶段 4 背景说明

**Files:**

- Modify: `plugins/audit/skills/review/SKILL.md`（L723、L809、L839、L952 附近）

- [ ] **Step 1: 替换 2d 触发段（L723）**

将：

```markdown
**触发：** 仅当阶段 1「变更性质」含 **bugfix** 时由主编排委派；非 bugfix 不委派本 agent。
```

改为：

```markdown
**触发：** 仅当阶段 1「残留扫描（residue_scan）」为 **yes** 时由主编排委派；`residue_scan=no` 不委派本 agent。
**聚焦不变：** 只审查缺陷性质第 3 类（仓库中其他代码的同类残留缺陷）；不得将性能改进点、体验建议、风格不一致作为 finding。
```

- [ ] **Step 2: 替换 2d 覆盖说明门禁首项（L809）**

将：

```markdown
- [ ] 已提取本次 bugfix 的根因模式；
```

改为：

```markdown
- [ ] 已提取本次修复的根因模式（来自 diff + 阶段 1 变更声称）；
```

- [ ] **Step 3: 替换主编排合并未委派 2d 说明（L839）**

将：

```markdown
   - 未委派 2d（非 bugfix）→ 不检查 2d 覆盖说明；
```

改为：

```markdown
   - 未委派 2d（residue_scan=no）→ 不检查 2d 覆盖说明；
```

- [ ] **Step 4: 在阶段 4「处理规则」列表末尾（`全排除场景已在阶段 0 快速结束` 一条之后）追加**

```markdown
- 「代码变更背景」可引用阶段 1 的变更性质列表；若 `residue_scan=yes`，可用一句话概括残留扫描判定依据；不展开 2d 扫描过程。
```

- [ ] **Step 5: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): align 2d trigger and merge gates with residue_scan"
```

---

## Task 5: plugin.json、spec 状态与校验

**Files:**

- Modify: `plugins/audit/.claude-plugin/plugin.json`
- Modify: `docs/superpowers/specs/2026-06-07-audit-review-optimization-residue-scan-design.md`

- [ ] **Step 1: bump plugin.json**

将 `version` 从 `1.0.1` 改为 `1.0.2`，`description` 改为：

```json
"description": "对 PR/commit/diff 做缺陷审计；optimization 子标签 taxonomy；residue_scan 控制 2d 同类残留扫描；T3 v3 参考触发场景；可选 T4 非触发场景"
```

- [ ] **Step 2: 更新 spec 状态**

将 design spec 头部：

```markdown
**状态：** 待实施
```

改为：

```markdown
**状态：** implemented（2026-06-07，见 plan `2026-06-07-audit-review-optimization-residue-scan.md`）
```

- [ ] **Step 3: 结构校验**

```bash
rg -n 'residue_scan' plugins/audit/skills/review/SKILL.md
rg -n 'optimization/' plugins/audit/skills/review/SKILL.md
rg -n '变更性质.*含.*bugfix|仅 bugfix|非 bugfix' plugins/audit/skills/review/SKILL.md || echo "OK: no stale bugfix-only 2d triggers"
```

Expected:

- 第一命令：≥10 处匹配 `residue_scan`
- 第二命令：≥5 处匹配 `optimization/`
- 第三命令：零匹配（或仅出现在 taxonomy 表「典型 bugfix」示例叙述中；若命中 L212 旧文案则说明 Task 3 未完成）

- [ ] **Step 4: Commit**

```bash
git add plugins/audit/.claude-plugin/plugin.json docs/superpowers/specs/2026-06-07-audit-review-optimization-residue-scan-design.md docs/superpowers/plans/2026-06-07-audit-review-optimization-residue-scan.md
git commit -m "chore(audit): bump plugin to 1.0.2 and mark optimization-residue-scan spec implemented"
```

---

## Spec 覆盖自检

| Spec § | Task |
|--------|------|
| § 变更性质 taxonomy | Task 2 Step 1 |
| § residue_scan 字段与启发式 | Task 2 Step 1 |
| § 2d 触发规则 | Task 1, 3, 4 |
| § 阶段 1 输出格式 | Task 2 Step 2 |
| § 阶段 1 限制 | Task 2 Step 3 |
| § 阶段 2 编排变更摘要 | Task 3 |
| § 2d 职责不变 | Task 4 Step 1 |
| § 阶段 4 报告 | Task 4 Step 4 |
| § 验收标准 | Task 5 Step 3 |
| § 非目标（不改 E1/R1/T3、不新增 2e） | 未触及 |

无 TBD/占位符。

---

## 执行选项

Plan 已保存至 `docs/superpowers/plans/2026-06-07-audit-review-optimization-residue-scan.md`。

**1. Subagent-Driven（推荐）** — 每个 Task 派生子 agent，任务间 review

**2. Inline Execution** — 本会话按 Task 1→5 顺序直接改 SKILL.md

请选择执行方式。
