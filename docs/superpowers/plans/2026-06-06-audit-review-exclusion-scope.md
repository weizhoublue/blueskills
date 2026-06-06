# audit/review 审计范围排除实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `audit/review` SKILL 中落地审计范围排除：主编排预处理 diff，全环节忽略 vendor/依赖、测试（`*_test.go` + e2e 目录）、`docs/` 变更；全排除时快速结束。

**Architecture:** 仅改 `plugins/audit/skills/review/SKILL.md` 与 `plugin.json`。在「输入」后新增 HARD-GATE 排除表与阶段 0 预处理；阶段 1～4 及共享规则统一引用「可审 diff」；2b/2d 补充 Grep/清单 skip 条文。

**Tech Stack:** Markdown skill；`rg` 结构校验；无 pytest。

**Reference:** [`docs/superpowers/specs/2026-06-06-audit-review-exclusion-scope-design.md`](../specs/2026-06-06-audit-review-exclusion-scope-design.md)

---

## 文件结构

| 路径 | 改动 | Task |
|------|------|------|
| `plugins/audit/skills/review/SKILL.md` | 排除规则、阶段 0、各阶段约束 | 1–5 |
| `plugins/audit/.claude-plugin/plugin.json` | 版本 + description | 6 |
| `docs/superpowers/specs/2026-06-06-audit-review-exclusion-scope-design.md` | 状态 → 已实施 | 6 |

---

## Task 1: 全局排除规则 + 阶段 0 预处理

**Files:**

- Modify: `plugins/audit/skills/review/SKILL.md`（L5 主编排开场白；L72 后插入新章；L74–81 更新流程图）

- [ ] **Step 1: 更新主编排开场白（L5）**

将首段：

```markdown
你是本次审计的**主编排者**。接收用户输入，委派阶段 1；**并行**委派阶段 2 的 2a/2b/2c 三个 specialist agent
```

改为：

```markdown
你是本次审计的**主编排者**。接收用户输入后**先执行阶段 0 变更预处理**；若无可审生产代码变更则快速结束；否则委派阶段 1；**并行**委派阶段 2 的 2a/2b/2c 三个 specialist agent
```

- [ ] **Step 2: 在 `## 输入` 章节结束（L70 后 `---` 之前）与 `## 总体流程` 之间插入以下全文**

