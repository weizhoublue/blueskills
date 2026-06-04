# investigate-issue：取消「问题后果」节 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将终稿从四节改为三节；删除独立「问题后果」；在「触发条件」正向清单之后新增必填子节「### 故障表现」，由 writer 从 `issue-analysis.json` 的 `consequences` 字段生成。

**Architecture:** 采用 spec 方案 1——`trace.json` / merge 仍保留 `consequences` 供分析；仅改 agent 提示词、主编排 SKILL、验证脚本与安装文档。challenger 的 R17 / 场景 / 动机检查集中到 `trigger-conditions`。

**Tech Stack:** Markdown agent 定义、bash 结构验证脚本、jq（合并逻辑不变）

**Spec:** [`docs/superpowers/specs/2026-06-04-investigate-issue-drop-consequences-section-design.md`](../specs/2026-06-04-investigate-issue-drop-consequences-section-design.md)

---

## File map

| File | Responsibility |
| --- | --- |
| `plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh` | 结构回归：三节、故障表现、禁止旧四节后果流 |
| `plugins/investigate-issue/agents/issue-writer.md` | 删除 `consequences` 节；扩展 `trigger-conditions` |
| `plugins/investigate-issue/agents/issue-challenger.md` | 读三节；R17/故障表现反模式；`target_section` 枚举 |
| `plugins/investigate-issue/agents/code-tracer.md` | 注释：`consequences` 仅供故障表现 |
| `plugins/investigate-issue/skills/investigate/SKILL.md` | section 表、阶段 4/6、stdout 模板、R17 措辞 |
| `docs/installation.md` | 用户可见终稿结构说明 |

**不修改：** `issue-analysis.json` jq 合并、`scout.json`、`business-context-analyst.md`

---

### Task 1: 先加强 verify 脚本（红灯）

**Files:**
- Modify: `plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh`

- [ ] **Step 1: 在现有 R20 检查之后追加以下块**

在 `grep -q 'R20\|unverified' "$SKILL"` 行之后、`# no investigate-project paths` 之前插入：

```bash
# three-section report (no standalone consequences section)
grep -q '故障表现' "$ROOT/agents/issue-writer.md" || err "writer missing 故障表现 subsection"
grep -q 'sections/consequences.md' "$SKILL" && err "SKILL must not reference sections/consequences.md"
grep -q '## 2\. 问题后果' "$SKILL" && err "SKILL stdout must not have ## 2. 问题后果"
grep -q '## 2\. 触发条件' "$SKILL" || err "SKILL stdout must have ## 2. 触发条件"
grep -q '## 3\. 结论' "$SKILL" || err "SKILL stdout must have ## 3. 结论"
grep -q '缺.*故障表现' "$ROOT/agents/issue-challenger.md" || err "challenger missing 故障表现 gap checks"
grep -q 'sections/consequences.md' "$ROOT/agents/issue-challenger.md" && err "challenger must not read consequences.md"
grep -q 'target_section.*consequences' "$ROOT/agents/issue-challenger.md" && err "challenger target_section must not include consequences"
```

- [ ] **Step 2: 运行 verify，确认失败**

Run:

```bash
bash plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh
```

Expected: `verify FAILED`（至少 `writer missing 故障表现`、`SKILL must not reference sections/consequences.md` 等）

- [ ] **Step 3: Commit（仅 verify，允许红灯）**

```bash
git add plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh
git commit -m "test(investigate-issue): verify three-section report without consequences"
```

---

### Task 2: 更新 issue-writer

**Files:**
- Modify: `plugins/investigate-issue/agents/issue-writer.md`

- [ ] **Step 1: 删除整节 `### \`consequences\`（R17 条件化）`**

删除从 `### \`consequences\`（R17 条件化）` 到 `### \`trigger-conditions\`` 之前的全部内容（含四个子节：用户与功能影响、何时不会出现、代码层机制、代码佐证）。

- [ ] **Step 2: 替换 `### \`trigger-conditions\`` 块为以下内容**

