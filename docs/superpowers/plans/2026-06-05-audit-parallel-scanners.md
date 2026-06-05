# Audit 阶段 2 并行 Scanner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `audit` skill 阶段 2 从单一「主审 agent」拆为 **2a/2b/2c 三 agent 并行**扫描，主编排合并候选缺陷并做覆盖说明门禁，以降低漏报；阶段 3 质检追加防误删规则。

**Architecture:** 仅改 `plugins/audit/skills/review/SKILL.md` 与 `plugin.json`。原 §2 的缺陷成立条件、候选格式、反证检查等提升为阶段 2 **共享规则**；三个 specialist 小节各含 checklist、Read 预算、输出模板与 Task 委派说明；主编排在三份返回后合并（不委派 merger）。通信仍为 Markdown 粘贴，无 JSON/脚本。

**Tech Stack:** Markdown skill 定义、`plugin.json`、`rg` 结构验收、人工试跑。

**设计依据:** `docs/superpowers/specs/2026-06-05-audit-parallel-scanners-design.md`

---

## 文件映射

| 文件 | 职责 |
|------|------|
| `plugins/audit/skills/review/SKILL.md` | 流程、阶段 2 拆分、主编排合并、阶段 3 增量规则 |
| `plugins/audit/.claude-plugin/plugin.json` | version `0.7.0`、description |
| `docs/superpowers/specs/2026-06-05-audit-parallel-scanners-design.md` | 完成后将「状态」改为「已实施」 |

---

### Task 0: 实施前阅读

**Files:**
- Read: `docs/superpowers/specs/2026-06-05-audit-parallel-scanners-design.md`
- Read: `plugins/audit/skills/review/SKILL.md`（全文）
- Read: `plugins/investigate-issue/skills/investigate/SKILL.md`（`### 阶段2：并行分析` 委派写法）

- [ ] **Step 1:** 确认 v1 不创建 `plugins/audit/agents/*.md`
- [ ] **Step 2:** 在 `SKILL.md` 标记替换区间：行 5–6（开篇）、74–81（总体流程）、131–174（旧阶段 2 目标/必须阅读/审计重点）、288–324（阶段 3）

---

### Task 1: 更新开篇与总体流程

**Files:**
- Modify: `plugins/audit/skills/review/SKILL.md:5-6`
- Modify: `plugins/audit/skills/review/SKILL.md:74-81`

- [ ] **Step 1: 改主编排角色句**

将第 5 行：

```markdown
你是本次审计的**主编排者**。接收用户输入，顺序委派阶段 1、2、3 的 agent，最后由你执行阶段 4 报告拼装并输出最终报告。禁止修改被审仓库代码；禁止运行测试。
```

替换为：

```markdown
你是本次审计的**主编排者**。接收用户输入，委派阶段 1；**并行**委派阶段 2 的 2a/2b/2c 三个 specialist agent，由你合并候选缺陷并做覆盖说明门禁；再委派阶段 3 质检；最后由你执行阶段 4 报告拼装并输出最终报告。禁止修改被审仓库代码；禁止运行测试。
```

- [ ] **Step 2: 改总体流程图**

将 `## 总体流程` 内 code block 替换为：

```text
1. 变更意图分析
2. 代码缺陷扫描（并行 2a / 2b / 2c → 主编排合并）
3. 缺陷质检
4. 报告拼装
```

- [ ] **Step 3: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "refactor(audit): describe parallel stage-2 scanners in overview"
```

---

### Task 2: 重写阶段 2 — 共享规则 + 删除旧 9 维单 agent 段

**Files:**
- Modify: `plugins/audit/skills/review/SKILL.md`（`# 2. 代码缺陷扫描` 至 `# 3. 质检` 之前）

- [ ] **Step 1: 替换阶段 2 开篇（删除旧「目标 / 必须阅读 / 审计重点」）**

在 `# 2. 代码缺陷扫描` 下，**删除**原：

- `## 目标`（单 agent 委派那段）
- `## 必须阅读`
- `## 审计重点`（9 条列表）

**插入**以下新开篇（紧接 `# 2. 代码缺陷扫描` 标题后）：