```markdown
---

## 审计范围排除（HARD-GATE）

以下路径的变更**不纳入审计**，全环节（阶段 0～4）均不得分析、不得作为缺陷证据、不得在 Grep/Read 中采信。

| 类别 | 路径规则 |
|------|----------|
| 依赖 | `vendor/**`、`node_modules/**`、`third_party/**` |
| 测试 | `**/*_test.go`、`e2e/**`、`test/e2e/**`、`tests/e2e/**` |
| 文档 | `docs/**` |

**匹配语义：**

- 以 diff 中的文件路径为准（正斜杠，相对仓库根）
- 任一规则命中 → **整文件排除**，不拆 hunk
- **不在排除范围内：** 通用 `test/`、`tests/`、`__tests__/`、`spec/`（非 e2e 子路径）；根目录 `README.md` 等非 `docs/` 文档

---

# 0. 变更预处理（主编排，不委派）

## 目标

读取完整 diff 后，按「审计范围排除」剥离不可审 hunks，生成**可审 diff**；统计排除摘要供编排上下文使用。

## 步骤

```text
1. 读取 changed files 列表与完整 diff
2. 按排除规则分为「可审」与「已排除」
3. 从 diff 中移除已排除文件的 hunks → 生成「可审 diff」
4. 可审文件列表为空 → 快速结束（不委派阶段 1/2/3，直接输出最终报告）
5. 否则 → 将「可审 diff」+「变更预处理摘要」传入阶段 1 及后续流程
```

## 变更预处理摘要（编排上下文，不进入最终报告正文）

```markdown
## 变更预处理摘要
- 可审文件数：N
- 已排除文件数：M
- 已排除路径（按类别）：
  - 依赖：…（共 x 个文件）
  - 测试：…（共 y 个文件）
  - 文档：…（共 z 个文件）
```

## 快速结束（可审文件数 = 0）

不委派任何 sub-agent，主编排**直接**输出以下最终报告（仅此内容）：

```markdown
## 代码变更背景

本次变更仅涉及依赖目录（vendor/node_modules/third_party）、测试代码（*_test.go / e2e 目录）或文档（docs/），无生产代码变更纳入审计范围。

## 缺陷

未发现满足审计范围条件的代码缺陷（已排除依赖、测试与文档变更，不在审查范围内）。

## 最终结论

REVIEW_RESULT=review_mark_ignore
```

## 混合 PR

- 阶段 1～4 仅使用「可审 diff」，不得使用原始 diff
- 阶段 1「涉及的主要文件」只列可审文件

---
```

- [ ] **Step 3: 更新 `## 总体流程` 代码块**

将：

```text
1. 变更意图分析
2. 代码缺陷扫描（并行 2a / 2b / 2c [+ 条件 2d] → 主编排合并）
3. 缺陷质检
4. 报告拼装
```

改为：

```text
0. 变更预处理（主编排；全排除时可快速结束）
1. 变更意图分析
2. 代码缺陷扫描（并行 2a / 2b / 2c [+ 条件 2d] → 主编排合并）
3. 缺陷质检
4. 报告拼装
```

- [ ] **Step 4: 校验**

```bash
rg -n '审计范围排除|变更预处理|可审 diff|vendor/\*\*|node_modules/\*\*|third_party/\*\*|\*_test\.go|快速结束' plugins/audit/skills/review/SKILL.md
```

Expected: ≥8 行匹配

- [ ] **Step 5: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): add exclusion rules and stage-0 diff preprocessing"
```

---

## Task 2: 阶段 1 输入约束

**Files:**

- Modify: `plugins/audit/skills/review/SKILL.md`（`# 1. 变更意图分析` 小节）

- [ ] **Step 1: 更新阶段 1「目标」段落（约 L89）**

将：

```markdown
委派一个独立的 agent，输入为本次代码变更的 diff 及 PR 元数据（标题、描述、comments 等）。
```

改为：

```markdown
委派一个独立的 agent，输入为阶段 0 生成的**可审 diff**（非原始 diff）及 PR 元数据（标题、描述、comments 等）。附「变更预处理摘要」（只读）。
```

- [ ] **Step 2: 在阶段 1「限制」小节（约 L127）末尾追加**

```markdown
- 「涉及的主要文件」只列可审文件，不得包含已排除路径。
- 变更性质以可审 diff 内容为准；不得因 PR 标题/描述提及 docs/vendor/test 而扩展审计范围。
- 不得从已排除文件的变更推断缺陷或审计范围。
```

- [ ] **Step 3: 校验**

```bash
rg -n '可审 diff|不得从已排除' plugins/audit/skills/review/SKILL.md | head -20
```

Expected: 阶段 1 相关行 ≥3

- [ ] **Step 4: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): constrain stage-1 to reviewable diff only"
```

---

## Task 3: 阶段 2 共享规则 + 委派输入 + 2b/2d

**Files:**

- Modify: `plugins/audit/skills/review/SKILL.md`（`# 2. 代码缺陷扫描`、共享规则、2b、2d）

- [ ] **Step 1: 更新阶段 2「目标」中 agent 输入（约 L139）**

将：

```markdown
各 agent 输入均为：（1）diff 原文；（2）阶段 1「变更意图分析」Markdown 全文；（3）本节下方「共享规则」全文（缺陷成立条件、候选格式等）。
```

改为：

```markdown
各 agent 输入均为：（1）阶段 0 生成的**可审 diff**（非原始 diff）；（2）阶段 1「变更意图分析」Markdown 全文；（3）本节下方「共享规则」全文（缺陷成立条件、候选格式等）；（4）「变更预处理摘要」（只读）。
```

- [ ] **Step 2: 更新 prompt 组装清单（约 L146）**

将 `diff 原文` 改为 `可审 diff`。

- [ ] **Step 3: 更新委派前准备与共享输入（约 L174）**

将 `组装共享 prompt 块（diff、阶段 1、共享规则）` 改为 `组装共享 prompt 块（可审 diff、阶段 1、共享规则、变更预处理摘要）`。

- [ ] **Step 4: 在 `## 共享规则` 下、`## 缺陷成立条件` 之前插入**

```markdown
## 审计范围（HARD-GATE）

- 传入的 diff 已由主编排按「审计范围排除」预处理；所列文件均在审计范围内。
- 编排上下文中的「已排除路径」**不得**作为缺陷证据、扫描锚点或 Grep 采信结果。
- Grep/Read 时**不得**深入已排除路径（2b 上下游、2d 全仓 Grep 均适用）。

---
```

- [ ] **Step 5: 在 2b「阶段 A」锚点提取后（约 L371 后）追加一条**

```markdown
4. **排除路径**：从 diff 列出的锚点若在「审计范围排除」表内 → 不应出现（可审 diff 已剥离）；若 Grep 发现 caller/callee 落在排除路径内，清单行注明 `已排除（测试/依赖/文档），不核实`，不计入「应扫未扫」。
```

- [ ] **Step 6: 在 2d「阶段 A」第 3 步 Grep 说明处（约 L435 后）改为**

```markdown
3. 全工程 `Grep`，**默认排除** `vendor/`、`node_modules/`、`third_party/`、`**/*_test.go`、`e2e/`、`test/e2e/`、`tests/e2e/`、`docs/`；命中排除路径的匹配**不进入**残留候选清单。在「扫描覆盖说明」中必填 **同类残留候选清单**（去重）：
```

- [ ] **Step 7: 替换主编排合并处「合理 skip 示例」（约 L500）**

将：

```markdown
**合理 skip 示例（须在覆盖说明写明）：** 纯 `docs`/`*.md`；纯注释/格式化无行为变化。
```

改为：

```markdown
**合理 skip 示例（须在覆盖说明写明）：** 纯注释/格式化无行为变化（`docs/`、测试、依赖类路径已在阶段 0 剥离，不会出现在可审 diff 中）。
```

