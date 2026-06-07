# audit/review 2d 始终委派 & 双模式扫描实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 2d 改为始终与 2a/2b/2c 并行委派；2d 内部通过意图识别选择全仓或轻量模式；阶段 1 标签不再门控 2d。

**Architecture:** 仅改 `plugins/audit/skills/review/SKILL.md` 与 `plugin.json`；编排层固定 4 Task；2d 新增阶段 0' + 轻量模式分支；全仓模式沿用现有阶段 A/B；用 `rg` 校验。

**Tech Stack:** Markdown skill；`rg` 结构校验。

**Reference:** [`docs/superpowers/specs/2026-06-08-audit-review-2d-always-dispatch-design.md`](../specs/2026-06-08-audit-review-2d-always-dispatch-design.md)

---

## 文件结构

| 路径 | 改动 | Task |
|------|------|------|
| `plugins/audit/skills/review/SKILL.md` | 编排固定 4 Task；阶段 1 去门控；2d 双模式 | 1–4 |
| `plugins/audit/.claude-plugin/plugin.json` | 版本 + description | 5 |
| `docs/superpowers/specs/2026-06-08-audit-review-2d-always-dispatch-design.md` | 状态 → implemented | 5 |

---

## Task 1: 编排层 — 固定 4 Task

**Files:**

- Modify: `plugins/audit/skills/review/SKILL.md`（L5、L150）

- [ ] **Step 1: 替换文首主编排描述（L5）**

将：

```markdown
你是本次审计的**主编排者**。接收用户输入后**先执行阶段 0 变更预处理**；若无可审生产代码变更则快速结束；否则委派阶段 1；**并行**委派阶段 2 的 2a/2b/2c 三个 specialist agent（若阶段 1「变更性质」含 **bugfix** 或任意 **optimization/<子标签>**，同时并行委派 **2d**），阶段 2 **禁止串行**等待 scanner；由你合并候选缺陷并做覆盖说明门禁；再委派阶段 3 质检；最后由你执行阶段 4 报告拼装并输出最终报告。禁止修改被审仓库代码；禁止运行测试。
```

改为：

```markdown
你是本次审计的**主编排者**。接收用户输入后**先执行阶段 0 变更预处理**；若无可审生产代码变更则快速结束；否则委派阶段 1；**并行**委派阶段 2 的 2a/2b/2c/**2d** 四个 specialist agent（**2d 始终委派**；工作模式由 2d 自决），阶段 2 **禁止串行**等待 scanner；由你合并候选缺陷并做覆盖说明门禁；再委派阶段 3 质检；最后由你执行阶段 4 报告拼装并输出最终报告。禁止修改被审仓库代码；禁止运行测试。
```

- [ ] **Step 2: 替换总体流程第 2 步（L150）**

将：

```text
2. 代码缺陷扫描（并行 2a / 2b / 2c [+ bugfix 或 optimization 时 2d] → 主编排合并）
```

改为：

```text
2. 代码缺陷扫描（并行 2a / 2b / 2c / 2d → 主编排合并）
```

- [ ] **Step 3: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): always dispatch 2d in review flow header"
```

---

## Task 2: 阶段 1 — 删除 2d 门控

**Files:**

- Modify: `plugins/audit/skills/review/SKILL.md`（L178–238）

- [ ] **Step 1: 重命名节标题并删除 `### 2d 委派规则`**

将 `## 变更性质与 2d 委派` 改为 `## 变更性质`。

删除自 `### 2d 委派规则` 至 `复合标签按**或**逻辑；判定以可审 diff 实际行为为准，不以 PR 标题用词为准。`（含该句，L206–213）整段。

在 taxonomy 子标签表后的 `判定以**可审 diff 实际行为**为准，不以 PR 标题用词为准。` 之后追加：

```markdown

变更性质标签仅用于报告与阶段 2 上下文；**不**门控是否委派 2d（2d 始终委派，见 2d 阶段 0'）。
```

- [ ] **Step 2: 更新阶段 1 限制（L238）**

将：

```markdown
- 不得暗示非 `bugfix` / 非 `optimization/<子标签>` 变更可由 2b 代做全仓同类残留扫描（残留属 2d，仅含 `bugfix` 或 `optimization/<子标签>` 时委派）。
```

改为：

```markdown
- 不得暗示 2b 可代做 2d 全仓同类残留扫描或 2d 轻量同包缺陷模式扫描（残留属 2d，2d 始终委派）。
- 不得因阶段 1 变更性质不含 bugfix/optimization 而暗示 2d 可跳过（2d 始终委派）。
```

