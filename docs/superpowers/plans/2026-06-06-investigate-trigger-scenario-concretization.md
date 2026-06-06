# investigate-issue 触发条件场景具象化（R21）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `investigate` SKILL 中落地 R21：于 `### 触发条件（正向：须同时满足）` 子节内，在逻辑条件之后增加 **参考触发场景** 块，强制配置快照、业务输入、应用层行为与量化观测，杜绝含糊触发叙述。

**Architecture:** 仅改 `SKILL.md`（插件已内联，无独立 agent 文件）。R21 与 R17/R20 正交：逻辑条件仍仅 `confirmed`；具象 vignette 在同子节内单独成块；阶段 4 评审新增 R21 blocking/major。

**Tech Stack:** Markdown skill 编排；`rg` 结构校验；无 pytest。

**Reference:** [`docs/superpowers/specs/2026-06-06-investigate-trigger-scenario-concretization-design.md`](../specs/2026-06-06-investigate-trigger-scenario-concretization-design.md)

**Conventions:**

- 正文中文；不新增 §2 的 `###` 子节（仍为 5 个）。
- R21 参考场景缺量化 alone **不得** 判 `issue_false`。
- `issue_true` 缺参考触发场景块 → **blocking**。

---

## 文件结构

| 路径 | 改动 | Task |
|------|------|------|
| `plugins/investigate-issue/skills/investigate/SKILL.md` | R21 全局规则、2a/2b 模板、阶段 3/4/5 | 1–5 |
| `plugins/investigate-issue/.claude-plugin/plugin.json` | 版本号 + description | 6 |
| `docs/superpowers/specs/2026-06-06-investigate-trigger-scenario-concretization-design.md` | 状态 → implemented | 6 |

---

## Task 1: 全局规则 — 新增 R21

**Files:**

- Modify: `plugins/investigate-issue/skills/investigate/SKILL.md`（约 L54 后，R20 与 R15 之间）

- [ ] **Step 1: 在 R20 行之后插入 R21**

定位：

```markdown
- **场景证据（R20）**：正向触发清单仅列 `confirmed`+`path:line` 的运行时状态；...
- **终稿禁止表格（R15）**：...
```

在 R20 与 R15 之间插入：

```markdown
- **场景具象化（R21）**：`### 触发条件（正向：须同时满足）` 在**逻辑条件**列表之后须提供 **参考触发场景** 块（`issue_true` 时必填 ≥1 条）。每条须含：场景来源（`code_synth` / `user_incident` / `hybrid`）、映射逻辑条件编号、配置快照、业务输入、应用层行为、量化观测点。数值须为代码字面量/校验边界（`confirmed`+refs）或 issue_brief 陈述（`doc_declared`/`inference`）；无法量化写「未能从代码量化」；禁止无依据魔法数字。参考场景不计入逻辑条件清单；禁止用 hedge 语（「可能」「例如」「某些情况下」）冒充逻辑条件。
```

- [ ] **Step 2: 微调 R20 首句（避免与 R21 混淆）**

将 R20 行首「正向触发清单」改为「逻辑条件列表（正向触发清单）」，整句为：

```markdown
- **场景证据（R20）**：逻辑条件列表（正向触发清单）仅列 `confirmed`+`path:line` 的运行时状态；`inference`/未验证的场景移到「未能从代码确认的前提」子节，不得计入逻辑条件列表；禁止「在某些情况下可能…」「例如…时」无 refs 进逻辑条件列表。
```

- [ ] **Step 3: 校验**

```bash
rg -n '场景具象化（R21）|code_synth|user_incident|hybrid' plugins/investigate-issue/skills/investigate/SKILL.md
```

Expected: ≥1 行匹配 R21；含 `code_synth`

- [ ] **Step 4: Commit**

```bash
git add plugins/investigate-issue/skills/investigate/SKILL.md
git commit -m "feat(investigate): add R21 scenario concretization global rule"
```

---

## Task 2: 阶段 2a — 量化提取与参考场景素材

**Files:**

- Modify: `plugins/investigate-issue/skills/investigate/SKILL.md`（阶段 B + 2a 输出模板）

- [ ] **Step 1: 扩展阶段 B 工作步骤**

在「填写缺陷落点、触发条件（R17）、后果…」一行之后，追加：

```markdown
- **R21 量化与场景合成**（在触发条件块内完成）：
  1. 从缺陷落点反向 Grep/Read：相关配置键默认值、常量、校验 `min/max`、枚举字面量。
  2. 从 C0 入口推断典型业务输入（api/cli/config apply）；无法确认 → 写入「未能确认的主张」，场景中标 `(inference)`。
  3. 合成 ≥1 条 `code_synth` 参考场景素材；若 `issue_brief` 含用户配置/请求，增 `user_incident` 或 `hybrid` 场景。
  4. **禁止**在逻辑条件或参考场景中使用无 refs 的魔法数字。