- [ ] **Step 8: 校验**

```bash
rg -n '审计范围（HARD-GATE）|可审 diff|已排除（测试/依赖/文档）|默认排除' plugins/audit/skills/review/SKILL.md
```

Expected: ≥5 行匹配

- [ ] **Step 9: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): apply exclusion rules to stage-2 scanners and merge gate"
```

---

## Task 4: 阶段 3、阶段 4 与执行约束

**Files:**

- Modify: `plugins/audit/skills/review/SKILL.md`（`# 3. 质检`、`# 4. 报告拼装`、`# 执行约束`）

- [ ] **Step 1: 在阶段 3「检查内容」之前插入**

```markdown
## 审计范围防御

- 候选缺陷的代码证据若落在「审计范围排除」路径内 → **删除**（不应出现，防御性规则）。
- 不重新审计已排除文件。
```

- [ ] **Step 2: 在阶段 4「处理规则」列表追加**

```markdown
- 混合 PR 时，「代码变更背景」可一句说明：「已排除 N 个依赖/测试/文档文件，未纳入本次审计」（N 取自变更预处理摘要）。
- 全排除场景已在阶段 0 快速结束，不进入本阶段。
```

- [ ] **Step 3: 在 `# 执行约束` 列表追加两条（约 L663 后）**

```markdown
16. 阶段 0 必须先于阶段 1；全排除变更不得委派阶段 1/2/3。
17. 阶段 1～4 及委派 prompt 必须使用可审 diff，不得将 vendor/node_modules/third_party、测试排除路径、docs/ 内变更纳入审计。
```

- [ ] **Step 4: 校验**

```bash
rg -n '审计范围防御|阶段 0 必须先于|必须使用可审 diff' plugins/audit/skills/review/SKILL.md
```

Expected: 3 行匹配

- [ ] **Step 5: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): extend exclusion rules to QC, report, and execution constraints"
```

---

## Task 5: 终验清单（人工对照 spec 验收标准）

**Files:**

- Verify: `plugins/audit/skills/review/SKILL.md`

- [ ] **Step 1: 运行结构校验**

```bash
rg -c '审计范围排除' plugins/audit/skills/review/SKILL.md
rg -c '可审 diff' plugins/audit/skills/review/SKILL.md
rg -c 'REVIEW_RESULT=review_mark_ignore' plugins/audit/skills/review/SKILL.md
rg -c 'vendor/\*\*' plugins/audit/skills/review/SKILL.md
rg -c '\*_test\.go' plugins/audit/skills/review/SKILL.md
rg -c '快速结束' plugins/audit/skills/review/SKILL.md
```

Expected: 每项 count ≥ 1

- [ ] **Step 2: 确认无残留「diff 原文」在阶段 2 输入语境（应已改为可审 diff）**

```bash
rg -n 'diff 原文' plugins/audit/skills/review/SKILL.md || echo "OK: no stale diff 原文"
```

Expected: 无匹配，或仅出现在历史说明性文字中（若有则改为「可审 diff」）

- [ ] **Step 3: 通读 spec 验收标准 5 条，在本地勾选**

对照 [`2026-06-06-audit-review-exclusion-scope-design.md`](../specs/2026-06-06-audit-review-exclusion-scope-design.md) 第五节，确认 SKILL 均已覆盖。

---

## Task 6: plugin.json 与 spec 状态

**Files:**

- Modify: `plugins/audit/.claude-plugin/plugin.json`
- Modify: `docs/superpowers/specs/2026-06-06-audit-review-exclusion-scope-design.md`

- [ ] **Step 1: 更新 plugin.json**

将 `version` 从 `0.9.1`  bump 为 `0.9.2`。

将 `description` 末尾增补（保留原有 T1–T3 等描述）：

```text
；预处理排除 vendor/依赖、*_test.go/e2e、docs/ 变更
```

- [ ] **Step 2: 更新 spec 状态**

将 `**状态：** 待实施` 改为 `**状态：** 已实施`。

- [ ] **Step 3: Commit**

```bash
git add plugins/audit/.claude-plugin/plugin.json docs/superpowers/specs/2026-06-06-audit-review-exclusion-scope-design.md
git commit -m "chore(audit): bump plugin to 0.9.2 and mark exclusion-scope spec implemented"
```

---

## 计划自检（实施前）

| Spec 要求 | 对应 Task |
|-----------|-----------|
| 排除路径表 + HARD-GATE | Task 1 |
| 阶段 0 预处理 + 快速结束模板 | Task 1 |
| 阶段 1 仅用可审 diff | Task 2 |
| 阶段 2 共享规则 + 2b/2d Grep 限制 | Task 3 |
| 阶段 3 防御删除 + 阶段 4 混合 PR 说明 | Task 4 |
| 替换原 docs skip 示例 | Task 3 Step 7 |
| 验收标准 rg 校验 | Task 5 |
| plugin.json / spec 状态 | Task 6 |

无 TBD / 占位符。