```markdown
## 目标

**并行**委派三个 specialist sub-agent（2a / 2b / 2c），输入均为：（1）diff 原文；（2）阶段 1「变更意图分析」Markdown 全文；（3）本节下方「共享规则」全文（缺陷成立条件、候选格式等）。

三 agent 返回后，由**主编排**合并候选缺陷、执行覆盖说明门禁，将合并结果交给阶段 3。主编排在本节**不得**以证据不足删除候选（交给质检）。

每次委派 sub-agent 时，prompt **必须**包含：
- 本 agent 职责与 checklist（见 2a/2b/2c）
- diff 原文 + 阶段 1 输出全文
- 下方「共享规则」全文
- 输出格式（含必填「扫描覆盖说明」）

## 并行委派

使用 `Task` **同时**发起三个 sub-agent（单条消息内三次 Task 调用）：

| 子阶段 | 角色名（description） | 职责摘要 |
|--------|----------------------|----------|
| **2a** | 变更代码本身审查 | 语言缺陷、安全、边界条件 |
| **2b** | 变更周边影响审查 | 上下游调用链、兄弟对比、bugfix 残留 |
| **2c** | 目的与兼容性审查 | 意图是否实现、升级兼容性 |

## 共享规则

以下规则对 2a/2b/2c **均适用**（保留现有条文，自本 plan 实施起置于阶段 2 内，位于 2a 小节之前）。
```

- [ ] **Step 2: 保留并确认共享规则块顺序**

确保下列现有小节**原样保留**在「## 共享规则」之后、`#### 2a` 之前（仅标题层级可改为 `## 缺陷成立条件` 等，内容不变）：

- `## 缺陷成立条件`
- `## 缺陷性质`
- `## 缺陷等级`
- `## 候选缺陷输出格式`
- `## 字段要求`（含反证检查）
- 阶段 2 内原 `---` 分隔若影响阅读可保留一处

- [ ] **Step 3: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "refactor(audit): stage 2 shared rules and parallel overview"
```

---

### Task 3: 插入 2a / 2b / 2c specialist 小节

**Files:**
- Modify: `plugins/audit/skills/review/SKILL.md`（插在「字段要求」之后、`# 3. 质检` 之前）

- [ ] **Step 1: 插入 `#### 2a`**

```markdown
#### 2a — 变更代码本身审查

sub-agent 扮演**变更代码本身审查员**。

**聚焦：** 变更 hunk 及**所在函数的完整实现**（必须 Read 含变更的完整函数体；禁止只看 diff 片段）。

**必扫 checklist（须全部写入「扫描覆盖说明」勾选）：**

- 语言/运行时：panic/recover、nil、zero/default 误用、OOM 风险、资源泄漏、并发竞态、错误处理遗漏
- 安全：认证/授权、输入校验、敏感信息、注入（SQL/命令/路径）、路径遍历、越权
- 边界：nil/empty/zero/default、重复/缺失/非法值、超时/重试、并发、部分失败

**不做：** 全仓上游入口追踪（2b）；PR 叙述是否达成（2c）。

**Read 预算：** Read ≤35；Grep ≤12；Glob ≤8。

**输出：** 使用下方「统一输出格式」；候选缺陷 ID 前缀 `2a-`（如 `### 候选缺陷 2a-1：标题`）。
```

- [ ] **Step 2: 插入 `#### 2b`**

```markdown
#### 2b — 变更周边影响审查

sub-agent 扮演**变更周边影响审查员**。

**聚焦：** 以变更符号为锚的调用链与同类对比。

**必扫 checklist：**

- 上游：从可达入口到变更点；调用方参数/状态/错误处理/并发语义是否仍成立
- 下游：从变更点到关键下游；新参数/状态/错误值是否破坏下游假设
- 兄弟/同类：同文件、同包、同模式实现对比
- 残留：**仅当**阶段 1「变更性质」含 **bugfix** 时，Grep 同根因/同模式残留

**不做：** 变更函数内纯局部问题（2a），除非由链路透传导致。

**Read 预算：** Read ≤40；Grep ≤15。

**输出：** 统一输出格式；ID 前缀 `2b-`。
```

- [ ] **Step 3: 插入 `#### 2c`**

```markdown
#### 2c — 目的与兼容性审查

sub-agent 扮演**目的与兼容性审查员**。

**聚焦：** commit/PR **声称** vs **实现**；对外契约与升级路径。

**必扫 checklist：**

- 意图：对照 commit message、PR 标题/描述、comments——是否修好、是否只修部分路径、修复逻辑是否不可达
- 兼容性：API 签名/行为、配置项、schema/CRD、默认值、数据迁移、滚动升级、回滚

**不做：** 全仓调用链深挖（2b）；泛化语言层扫描（2a）。

**Read 预算：** Read ≤30；Grep ≤10。

**输出：** 统一输出格式；ID 前缀 `2c-`。
```

