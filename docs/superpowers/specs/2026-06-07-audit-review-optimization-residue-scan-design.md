# audit review 变更性质扩展 & 2d 残留扫描触发重构设计

**日期：** 2026-06-07  
**状态：** 待实施  
**插件：** `plugins/audit`（skill：`review`）

---

## 背景

`plugins/audit/skills/review/SKILL.md` 阶段 1 的「变更性质」目前为：

`bugfix / feature / refactor / test / docs / other`

实践中存在大量**标题或描述写为「优化 / 改进」**的 PR，其语义混合了多种子类型：

- 隐性缺陷修复（补校验、防崩溃、修默认值）
- 纯体验 / 流程（文案、交互顺序）
- 性能（缓存、算法、资源）
- 代码一致性（统一错误处理风格，行为不变）

这些变更若落入 `other` 或 `refactor`，报告描述粗糙；若强行标为 `bugfix`，又与 PR 自称不符。

与此同时，**2d（同类残留审查）** 的触发条件绑定在「变更性质含 `bugfix`」。导致：

- 「优化：补充缺失校验」类 PR 可能被标为非 bugfix → **2d 被跳过**，漏掉全仓同类残留；
- 规则让读者误以为「只要叫 optimization 就不跑 2d」，与 2d 的真实目的（**是否存在可泛化的缺陷模式残留**）不一致。

---

## 目标

1. **扩展变更性质 taxonomy**：新增 `optimization` 及固定子标签，支持混合优化类 PR 的准确描述。
2. **解耦 2d 触发条件**：引入独立字段 `residue_scan: yes | no`，**当且仅当 `yes` 时委派 2d**，不再仅依赖是否含 `bugfix`。
3. **保持 2d 职责不变**：2d 仍只做「仓库中其他代码的同类残留缺陷」（缺陷性质第 3 类），不扩展为泛泛优化扫描。
4. **向后兼容默认行为**：典型 bugfix PR 默认 `residue_scan=yes`，与现网「bugfix → 委派 2d」一致。

---

## 非目标

- 不新增 2e 或其他 scanner；2a/2b/2c 职责与并行规则不变。
- 不因 `optimization` 标签自动跑 2d（避免方案 D：全 optimization 全仓 Grep）。
- 不改变缺陷成立条件、E1/R1/T3–T4、质检与最终报告格式。
- 不将性能退化、体验瑕疵等「非缺陷」纳入 2d 扫描目标。
- v1 只改 `SKILL.md`（及必要时 `plugin.json` 版本/描述）；不新增 `agents/*.md`。

---

## 已确认决策（brainstorming）

| 项 | 选择 |
|----|------|
| 优化类 taxonomy | **轻量 C**：新增 `optimization` + 固定子标签 |
| 2d 触发 | **方案 B**：独立字段 `residue_scan`，与变更性质标签解耦 |
| bugfix 与 2d | 典型 bugfix 默认 `residue_scan=yes`；单点无泛化模式可标 `no` 并说明 |
| optimization 与 2d | **不**因含 `optimization` 自动触发；由 `residue_scan` 决定 |
| 复合标签 | 允许（如 `bugfix` + `optimization/correctness`） |

---

## 变更性质 taxonomy

### 顶层类型（保留 + 扩展）

| 标签 | 含义 |
|------|------|
| `bugfix` | 修复已知错误行为、崩溃、数据错误、安全漏洞等 |
| `feature` | 新增能力、API、配置项、用户可见功能 |
| `refactor` | 结构调整、重命名、提取函数；**对外行为声称不变** |
| `test` | 测试代码变更（若可审 diff 中仍有生产代码，可与其它标签复合） |
| `docs` | 文档变更（可审 diff 通常已在阶段 0 排除） |
| `optimization` | 改进类变更；**须**带子标签（见下表） |
| `other` | 无法归入以上任一类型的兜底；**不得**与 `optimization` 同时使用 |

### `optimization` 子标签（必选其一）