- [ ] **Step 3: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): remove stage 1 gate for 2d dispatch"
```

---

## Task 3: 阶段 2 编排 — 固定 4 Task 规则

**Files:**

- Modify: `plugins/audit/skills/review/SKILL.md`（L249、L270–304）

- [ ] **Step 1: 替换 `# 2. 代码缺陷扫描` 目标段（L249）**

将：

```markdown
**并行**委派 specialist sub-agent：**始终** 2a / 2b / 2c；**当且仅当**阶段 1「变更性质」含 **bugfix** 或任意 **optimization/<子标签>** 时，**同时**委派 2d。
```

改为：

```markdown
**并行**委派 specialist sub-agent：**始终** 2a / 2b / 2c / **2d**（固定 4 个 Task）。2d 工作模式（全仓 / 轻量）由 2d 在阶段 0' 自决，**不得**因阶段 1 变更性质而跳过委派。
```

- [ ] **Step 2: 替换并行委派 Task 数量规则（L270–272）**

将：

```markdown
- 阶段 1 完成后，**先**在编排上下文写好共享输入（可审 diff + 阶段 1 全文 + 共享规则 + 变更预处理摘要），**再**在同一轮回复一次性发起 `Task`：
  - **不含 bugfix 且不含 optimization**（阶段 1 变更性质仅 feature / refactor / test / docs / other）：**三次** Task（2a / 2b / 2c）
  - **含 bugfix 或 optimization**（阶段 1 变更性质含 `bugfix` 或任意 `optimization/<子标签>`）：**四次** Task（2a / 2b / 2c / 2d）
```

改为：

```markdown
- 阶段 1 完成后，**先**在编排上下文写好共享输入（可审 diff + 阶段 1 全文 + 共享规则 + 变更预处理摘要），**再**在同一轮回复一次性发起 **四次** `Task`（2a / 2b / 2c / 2d）
```

- [ ] **Step 3: 替换委派前准备步骤 1（L285）**

将：

```text
1. 确认阶段 1「变更性质」是否含 bugfix 或 optimization/<子标签> → 确定 Task 数量（3 或 4）
```

改为：

```text
1. 确认阶段 2 须发起 4 个 Task（2a / 2b / 2c / 2d），无 3 Task 分支
```

- [ ] **Step 4: 替换阶段 2 委派自检（L294–295）**

将：

```markdown
- [ ] 已在同一轮回复发起全部 Task（3 或 4 个）
- [ ] 2a / 2b / 2c（及 2d 若含 bugfix 或 optimization）输出均已收齐
```

改为：

```markdown
- [ ] 已在同一轮回复发起全部 Task（4 个：2a / 2b / 2c / 2d）
- [ ] 2a / 2b / 2c / 2d 输出均已收齐
```

- [ ] **Step 5: 替换子阶段表 2d 委派条件（L304）**

将：

```markdown
| **2d** | 同类残留审查 | 全仓同模式 Grep 与核实 | 含 bugfix 或 optimization |
```

改为：

```markdown
| **2d** | 同类残留审查 | 意图识别后全仓或轻量同包扫描 | 始终 |
```

- [ ] **Step 6: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): fix stage 2 to always run four parallel scanners"
```

---

## Task 4: 2d 重写 — 阶段 0'、双模式、合并门禁

**Files:**

- Modify: `plugins/audit/skills/review/SKILL.md`（L756–852、L876–877）

- [ ] **Step 1: 将 `### 2d — 同类残留审查` 触发段至 `#### 阶段 A` 之前替换为以下全文**

（保留原 `#### 阶段 A` 标题，在其前插入新内容；将原触发段删除）

在 `sub-agent 扮演**同类残留审查员**。` 之后、`#### 阶段 A` 之前插入：