```

- [ ] **Step 2: 重写 2a `**触发条件**` 输出块**

将现有 `**触发条件**` 块（约 L201–206）替换为：

```markdown
**触发条件**：
- **逻辑条件**（须同时满足；仅 confirmed 进此列表，R17 + R20）：
  - 条件1（config）：... refs: path:line (confirmed)
  - 条件2（runtime_state）：... refs: path:line (confirmed)
- **不触发情形**（供阶段 3 反向子节；R17）：
  - 情形1：... 原因：... refs 或 (inference)

**参考触发场景素材**（供阶段 3 撰写；R21；不计入逻辑条件）：
- **场景1**（来源：code_synth | user_incident | hybrid）
  - **映射条件**：条件1 + 条件2
  - **配置快照**：`key=value` … refs: path:line (confirmed) 或 tier
  - **业务输入**：API/CLI/事件 + 关键参数；无法确认则写「未能从代码确认」并标 (inference)
  - **应用层行为**：…（对齐 C0–C3 业务语言）refs: path:line
  - **量化观测**：常量/默认/边界数值；无法则写「未能从代码量化」
```

- [ ] **Step 3: 2a 扫描覆盖说明追加一项**

在 `## 扫描覆盖说明` 列表末尾加：

```markdown
- [ ] 已产出 ≥1 条参考触发场景素材（含配置快照、业务输入、应用层行为、量化观测）
```

- [ ] **Step 4: 校验**

```bash
rg -n '参考触发场景素材|R21 量化与场景合成' plugins/investigate-issue/skills/investigate/SKILL.md
```

Expected: 各 ≥1 匹配

- [ ] **Step 5: Commit**

```bash
git add plugins/investigate-issue/skills/investigate/SKILL.md
git commit -m "feat(investigate): 2a code-tracer R21 scenario material output"
```

---

## Task 3: 阶段 2b — 用户事故素材

**Files:**

- Modify: `plugins/investigate-issue/skills/investigate/SKILL.md`（2b 阶段 B + 输出模板）

- [ ] **Step 1: B1 情境补充 R21 素材要求**

在 `- **B1** 情境：谁、部署/配置、**代码实际能力边界**…` 行末追加说明：

```markdown
（须摘录用户声称的具体配置取值、操作步骤、输入请求，供 R21 `user_incident`/`hybrid` 场景；区分 `doc_declared` vs `confirmed`）
```

- [ ] **Step 2: 保留项追加参考场景素材**

在 `**3. 保留项**：兄弟分支对比（必填）、不触发场景、关键机制动机 W1–W3（可选）。` 改为：

```markdown
**3. 保留项**：兄弟分支对比（必填）、不触发场景、**参考触发场景素材（用户侧：配置快照、业务输入、可观察量化现象）**、关键机制动机 W1–W3（可选）。
```

- [ ] **Step 3: 规则摘要追加两条**

在 2b 规则摘要列表末尾加：

```markdown
- 用户主张 `missing` / `doc_only` 的能力**不得**写入参考场景素材作为已发生事实。
- B4 应用层行为描述须与 2a C0–C3 一致；不一致须说明原因。
```

- [ ] **Step 4: 2b 输出模板 `**业务流**` 后插入块**

在 `**业务流**` 三节之后、`**兄弟分支对比**` 之前插入：

```markdown
**参考触发场景素材（用户侧，供阶段 3 R21）**：
- 配置快照：... (doc_declared/confirmed/inference) refs: P*
- 业务输入：... (doc_declared/inference)
- 可观察量化现象：... (doc_declared/inference)
```

- [ ] **Step 5: 2b 扫描覆盖说明追加**

```markdown
- [ ] 已摘录用户配置/输入/量化现象（或注明 issue_brief 未提供）
```

- [ ] **Step 6: 校验**

```bash
rg -n '参考触发场景素材（用户侧' plugins/investigate-issue/skills/investigate/SKILL.md
```

Expected: exit 0

- [ ] **Step 7: Commit**

```bash
git add plugins/investigate-issue/skills/investigate/SKILL.md
git commit -m "feat(investigate): 2b business context R21 user incident material"
```

---

## Task 4: 阶段 3 — 撰写与三节必含要素

**Files:**

- Modify: `plugins/investigate-issue/skills/investigate/SKILL.md`（阶段 3 步骤 1/2 + 三节必含要素）

- [ ] **Step 1: 步骤 1 综合列表追加**

在内部分析综合 bullet 列表中，在「调用链、缺陷落点、触发条件、后果（阶段 2a）」后确保包含：