| 子标签 | 含义 | 典型示例 |
|--------|------|----------|
| `optimization/correctness` | 正确性 / 安全性 / 健壮性改进，未明确称为 bug | 补输入校验、防御性 nil 检查、修错误默认值 |
| `optimization/performance` | 性能、资源占用 | 缓存、批处理、减少分配 |
| `optimization/ux` | 体验、文案、交互、可观测性（非缺陷） | 错误提示更清晰、日志更易读、CLI 输出格式 |
| `optimization/consistency` | 与兄弟实现或项目约定对齐，**行为声称不变** | 统一错误处理风格、对齐命名约定 |
| `optimization/workflow` | 开发 / 运维 / 发布流程改进 | CI 步骤、脚本、内部工具链 |

### 复合标签规则

- 阶段 1 可输出**多个**顶层/子标签，用列表表示（见输出格式）。
- 常见复合：
  - `bugfix` + `optimization/correctness`（修复且改进表述）
  - `feature` + `optimization/ux`
  - `refactor` + `optimization/consistency`
- `optimization` 出现时**必须**带且仅带**一个**子标签。
- 判定以**可审 diff 实际行为**为准，不以 PR 标题用词为准。

---

## `residue_scan` 字段

### 定义

阶段 1 新增必填字段：

```markdown
- 残留扫描（residue_scan）：yes | no
- 残留扫描判定依据：（一句话；no 时说明为何无泛化模式）
```

**语义：** 本次变更是否修复（或引入防护针对）一种**可能在仓库其他生产代码位置以相同根因复现的缺陷模式**，从而需要 2d 做全仓同类残留审查。

### `residue_scan: yes` 判定启发式

满足以下**任一**且 diff 体现具体代码模式修复 → `yes`：

1. 缺失的条件判断、分支、边界处理被补上
2. 缺失或错误的错误处理、资源清理、rollback 被补上
3. API / 库 / 框架误用方式被纠正
4. 错误的默认值、配置解析、schema 处理被修正
5. 状态机 / enum / mode 分支遗漏被补上
6. nil / 空值 / 越界 / 生命周期 / 并发保护缺失被补上
7. 权限、认证、校验遗漏被补上

**与 `bugfix` 的关系：** 以上模式若存在，无论 PR 自称 bugfix 还是 optimization，均应 `residue_scan=yes`。

### `residue_scan: no` 判定启发式

以下情况 → `no`（2d 不委派）：

1. 纯文案、注释、日志措辞（无行为变化）
2. 纯性能优化且不改变正确性语义
3. 纯重构 / 一致性调整，未触及上述缺陷模式
4. 单点笔误、单一配置项、单一常量修正，**无可泛化的搜索模式**（须在判定依据中说明）
5. 新增 feature 的主路径实现，非「修复既有错误模式」

### 边界：不确定时

- 优先结合 diff：若已出现可描述的「修复前模式 → 修复后模式」，倾向 `yes`。
- 若证据不足，标 `yes` 并在「不确定信息」注明；**不得**因 PR 标题含「优化」默认 `no`。

---

## 2d 触发规则（替代「仅 bugfix」）

### 新规则

| `residue_scan` | 并行 Task 数 | 2d |
|----------------|-------------|-----|
| `yes` | 4（2a / 2b / 2c / 2d） | 委派 |
| `no` | 3（2a / 2b / 2c） | 不委派 |

**主编排**在阶段 2 委派前读取阶段 1 的 `residue_scan`，**不再**以「变更性质是否含 bugfix」作为 2d 唯一条件。

### 与现网行为对比

| 场景 | 现网 | 新规则 |
|------|------|--------|
| 典型 bugfix（nil panic） | 4 Task | 4 Task（`residue_scan=yes`） |
| 优化补校验 | 可能 3 Task（若未标 bugfix） | 4 Task（`optimization/correctness` + `residue_scan=yes`） |
| 优化文案 | 3 Task | 3 Task（`optimization/ux` + `residue_scan=no`） |
| 单点 typo 修常量 | 4 Task（若标 bugfix） | 3 Task（可 `bugfix` + `residue_scan=no`） |

