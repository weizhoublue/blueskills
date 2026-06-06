# audit/review 触发条件顶层具象化（T1–T3）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `audit/review` SKILL 中落地 T1–T3：`缺陷的触发条件` 字段内分 **顶层逻辑条件** + **参考触发场景**（禁止含糊词、须具体值）；函数级路径仅写入可达性证据。

**Architecture:** 仅改 `plugins/audit/skills/review/SKILL.md` 与 `plugin.json`。T1/T2/T3 写入共享规则；候选/终稿模板、阶段 3 质检拒收项同步更新；不新增报告章节。

**Tech Stack:** Markdown skill；`rg` 结构校验；无 pytest。

**Reference:** [`docs/superpowers/specs/2026-06-06-audit-review-trigger-concretization-design.md`](../specs/2026-06-06-audit-review-trigger-concretization-design.md)

---

## 文件结构

| 路径 | 改动 | Task |
|------|------|------|
| `plugins/audit/skills/review/SKILL.md` | T1–T3、字段模板、质检、执行约束 | 1–4 |
| `plugins/audit/.claude-plugin/plugin.json` | 版本 + description | 5 |
| `docs/superpowers/specs/2026-06-06-audit-review-trigger-concretization-design.md` | 状态 implemented | 5 |

---

## Task 1: 共享规则 — 新增 T1/T2/T3

**Files:**

- Modify: `plugins/audit/skills/review/SKILL.md`（约 L207 后，`---` 与 `## 缺陷性质` 之间）

- [ ] **Step 1: 在「缺陷成立条件」列表之后插入触发条件规则**

在：

```markdown
- 能说明现有代码路径不会避免该问题。

---

## 缺陷性质
```

改为：

```markdown
- 能说明现有代码路径不会避免该问题。

## 触发条件规则（T1–T3）

- **T1 顶层逻辑**：`缺陷的触发条件` 中的 **顶层逻辑条件** 须从用户/运维可见入口表述（config / input / env / API / CLI / CR spec）；**禁止**仅用函数内变量、局部分支、指针状态作为逻辑条件（那些写入 `相关代码证据 → 可达性证据`）。
- **T2 场景证据**：顶层逻辑条件须有代码 `path:line` 或 PR 原文依据；hedge 语（「可能」「例如」「某些情况下」）不得进入逻辑条件列表。
- **T3 场景具象化**：顶层逻辑条件之后须提供 **参考触发场景** 块（≥1 条）。每条须含：场景来源（`code_synth` / `pr_context` / `hybrid`）、映射逻辑条件编号、配置快照、业务输入、应用层行为、量化观测。**严禁**「大概」「可能」「未来」「某些情况下」及同义含糊语；须具体取值；无法量化写「未能从代码量化」，禁止用含糊句替代。

**输出候选缺陷前（2a/2b/2c/2d 共享）：**

1. 从 diff/锚点提取配置键、默认值、schema、常量（Grep/Read）。
2. 从阶段 1 变更声称提取 `pr_context`（若有）。
3. 合成 ≥1 条参考场景并映射逻辑条件编号。
4. 函数级调用链只写可达性证据，不得作为顶层逻辑条件。
5. 参考场景自检：无禁止词；配置/输入/量化须具体值或「未能从代码量化」。

---

## 缺陷性质
```

- [ ] **Step 2: 校验**

```bash
rg -n 'T1 顶层逻辑|T2 场景证据|T3 场景具象化|code_synth|pr_context' plugins/audit/skills/review/SKILL.md
```

Expected: ≥5 行匹配

- [ ] **Step 3: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): add T1-T3 trigger concretization shared rules"
```

---

## Task 2: 候选格式与字段要求

**Files:**

- Modify: `plugins/audit/skills/review/SKILL.md`（候选缺陷输出格式 + `### 缺陷的触发条件`）

- [ ] **Step 1: 替换候选缺陷输出格式中的触发条件占位**

将：

```markdown
- 缺陷的触发条件：
- 代码缺陷解读：
```

改为：

```markdown
- 缺陷的触发条件：
  - **顶层逻辑条件**（须同时满足；T1 + T2）：
    - 条件1（config/input）：... refs: path:line
    - 条件2（runtime/部署态）：... refs: path:line
  - **参考触发场景**（可评估；T3）：
    - **场景1**（来源：code_synth | pr_context | hybrid）
      - **映射条件**：条件1 + 条件2
      - **配置快照**：`key=value` … refs: path:line 或 PR 引用
      - **业务输入**：API/CLI/请求 + 关键参数与取值
      - **应用层行为**：用户可理解的操作结果
      - **量化观测**：具体数字 + 单位；或「未能从代码量化」
- 代码缺陷解读：
```

- [ ] **Step 2: 重写 `### 缺陷的触发条件` 字段要求**

删除现有 L268–276 简短说明，替换为：

```markdown
### 缺陷的触发条件

须使用 **顶层逻辑条件** + **参考触发场景** 双块结构（T1–T3）；模板见上文「候选缺陷输出格式」。

**禁止词**（逻辑条件与参考场景均适用，含同义变体）：

- 大概、可能、也许、似乎、潜在、有一定概率、在某些情况下
- 未来、将来、若以后、一旦升级后（无当前 diff/代码依据时）
- 无量化形容：很高、很低、较大、较短、设得很小（无具体数字时）
- 无主体操作：用户执行某操作后、配置不当时

**内容归属：**

| 内容 | 写入位置 |
| --- | --- |
| CR/Helm/env/API/CLI 配置与输入 | 顶层逻辑条件 / 配置快照 / 业务输入 |
| 调用链、函数分支、`ptr==nil` 落点 | `相关代码证据 → 可达性证据`（**不得**作为顶层逻辑条件） |

若参考场景只能含糊表述或无法给出任何具体配置/输入取值 → **不要输出**该候选缺陷。
```