- [ ] **Step 4: 插入「统一输出格式」**

在三小节之后、`### 主编排合并` 之前插入：

```markdown
### 三 agent 统一输出格式

```markdown
## 候选缺陷列表

### 候选缺陷 2a-1：标题

- 缺陷的性质：
- 缺陷等级：
- 相关代码证据：
- 缺陷的触发条件：
- 代码缺陷解读：
- 造成的代码后果和业务功能后果：
- 反证检查：
- 建议解决方案：

（若无缺陷：写「本 agent 范围内未发现满足成立条件的候选缺陷。」）

## 扫描覆盖说明

- 已检查的变更文件：
- 已覆盖的维度：（逐项勾选，与本 agent checklist 一致）
- 未深入的原因：（无则写「无」）
- 结论：（一句总结）
```

（注：实施时外层 markdown _fence 按 SKILL 现有风格处理，避免嵌套 fence 冲突——可将内层模板改为缩进代码块或单层 fence。）
```

**实施提示：** 若嵌套 fence 有问题，将内层改为：

```markdown
### 三 agent 统一输出格式

各 agent 必须返回两节：`## 候选缺陷列表`（可无条目标题下说明零缺陷）与 **`## 扫描覆盖说明`（必填）**。候选缺陷字段与「候选缺陷输出格式」一致；标题形如 `### 候选缺陷 2b-1：…`。
```

- [ ] **Step 5: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): add 2a/2b/2c specialist scanner sections"
```

---

### Task 4: 主编排合并与覆盖门禁

**Files:**
- Modify: `plugins/audit/skills/review/SKILL.md`（紧接「三 agent 统一输出格式」之后、`# 3. 质检` 之前）

- [ ] **Step 1: 插入主编排小节**

```markdown
### 主编排合并（不委派）

三份 agent 输出收齐后，**主编排**执行：

1. **收集**：保留来源前缀 `2a-` / `2b-` / `2c-` 直至合并完成。
2. **合并去重**：
   - 相同根因 + 相同落点 → 合并为一条，保留最全证据；
   - 不同根因（如 2a 局部 nil 与 2b 上游未校验）→ **保留多条**；
   - **禁止**以「可能性低」或证据不足删除（交给阶段 3）。
3. **覆盖说明门禁**：任一份「扫描覆盖说明」中 checklist 项标为未检查，且无合理 skip（如纯 `docs` 变更跳过上下游、纯格式化）→ 主编排须 **轻量补查** 或 **再委派该 agent 一次**（附 diff、阶段 1 输出、指出漏项）。
4. **重编号**：合并后改为连续序号 `### 候选缺陷 1` … 供阶段 3 使用。
5. **交给阶段 3**：粘贴合并后的完整「候选缺陷列表」Markdown（可不附三份原始覆盖说明，但主编排须已处理门禁）。

**合理 skip 示例（须在覆盖说明写明）：** 纯 `docs`/`*.md`；纯注释/格式化无行为变化。
```

- [ ] **Step 2: 更新阶段 1 限制（可选一句）**

在 `# 1. 变更意图分析` 的 `## 限制` 末尾追加一句：

```markdown
- 不得因「变更简单」而暗示 2b/2c 可跳过；是否 skip 由阶段 2 各 agent 在覆盖说明中论证。
```

- [ ] **Step 3: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): orchestrator merge and coverage gate for stage 2"
```

---

### Task 5: 阶段 3 质检增量规则

**Files:**
- Modify: `plugins/audit/skills/review/SKILL.md`（`# 3. 质检` 的 `## 检查内容` 或 `处理规则` 之后）

- [ ] **Step 1: 追加防误删三条**

在阶段 3「处理规则」列表**之后**增加：

```markdown
**防漏报（合并后质检）：**

- 仅当反证后**证据不足**才可删除；**不得**因「2a/2b/2c 中其他 agent 未报同一问题」而删除。
- 描述模糊但成立 → **补充**证据与触发条件，改成确定性表述；**禁止**仅润色后删除。
- 不重新全量审计；允许对单条候选 **Read 锚点函数** 核实反证（建议 ≤10 Read/条）。
```