### 2d 职责（不变）

- 仅输出缺陷性质第 3 类：仓库中其他代码的同类残留缺陷。
- 不得将性能改进点、体验建议、风格不一致作为 2d finding。
- 触发条件从「bugfix」改为「residue_scan=yes」；2d 内部流程与覆盖说明门禁不变。

---

## 阶段 1 输出格式（更新）

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

### 阶段 1 限制（更新）

- 不得因「变更简单」而暗示 2b/2c/2d 可跳过；是否 skip 由阶段 2 各 agent 在覆盖说明中论证。
- 不得暗示非 `residue_scan=yes` 变更可由 2b 代做全仓同类残留扫描（残留属 2d，仅 `residue_scan=yes` 委派）。
- 不得将 `residue_scan` 默认绑死为「含 bugfix → yes、不含 → no」；须按本节启发式独立判定。
- 其余限制（可审 diff、排除路径等）不变。

---

## 阶段 2 编排变更摘要

需同步替换 `SKILL.md` 中所有「仅 bugfix 委派 2d」表述为「`residue_scan=yes` 委派 2d」，包括但不限于：

1. 文首流程概述（第 5 行）
2. `# 2. 代码缺陷扫描` 目标段
3. `阶段 2 并行委派` HARD-GATE 与 Task 数量规则
4. `委派前准备` 步骤 1
5. `阶段 2 委派自检` checklist
6. 子阶段表「委派条件」列（2d：仅 `residue_scan=yes`）
7. `2d — 同类残留审查` 触发段
8. 主编排合并「未委派 2d」门禁说明
9. 阶段 1 限制中关于 2d 的交叉引用

**不变：** 2a/2b/2c 始终并行；同一轮 assistant 回复内一次性发起全部 Task；禁止串行等待。

---

## 示例对照表

| PR 描述 | 变更性质 | residue_scan | 2d |
|---------|----------|--------------|-----|
| Fix nil deref in handler | `bugfix` | yes | ✅ |
| 优化：补充 API 入参校验 | `optimization/correctness` | yes | ✅ |
| 优化错误提示文案 | `optimization/ux` | no | ❌ |
| 加缓存提升吞吐 | `optimization/performance` | no | ❌ |
| 统一三处错误处理风格 | `optimization/consistency` | no | ❌ |
| 修 CI 脚本超时 | `optimization/workflow` | no | ❌ |
| 修错单个默认常量，无同类写法 | `bugfix` | no（判定依据：单点常量，无可泛化模式） | ❌ |
| 新 API + 更友好的帮助文本 | `feature`, `optimization/ux` | no | ❌ |

---

## 阶段 4 报告

「代码变更背景」一节可引用阶段 1 的变更性质列表与 `residue_scan` 判定依据（一句话）；**不**在最终报告正文中展开 2d 扫描过程细节。

`REVIEW_RESULT` 规则不变。

---

## 实施范围

| 文件 | 变更 |
|------|------|
| `plugins/audit/skills/review/SKILL.md` | taxonomy、residue_scan、2d 触发全文替换 |
| `plugins/audit/.claude-plugin/plugin.json` | 版本号 bump（若发布） |

---

## 风险与缓解

| 风险 | 缓解 |
|------|------|
| 阶段 1 误标 `residue_scan=no` 导致漏扫 | 启发式写清；不确定倾向 yes；判定依据必填 |
| 阶段 1 过度标 yes 增加 token | 2d 内部仍有「同根因」核实门禁；非缺陷不输出 |
| `optimization` 子标签选错 | 子标签仅影响报告描述，不单独决定 2d |

---

## 验收标准

1. `SKILL.md` 中不再存在「仅 bugfix 委派 2d」作为唯一触发条件。
2. 阶段 1 输出模板含 `residue_scan` 与判定依据。
3. 阶段 2 委派规则明确：`residue_scan=yes` → 4 Task，否则 3 Task。
4. 示例 PR「优化补校验」在文档中明确应触发 2d。
5. 2d 职责与 finding 性质第 3 类定义未变。