- [ ] **Step 3: 校验**

```bash
rg -n '顶层逻辑条件|参考触发场景|禁止词' plugins/audit/skills/review/SKILL.md | head -10
```

Expected: 候选格式与字段要求均有匹配

- [ ] **Step 4: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): T1-T3 trigger field template and requirements"
```

---

## Task 3: 阶段 3 质检改造

**Files:**

- Modify: `plugins/audit/skills/review/SKILL.md`（`# 3. 质检` 节）

- [ ] **Step 1: 在「检查内容」之后插入 T 规则拒收表**

在「对这些模糊描述，必须回到代码证据核实进行核实」段落后插入：

```markdown
### 触发条件合规（T1–T3，证据不足则删除）

| 代号 | 说明 |
| --- | --- |
| `trigger_function_level_only` | 触发条件仅有函数内部分支/变量，无顶层 config/input |
| `trigger_scenario_hedge` | 参考触发场景含禁止词（大概/可能/未来/某些情况下等） |
| `trigger_scenario_no_concrete_value` | 参考场景缺配置具体取值、或缺业务输入具体参数、或量化仅为含糊形容 |
| `trigger_logic_hedge` | 顶层逻辑条件含 hedge 语 |

**处理：**

- 可修复：补全顶层逻辑条件与参考场景具体值，删除禁止词 → 保留 finding
- 无法修复：删除 finding（不得仅润色含糊语）
- 量化观测：允许「未能从代码量化」；禁止「大概 N 秒」「可能降为 0」等
```

- [ ] **Step 2: 扩展「处理规则」首条**

将：

```markdown
- 成立：补充证据和触发条件，改成确定性表述，适当修正问题的严重性等级；
```

改为：

```markdown
- 成立：补充证据；将触发条件改为 T1–T3 合规双块（顶层逻辑条件 + 参考触发场景，具体取值、无禁止词）；适当修正严重性等级；
```

- [ ] **Step 3: 扩展「防漏报」**

在「描述模糊但成立 → **补充**证据与触发条件」后追加：

```markdown
（触发条件须符合 T1–T3，禁止仅删掉禁止词而不补具体值）
```

- [ ] **Step 4: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): stage 3 QC T1-T3 rejection criteria"
```

---

## Task 4: 终稿格式与执行约束

**Files:**

- Modify: `plugins/audit/skills/review/SKILL.md`（阶段 4 + 执行约束）

- [ ] **Step 1: 更新最终报告格式中触发条件注释**

在 `## 最终报告格式` 的缺陷模板中，将：

```markdown
- 缺陷的触发条件：
```

保留字段名，在其上方（模板说明区）或紧接 `## 缺陷` 后增加一句注释（若模板无注释区，则在 `# 4. 报告拼装` 的「处理规则」追加）：

在 `## 处理规则` 列表末尾加：

```markdown
- 每条缺陷的 `缺陷的触发条件` 须为 T1–T3 双块结构（顶层逻辑条件 + 参考触发场景）；函数级路径仅在可达性证据中出现；
```

- [ ] **Step 2: 执行约束追加两条**

在约束 13 之后加：

```markdown
14. 触发条件不得仅用函数内部状态冒充顶层条件；须写 config/input 级逻辑条件 + 具象参考场景。
15. 参考触发场景中严禁「大概」「可能」「未来」等含糊语；须具体配置取值与输入参数，或明确写「未能从代码量化」。
```

- [ ] **Step 3: 委派 prompt 清单补充（可选一行）**

在「每次委派 sub-agent 时，prompt **必须**包含：」列表中追加：

```markdown
- 触发条件规则 T1–T3（含共享规则内全文）
```

- [ ] **Step 4: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): final report and execution constraints for T1-T3"
```

---

## Task 5: 版本号与 spec 状态

**Files:**

- Modify: `plugins/audit/.claude-plugin/plugin.json`
- Modify: `docs/superpowers/specs/2026-06-06-audit-review-trigger-concretization-design.md`

- [ ] **Step 1:** `version` `0.8.3` → `0.8.4`；`description` 末尾加 `；T1–T3 触发条件顶层具象化`

- [ ] **Step 2:** spec 状态行改为 `implemented（2026-06-06，见 plan 2026-06-06-audit-review-trigger-concretization.md）`

- [ ] **Step 3: Commit**

```bash
git add plugins/audit/.claude-plugin/plugin.json docs/superpowers/specs/2026-06-06-audit-review-trigger-concretization-design.md
git commit -m "chore(audit): bump to 0.8.4, mark T1-T3 spec implemented"
```

---

## Task 6: 终验

- [ ] **Step 1:**

```bash
cd /Users/weizhoublue/Documents/git/blueskills
rg -c 'T1|T2|T3|顶层逻辑条件|参考触发场景|trigger_function_level_only' plugins/audit/skills/review/SKILL.md
rg -n '大概|可能|未来' plugins/audit/skills/review/SKILL.md
```

Expected: 第一命令匹配行数 ≥ 12；第二命令匹配应仅在「禁止」说明语境中出现

- [ ] **Step 2:** 对照 spec §10 六项验收标准逐项勾选

- [ ] **Step 3:** `git status` → working tree clean

---

## Spec 覆盖自检

| Spec § | Task |
|--------|------|
| §3 T1–T3 | 1 |
| §4 字段结构 | 2 |
| §5 阶段 2 | 1（共享步骤） |
| §6 阶段 3 | 3 |
| §7 阶段 4 | 4 |
| §8 改动清单 | 1–4 |
| §10 验收 | 6 |
| §12 Rollout | 5 |

无 TBD；无遗漏。