```markdown

**触发：** **始终**由主编排委派；**不得**因阶段 1 变更性质不含 bugfix/optimization 而跳过。

**聚焦：** 当前 PR 修了一处或做行为改进后，仓库（全仓或同包）中是否仍存在同类残留缺陷。只审查缺陷性质第 3 类，或轻量模式下同包兄弟缺失对等防护且构成真实缺陷。

**聚焦不变：** 不得将性能改进点、体验建议、风格不一致作为 finding。

**与 2b 边界：** 2b 负责调用链与一层上下游；2d **不**追 caller。2d 轻量模式只做同包/模块内「可泛化缺陷模式」兄弟对等核实。

**不做：**
- 不做本 PR 变更范围内是否修好声称问题，属 2c；
- 不做变更函数内局部语言缺陷扫描，属 2a；
- 不做上下游调用链深挖，属 2b；
- 不因代码形态相似就泛化为残留，必须证明同根因（全仓）或同等缺陷模式缺失（轻量）、同触发、同后果。

#### 阶段 0' — 意图识别（必做）

从**可审 diff**（主依据）+ 阶段 1「变更声称」（参考，非决定性）识别 bug 修复意图与优化改进意图。

**bug 修复意图信号（满足任一）：** 补条件判断/分支/边界；补或修正错误处理/资源清理/rollback；纠正 API/库/框架误用；修正默认值/配置/schema；补状态机/enum/mode 分支；补 nil/空值/越界/生命周期/并发保护；补权限/认证/校验。

**优化改进意图信号（满足任一，且 diff 有行为变化）：** 正确性/健壮性/安全性改进；体验/交互/可观测性改进（**非**纯文案/注释）；与兄弟实现或约定对齐的行为调整。

**不视为优化改进意图（倾向轻量模式）：** 纯 rename/纯提取/纯新增 API 骨架；纯 performance 且未触及缺陷模式；纯文案/注释/日志措辞。

**判定：**
- 识别到 **任一** bug 修复意图 **或** 优化改进意图 → **全仓模式**（执行下方「全仓模式 — 阶段 A/B」）
- 均未识别 → **轻量模式**（执行下方「轻量模式 — 阶段 L-A/L-B」）

「扫描覆盖说明」**必填**：
- `2d 工作模式`：`全仓` | `轻量`
- `意图识别结论`：一句话

#### 全仓模式 — 阶段 A/B
```

- [ ] **Step 2: 将原 `#### 阶段 A — 残留模式提取与候选定位` 标题改为与上文衔接**

将：

```markdown
#### 阶段 A — 残留模式提取与候选定位
```

改为：

```markdown
（全仓模式）#### 阶段 A — 残留模式提取与候选定位
```

将原 `#### 阶段 B — 逐项上下文核实` 改为：

```markdown
（全仓模式）#### 阶段 B — 逐项上下文核实
```

- [ ] **Step 3: 在 `（全仓模式）#### 阶段 B` 段落后、`#### 输出要求` 之前插入轻量模式全文**

```markdown

#### 轻量模式 — 阶段 L-A / L-B

当阶段 0' 判定为**轻量模式**时执行（**禁止**全仓 Grep）。

**阶段 L-A — 同包缺陷模式提取与兄弟定位**

1. **范围：** 变更锚点所在**包/模块**（同 Go package、同 Python module、同 TS 目录层级等）。
2. **提取缺陷模式（1～3 条）：** 从 diff 尝试提取可泛化模式（校验、错误处理、nil 检查等）；若纯新增/rename 无可提取模式，须在覆盖说明注明。
3. **定位同包并行实现：** 同文件、同包、同 struct/class 兄弟方法，或同业务模式并行函数（**只问缺陷模式对等**，不问调用链）。
4. 在「扫描覆盖说明」填写：

```markdown
### 轻量模式 — 同包范围与兄弟清单

| 包/模块范围 | 提取的缺陷模式 | 兄弟符号 | 文件 | 是否进入核实 | 原因 |
|-------------|----------------|----------|------|--------------|------|
```

**阶段 L-B — 逐项对等核实**

对每个兄弟实现 `Read` 上下文，检查是否缺少与本次变更对等的防护。

同类残留成立条件与全仓模式阶段 B 相同（同根因或同等缺陷模式缺失、生产路径、同触发、无现有防护、有明确后果）。

在「扫描覆盖说明」填写：

| 文件 | 函数/位置 | 判定 | 核实原因 | 是否输出 finding |
|------|-----------|------|----------|------------------|

**轻量模式不得：** 以「无意图」为由空白返回；做全仓 Grep；将性能/风格/命名问题作为 finding。
```

- [ ] **Step 4: 替换 2d `#### 覆盖说明门禁` 整段（L843–852）**

将：

```markdown
#### 覆盖说明门禁

主编排仅在已委派 2d 时检查以下门禁：

- [ ] 已提取本次修复的根因模式（来自 diff + 阶段 1 变更声称）；
- [ ] 搜索模式已列出，并说明每条模式的覆盖意图；
- [ ] 若搜索模式少于 3 条，已说明原因；
- [ ] 同类残留候选清单已生成；
- [ ] 候选清单每一行已核实，或注明未进入核实 / skip 原因；
- [ ] 输出 finding 均满足同根因、同触发、无现有防护、有明确后果。
```