```markdown
- 2a 参考触发场景素材、2b 用户侧参考场景素材（阶段 2a/2b）
```

- [ ] **Step 2: 步骤 2 撰写规则追加 R21**

在 `- **R20**：...` 行后插入：

```markdown
- **R21**：`### 触发条件（正向：须同时满足）` 内逻辑条件列表之后写 **参考触发场景** 块；合并 2a 素材 + 2b 用户情境；`issue_true` 时必填 ≥1 条；每条映射逻辑条件编号；hedge 语禁止出现在逻辑条件列表
```

- [ ] **Step 3: 更新 `## 2. 触发条件` 子节第 1 项说明**

将：

```markdown
1. `### 触发条件（正向：须同时满足）`（仅 confirmed；配置项后可括注 W2 业务目的）
```

改为：

```markdown
1. `### 触发条件（正向：须同时满足）` — 内含两块：**逻辑条件**（仅 confirmed，R17+R20；配置项后可括注 W2 业务目的）+ **参考触发场景**（R21，`issue_true` 必填）
```

- [ ] **Step 4: 在子节顺序表后插入 §2 内部模板（阶段 3 撰写用）**

在 `5. \`### 完整触发调用链\`` 与 `\`## 3. 结论\`` 之间插入：

````markdown
`### 触发条件（正向：须同时满足）` 内部模板（R17 + R20 + R21）：

```markdown
### 触发条件（正向：须同时满足）

**逻辑条件**（仅 confirmed；R17 + R20）：
- 条件1（config）：... refs: path:line (confirmed)
- 条件2（runtime_state）：... refs: path:line (confirmed)

**参考触发场景**（可评估，不计入上方逻辑条件；R21）：
- **场景1**（来源：code_synth | user_incident | hybrid）
  - **映射条件**：条件1 + 条件2
  - **配置快照**：...
  - **业务输入**：...
  - **应用层行为**：...
  - **量化观测**：...
```
````

- [ ] **Step 5: 校验**

```bash
rg -n '参考触发场景.*R21|逻辑条件.*仅 confirmed' plugins/investigate-issue/skills/investigate/SKILL.md | head -5
```

Expected: 阶段 3 区段有匹配

- [ ] **Step 6: Commit**

```bash
git add plugins/investigate-issue/skills/investigate/SKILL.md
git commit -m "feat(investigate): stage 3 R21 trigger section writing rules"
```

---

## Task 5: 阶段 4 评审 + 阶段 5 终稿 + 补充员

**Files:**

- Modify: `plugins/investigate-issue/skills/investigate/SKILL.md`（评审扫描、resolution、stdout、补充员）

- [ ] **Step 1: R17 评审项追加 hedge 与逻辑条件措辞**

在 R17 `major：正向触发缺运行时状态要素` 之后追加：

```markdown
- blocking（R21 交叉）：逻辑条件列表含「可能/例如/某些情况下」未标 `(inference)`
```

- [ ] **Step 2: 在 R20 扫描块之后插入 R21 扫描块**

```markdown
场景具象化 R21（`触发条件` 必查）：
- blocking：`issue_true` 且 `### 触发条件` 下无 **参考触发场景** 块
- blocking：参考场景含具体数值无 refs 且未标 `(inference)`
- major：参考场景缺配置快照 / 业务输入 / 应用层行为 / 量化观测任一项
- major：参考场景未写「映射条件：条件 N」
- major：读者无法用该 vignette 复述如何踩坑（遮住 path:line 后仍模糊）
- major：参考场景将 `missing`/`doc_only` 能力写作已发生事实
```

- [ ] **Step 3: 更新 resolution 说明**

将：

```markdown
- 仅有动机/场景类 major → `needs_enrichment`
- 第3轮结束仍有动机或场景 major → `partial`
```

改为：

```markdown
- 仅有动机/场景证据/R21 类 major → `needs_enrichment`
- 第3轮结束仍有动机、场景证据或 R21 major → `partial`
```

在「禁止：因缺 W2 单独判 blocking」行后追加：

```markdown
- 禁止：因参考场景缺量化 alone 判 `issue_false`
```

- [ ] **Step 4: 评审输出格式追加 R21 审核节**

在 `**场景证据审核**：` 块之后插入：

```markdown
**场景具象化审核（R21）**：
- 场景：... 缺字段：[配置快照/业务输入/应用层行为/量化观测/映射条件] 严重程度：blocking/major
```

- [ ] **Step 5: 补充员工作内容追加 R21**

在补充员「禁止 markdown 表格」之前插入：

```markdown
- R21 缺失项：在 `### 触发条件` 内补 **参考触发场景** 块或补全 vignette 字段；无法补充时写「综合分析中暂无依据」
```

- [ ] **Step 6: 更新阶段 5 stdout `## 2. 触发条件` 注释**