```markdown
### `trigger-conditions`（R17 正反向 + R20 + 故障表现）

素材：`trigger_conditions` + `consequences.user_impact`（及必要时 `consequences.code_level` 中**用户可感知**的一句，禁止单独开「代码层机制」子节）。

1. **`### 触发条件（正向：须同时满足）`** — 仅 **confirmed** 场景；配置项后可用一句括注 **业务目的（W2）**；**禁止**在本子节写长段故障/症状叙事
2. **`### 故障表现`**（**必填**）— 紧接正向清单之后：当上一节条件**同时**满足时的用户/评估/功能可见坏结果；**禁止**再列一套与第 1 子节同文的条件 bullet
3. **`### 未能从代码确认的前提（不应计入触发清单）`** — 若有 inference/unverified 则**必填**；**禁止**与正向清单重复编号
4. **`### 不触发 / 表现为正常的情形`**（**必填**）— R17 反向（吸收原「何时不会出现后果」类内容）
5. **`### 从输入到落点的过程`**
6. **`### 代码佐证`**（可选）
```

- [ ] **Step 3: 更新 R20 第 2 条**

将：

```markdown
2. `inference` 或 `unverified[]` 中的场景 → **`### 未能从代码确认的前提（不应计入触发清单）`**（`trigger-conditions` 存在此类主张时**必填**；`problem-description` / `consequences` 按需）。
```

改为：

```markdown
2. `inference` 或 `unverified[]` 中的场景 → **`### 未能从代码确认的前提（不应计入触发清单）`**（`trigger-conditions` 存在此类主张时**必填**；`problem-description` 按需）。
```

- [ ] **Step 4: 更新禁止形态**

在「要求的输出形态」或「禁止的输出形态」增加一条：

```markdown
- 在 `### 故障表现` 中重复粘贴「### 触发条件（正向）」的完整条件清单
```

- [ ] **Step 5: 更新 `draft_all`**

将：

```markdown
2. **先 Write 前三节**，再 Write **`sections/issue-verdict.md`**
```

改为（三节 = 问题描述 + 触发条件 + 结论）：

```markdown
2. **先 Write** `sections/problem-description.md` 与 `sections/trigger-conditions.md`，再 Write **`sections/issue-verdict.md`**（**禁止** Write `sections/consequences.md`）
```

将返回主线程中的 `sections_written: 4` 改为 `sections_written: 3`。

- [ ] **Step 6: 更新 supplement 示例 JSON**

`target_section` 示例若仍为 `"consequences"`，改为 `"trigger-conditions"`。

- [ ] **Step 7: Commit**

```bash
git add plugins/investigate-issue/agents/issue-writer.md
git commit -m "feat(investigate-issue): writer three sections with 故障表现 in trigger"
```

---

### Task 3: 更新 issue-challenger

**Files:**
- Modify: `plugins/investigate-issue/agents/issue-challenger.md`

- [ ] **Step 1: 全文「四节」→「三节」**

例如首段：

```markdown
首要目标：**让未读过仓库的新手读者能读懂整份三节报告**（问题描述、触发条件、结论）。
```

- [ ] **Step 2: 评审 Read 列表**

将：

```markdown
- **一次 Read 四节**：`sections/problem-description.md`、`consequences.md`、`trigger-conditions.md`、**`issue-verdict.md`**
```

改为：

```markdown
- **一次 Read 三节**：`sections/problem-description.md`、`trigger-conditions.md`、**`issue-verdict.md`**
```

- [ ] **Step 3: 替换 R17 小节标题与表格**

将 `### 条件严谨性 R17（\`consequences\`、\`trigger-conditions\` 必查）` 改为 `### 条件严谨性 R17（\`trigger-conditions\` 必查）`，表格下追加：

```markdown
| 缺少 `### 故障表现` 子节 | `blocking` |
| `### 故障表现` 重复粘贴正向触发条件清单（同文 bullet） | `blocking` |
```

删除仅针对独立 consequences 文件的表述。

- [ ] **Step 4: 更新 R18 / R20 / 其他扫描范围**

- R18：`consequences` → 删除；保留 `problem-description` + `trigger-conditions`（按条件扫）
- B2/B4：从 `consequences` 改为仅 `problem-description`（或 `problem-description` + `trigger-conditions` 的故障表现）
- 场景证据 R20：删除 `consequences`；保留 `problem-description`、`trigger-conditions`
- `complete 前提`：`四节` → `三节`

- [ ] **Step 5: 更新提问模板**

- 模板 3、4：`target: consequences / trigger-conditions` → `target: trigger-conditions`
- 模板 6：`后果与触发条件表述矛盾` → `问题描述与触发条件（含故障表现）表述矛盾`
- 模板 12：`problem-description 或 consequences` → `problem-description 或 trigger-conditions`（`field_hint` 指向 `§故障表现`）
- 模板 14：`trigger-conditions 或 consequences` → `trigger-conditions`

- [ ] **Step 6: 更新 gaps schema**

```json
"target_section": "problem-description|trigger-conditions|issue-verdict",
```

- [ ] **Step 7: Commit**

```bash
git add plugins/investigate-issue/agents/issue-challenger.md
git commit -m "feat(investigate-issue): challenger checks 故障表现 in trigger-conditions only"
```

---

### Task 4: 更新 code-tracer 注释

**Files:**
- Modify: `plugins/investigate-issue/agents/code-tracer.md`

- [ ] **Step 1: 在工作步骤第 4 条后增加说明**

在 `4. 填写 \`consequences\`（code_level + user_impact）与 \`trigger_conditions\`` 后追加：

```markdown
   - `consequences` **不**对应独立报告节；由 issue-writer 写入 `trigger-conditions` 的 **`### 故障表现`**（素材以 `user_impact` 为主）。