改为：

```markdown
#### 覆盖说明门禁

主编排**始终**检查 2d 门禁（2d 始终委派）：

- [ ] `2d 工作模式` 已标注（全仓 / 轻量）
- [ ] `意图识别结论` 已填写
- [ ] **全仓模式**：已提取根因模式；搜索模式已列出及覆盖意图；候选清单已生成并逐项核实或注明 skip
- [ ] **轻量模式**：同包/模块范围已说明；缺陷模式（1～3 条）已列出或注明无可提取；兄弟对比清单已生成；逐项核实或 skip 原因已记录
- [ ] 输出 finding 均满足成立条件（全仓：同根因、同触发、无防护、有后果；轻量：同等缺陷模式缺失且构成真实缺陷）
```

- [ ] **Step 5: 替换主编排合并 2d 门禁（L876–877）**

将：

```markdown
   - **2d**（已委派）：须满足 2d 覆盖说明门禁全部勾选（根因模式、搜索模式清单及覆盖意图、同类残留候选清单、候选核实结果）；
   - 未委派 2d（未含 bugfix 且未含 optimization）→ 不检查 2d 覆盖说明；
```

改为：

```markdown
   - **2d**（始终委派）：须满足 2d 覆盖说明门禁（含工作模式、意图识别结论；全仓或轻量分支 checklist 均已勾选或合理 skip）；
```

- [ ] **Step 6: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): add 2d intent detection and dual-mode scanning"
```

---

## Task 5: plugin.json、spec 状态与校验

**Files:**

- Modify: `plugins/audit/.claude-plugin/plugin.json`
- Modify: `docs/superpowers/specs/2026-06-08-audit-review-2d-always-dispatch-design.md`

- [ ] **Step 1: bump plugin.json**

`version`: `1.0.3` → `1.0.4`

`description`:

```json
"description": "对 PR/commit/diff 做缺陷审计；2d 始终委派、内部全仓/轻量双模式；optimization 子标签 taxonomy；T3 v3 参考触发场景；可选 T4 非触发场景"
```

- [ ] **Step 2: 更新 spec 状态**

```markdown
**状态：** implemented（2026-06-08，见 plan `2026-06-08-audit-review-2d-always-dispatch.md`）
```

- [ ] **Step 3: 结构校验**

```bash
rg -n '三次.*Task|3 或 4|residue_scan' plugins/audit/skills/review/SKILL.md || echo "OK: no 3-task branch or residue_scan"
rg -n '2d 始终|始终委派|固定 4' plugins/audit/skills/review/SKILL.md
rg -n '阶段 0'"'"'|轻量模式|全仓模式' plugins/audit/skills/review/SKILL.md
rg -n '含 bugfix 或 optimization' plugins/audit/skills/review/SKILL.md || echo "OK: no tag-based 2d gate"
```

Expected:
- 第一、四命令：零匹配（或仅阶段 1 taxonomy 表内「bugfix」字样，非门控）
- 第二命令：≥3 处「始终」相关表述
- 第三命令：≥5 处双模式相关表述

- [ ] **Step 4: Commit**

```bash
git add plugins/audit/.claude-plugin/plugin.json docs/superpowers/specs/2026-06-08-audit-review-2d-always-dispatch-design.md docs/superpowers/plans/2026-06-08-audit-review-2d-always-dispatch.md
git commit -m "chore(audit): bump plugin to 1.0.4 and mark 2d-always-dispatch spec implemented"
```

---

## Spec 覆盖自检

| Spec § | Task |
|--------|------|
| § 2d 始终委派 | Task 1, 3 |
| § 阶段 1 去门控 | Task 2 |
| § 阶段 0' 意图识别 | Task 4 Step 1 |
| § 全仓模式 | Task 4 Step 2 |
| § 轻量模式 | Task 4 Step 3 |
| § 2b/2d 边界 | Task 4 Step 1 |
| § 覆盖说明门禁 | Task 4 Step 4–5 |
| § 验收标准 | Task 5 Step 3 |

无 TBD/占位符。

---

## 执行选项

Plan 已保存至 `docs/superpowers/plans/2026-06-08-audit-review-2d-always-dispatch.md`。

**1. Subagent-Driven（推荐）** — 每个 Task 派生子 agent，任务间 review

**2. Inline Execution** — 本会话按 Task 1→5 顺序直接改 SKILL.md

请选择执行方式。