将：

```markdown
（须含：正向须同时满足 → 故障表现 → 未能从代码确认的前提（若有）→ 不触发/正常情形（反向）→ 完整触发调用链。）
```

改为：

```markdown
（须含：`### 触发条件` 内逻辑条件 + 参考触发场景（R21）→ 故障表现 → 未能从代码确认的前提（若有）→ 不触发/正常情形 → 完整触发调用链。）
```

- [ ] **Step 7: complete 前提追加 R21**

将 `**complete 前提**：三节满足 R16/R17/R19；无 blocking` 改为：

```markdown
**complete 前提**：三节满足 R16/R17/R19/R21（`issue_true` 时含参考触发场景）；无 blocking
```

- [ ] **Step 8: 校验**

```bash
rg -n '场景具象化 R21|场景具象化审核' plugins/investigate-issue/skills/investigate/SKILL.md
```

Expected: ≥2 匹配

- [ ] **Step 9: Commit**

```bash
git add plugins/investigate-issue/skills/investigate/SKILL.md
git commit -m "feat(investigate): stage 4/5 R21 review and stdout template"
```

---

## Task 6: 版本号与 spec 状态

**Files:**

- Modify: `plugins/investigate-issue/.claude-plugin/plugin.json`
- Modify: `docs/superpowers/specs/2026-06-06-investigate-trigger-scenario-concretization-design.md`

- [ ] **Step 1: bump plugin version**

`plugin.json` 中 `"version": "0.8.4"` → `"0.8.5"`

`description` 末尾追加：`；R21 触发条件参考场景具象化`

- [ ] **Step 2: spec 状态行**

将 spec 第 4 行 `- 状态：已审阅（brainstorming 确认）` 改为：

```markdown
- 状态：implemented（2026-06-06，见 plan `2026-06-06-investigate-trigger-scenario-concretization.md`）
```

- [ ] **Step 3: Commit**

```bash
git add plugins/investigate-issue/.claude-plugin/plugin.json docs/superpowers/specs/2026-06-06-investigate-trigger-scenario-concretization-design.md
git commit -m "chore(investigate-issue): bump to 0.8.5, mark R21 spec implemented"
```

---

## Task 7: 终验（grep 清单）

**Files:** 无新建

- [ ] **Step 1: 运行完整 grep 验收**

```bash
cd /Users/weizhoublue/Documents/git/blueskills
rg -c 'R21|参考触发场景|code_synth|场景具象化' plugins/investigate-issue/skills/investigate/SKILL.md
rg -n '### 触发条件（正向：须同时满足）' plugins/investigate-issue/skills/investigate/SKILL.md | wc -l
rg -n '^### ' plugins/investigate-issue/skills/investigate/SKILL.md | rg '参考触发场景' || echo "OK: no extra ### subsection for reference scenarios"
```

Expected:

- 第一个命令：匹配行数 ≥ 8
- 第二个命令：`wc -l` ≥ 2（模板 + 必含要素各至少一处）
- 第三个命令：输出 `OK: no extra ### subsection`（参考场景不得独立成 `###` 子节）

- [ ] **Step 2: 对照 spec §10 验收表逐项勾选**

| # | 标准 | 验证方式 |
|---|------|----------|
| 1 | `issue_true` 终稿含逻辑条件 + 参考触发场景 | Task 4 Step 3 + Task 5 Step 6 |
| 2 | vignette 五字段 | Task 2 Step 2 模板 |
| 3 | 逻辑条件无 hedge | Task 5 Step 1 |
| 4 | R21 blocking/major | Task 5 Step 2 |
| 5 | 不破坏 R17/R20/R18 | R20 仍限制逻辑条件；R18 未改 |
| 6 | §2 仍 5 个 `###` | Task 7 Step 1 第三条 |

- [ ] **Step 3: 确认工作区干净（除预期文件外）**

```bash
git status
```

Expected: working tree clean

---

## Spec 覆盖自检

| Spec 章节 | 对应 Task |
|-----------|-----------|
| §3 R21 与 R17/R20 正交 | Task 1 |
| §4 §2 结构与内部模板 | Task 4 |
| §5.1 2a upstream | Task 2 |
| §5.2 2b upstream | Task 3 |
| §6 阶段 3 撰写 | Task 4 |
| §7 阶段 4 评审 | Task 5 |
| §8 SKILL 改动清单 | Task 1–5 |
| §10 验收标准 | Task 7 |
| §12 Rollout / version | Task 6 |

无遗漏；无 TBD 占位。