- [ ] **Step 2: 更新阶段 3 目标首句**

将：

```markdown
委派一个独立的 agent，输入为阶段 2 输出的全部候选缺陷 markdown。
```

改为：

```markdown
委派一个独立的 agent，输入为阶段 2 **主编排合并后**的全部候选缺陷 markdown。
```

- [ ] **Step 3: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "refactor(audit): QC rules to avoid false negatives after merge"
```

---

### Task 6: 更新 plugin.json

**Files:**
- Modify: `plugins/audit/.claude-plugin/plugin.json`

- [ ] **Step 1: bump version 与 description**

```json
{
  "name": "audit",
  "displayName": "Audit",
  "version": "0.7.0",
  "description": "对 PR/commit/diff 做缺陷审计；阶段2 三维度并行扫描（代码本身/周边影响/目的兼容），主编排合并后质检",
  "keywords": ["code-review", "pr-review", "audit"],
  "license": "MIT"
}
```

- [ ] **Step 2: Commit**

```bash
git add plugins/audit/.claude-plugin/plugin.json
git commit -m "chore(audit): bump to 0.7.0 for parallel stage-2 scanners"
```

---

### Task 7: 结构验收与 spec 状态

**Files:**
- Modify: `docs/superpowers/specs/2026-06-05-audit-parallel-scanners-design.md`（文首状态）

- [ ] **Step 1: rg 门禁**

```bash
cd /Users/weizhoulan/Documents/git/blueskills
rg -q '并行' plugins/audit/skills/review/SKILL.md
rg -q '2a — 变更代码本身审查' plugins/audit/skills/review/SKILL.md
rg -q '2b — 变更周边影响审查' plugins/audit/skills/review/SKILL.md
rg -q '2c — 目的与兼容性审查' plugins/audit/skills/review/SKILL.md
rg -q '扫描覆盖说明' plugins/audit/skills/review/SKILL.md
rg -q '主编排合并' plugins/audit/skills/review/SKILL.md
rg -q '不得.*其他 agent 未报' plugins/audit/skills/review/SKILL.md
rg -q '编程语言缺陷' plugins/audit/skills/review/SKILL.md && echo 'FAIL: old 9-dim list may remain' && exit 1 || true
```

**注意：** 最后一行意图是确认旧「审计重点」9 条列表已删除；若 `rg` 仍命中「编程语言缺陷」仅在 2a checklist 中，应改为：

```bash
! rg -q '^[0-9]+\. 编程语言缺陷' plugins/audit/skills/review/SKILL.md
```

Expected: 无 `1. 编程语言缺陷` 式旧枚举列表。

- [ ] **Step 2: 更新 spec 状态**

将 `docs/superpowers/specs/2026-06-05-audit-parallel-scanners-design.md` 第 4 行 `**状态：** 待实施` 改为 `**状态：** 已实施`。

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-06-05-audit-parallel-scanners-design.md
git commit -m "docs(audit): mark parallel-scanners spec as implemented"
```

---

### Task 8: 人工试跑（验收）

**Files:** 无代码变更；在被审仓库或本仓库任选一小段真实 diff/PR。

- [ ] **Step 1:** 在目标仓库根目录触发 `/audit:review`（或等价 skill 调用），输入含已知缺陷的 PR 或本地 diff。
- [ ] **Step 2:** 确认日志/对话中出现 **三次并行** Task（2a/2b/2c）。
- [ ] **Step 3:** 确认三份输出均含 `## 扫描覆盖说明` 且 checklist 已勾选。
- [ ] **Step 4:** 确认主编排合并后进入质检，终稿含 `REVIEW_RESULT=` 且缺陷条目不弱于合并前应有项。

- [ ] **Step 5:** 在 spec「完成标准」小节将 checkbox 勾为 `[x]`（若实施者试跑通过）。

---

## Plan 自检（对照 spec）

| Spec 要求 | 对应 Task |
|-----------|-----------|
| 三 agent 并行 | Task 1–3 |
| 扫描覆盖说明必填 | Task 3–4 |
| 主编排合并、不裁证据 | Task 4 |
| 质检防误删三条 | Task 5 |
| plugin.json 0.7.0 | Task 6 |
| 手工试跑 | Task 8 |

无 TBD；未创建 `agents/*.md`（符合 v1 非目标）。