```

- [ ] **Step 2: Commit**

```bash
git add plugins/investigate-issue/agents/code-tracer.md
git commit -m "docs(investigate-issue): trace consequences feed 故障表现 subsection"
```

---

### Task 5: 更新主编排 SKILL.md

**Files:**
- Modify: `plugins/investigate-issue/skills/investigate/SKILL.md`

- [ ] **Step 1: 更新 R17 全局红线（约第 10 条）**

将：

```markdown
10. **条件严谨性（R17）**：`consequences` 与 `trigger-conditions` 须**正向 + 反向**成对表述。
```

改为：

```markdown
10. **条件严谨性（R17）**：`trigger-conditions` 须**正向 + 故障表现 + 反向**成对表述；正向清单不得在「故障表现」中重复粘贴。
```

- [ ] **Step 2: 更新 section id 表**

删除 `问题后果 | consequences | sections/consequences.md` 行。

将 `MAX_REVIEW_ROUNDS` 说明中的「四节」改为「三节（含结论）」。

- [ ] **Step 3: 阶段 4 标题与文件列表**

- `撰写四节初稿` → `撰写三节初稿`
- 删除 `sections/consequences.md`
- 仅保留三文件 + issue-verdict

- [ ] **Step 4: 阶段 5 描述**

`四节合并后的完整报告` → `三节合并后的完整报告`

- [ ] **Step 5: 替换 stdout 模板（阶段 6）**

```markdown
## 1. 问题描述

（须含：业务上发生了什么 → 可选「关键机制为何如此设计」（W1/W2/W3，R18）→ 前因后果链 → 兄弟路径对比；代码佐证置后。禁止以 path:line 清单作为根因正文。）

...

## 2. 触发条件

（须含：**正向须同时满足** → **故障表现** → **不触发/表现为正常的情形**（反向）→ 从输入到落点；禁止在故障表现中重复正向条件清单。可含 `### 未能从代码确认的前提`：inference 场景不得计入「须同时满足」，见 R20。）

...

## 3. 结论

REVIEW_RESULT=issue_true

（本节正文**仅允许**上述一行，禁止任何解释。）
```

- [ ] **Step 6: 阶段 6 Read 说明**

`Read 四节` → `Read 三节`（`problem-description.md`、`trigger-conditions.md`、`issue-verdict.md`）

- [ ] **Step 7: 更新「三节素材映射」**

删除「问题后果」行；在「触发条件」行注明：

```markdown
- **触发条件** ← trace（`trigger_conditions` + `consequences` 用于故障表现）+ scout
```

- [ ] **Step 8: 阶段 4 writer 速查**

`draft_all 一次写齐四节` → `draft_all 一次写齐三节`

- [ ] **Step 9: Commit**

```bash
git add plugins/investigate-issue/skills/investigate/SKILL.md
git commit -m "feat(investigate-issue): orchestrator three-section stdout template"
```

---

### Task 6: 更新 installation.md

**Files:**
- Modify: `docs/installation.md`

- [ ] **Step 1: 替换 investigate-issue  bullet（约第 52 行）**

将：

```markdown
   - writer 一次写好四节；**§1 问题描述** … **§3 触发条件** …
```

改为：

```markdown
   - writer 一次写好三节（问题描述、触发条件、结论）；**§1 问题描述** 中推荐含 **「关键机制为何如此设计」**（W1/W2/W3）；**§2 触发条件** 在正向清单后须有 **「故障表现」** 子节（用户可见坏结果，素材来自分析中的 `consequences`，不单独设「问题后果」节）；正向清单仅列代码已证实状态，未能证实的场景进「未能从代码确认的前提」（R20）；**§3 结论** 仅一行 `REVIEW_RESULT=issue_true` 或 `REVIEW_RESULT=issue_false`。
```

- [ ] **Step 2: Commit**

```bash
git add docs/installation.md
git commit -m "docs: installation three-section investigate-issue report"
```

---

### Task 7: 绿灯 — 运行 verify

**Files:**
- Test: `plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh`

- [ ] **Step 1: 运行验证**

```bash
bash plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh
```

Expected: `verify OK`

- [ ] **Step 2: 若失败，按错误信息回到 Task 2–5 修补**

- [ ] **Step 3: 更新 spec 状态（可选一行）**

在 `docs/superpowers/specs/2026-06-04-investigate-issue-drop-consequences-section-design.md` 顶部 `状态：` 改为 `已实现（plan 2026-06-04）` 并 commit。

```bash
git add docs/superpowers/specs/2026-06-04-investigate-issue-drop-consequences-section-design.md
git commit -m "docs: mark drop-consequences spec as implemented"
```

---

## Spec coverage checklist

| Spec § | Task |
| --- | --- |
| §4 终稿三节结构 | Task 5 stdout 模板 |
| §5 trigger 子节含故障表现 | Task 2, 3 |
| §6 分工表 | Task 2, 5 |
| §7.1 trace 保留 consequences | Task 4（不改 schema） |
| §7.2 文件列表 | Tasks 1–6 |
| §8 challenger 增量 | Task 3 |
| §11 验收 verify | Task 1, 7 |

---

## Manual smoke test（可选，非 CI）

在任意已 `cd` 的目标仓库运行一次 `/investigate-issue:investigate`（或本地编排），检查 stdout：

- 无 `## 2. 问题后果`
- `## 2. 触发条件` 下存在 `### 故障表现`
- `ISSUE_TMP/sections/` 无 `consequences.md`（`ISSUE_KEEP_TMP=1` 时）

---
