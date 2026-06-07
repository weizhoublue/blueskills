# audit/review 触发条件精简与非触发场景（T3 v3 / T4）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `audit/review` SKILL 中删除冗余的「顶层逻辑条件」，将「参考触发场景」升级为唯一必填触发块（T3 v3），并新增可选「非触发场景」（T4）。

**Architecture:** 仅改 `plugins/audit/skills/review/SKILL.md` 与 `plugin.json`；在现有 E1/R1/T3 v2 区块上删除 T1/T2、升级 T3、追加 T4；同步更新候选/终稿模板、阶段 3 质检、阶段 4 与执行约束；不新增报告 `###` 子节。

**Tech Stack:** Markdown skill；`rg` 结构校验；无 pytest。

**Reference:** [`docs/superpowers/specs/2026-06-07-audit-review-trigger-simplification-design.md`](../specs/2026-06-07-audit-review-trigger-simplification-design.md)

---

## 文件结构

| 路径 | 改动 | Task |
|------|------|------|
| `plugins/audit/skills/review/SKILL.md` | T3 v3/T4 规则、模板、质检、约束 | 1–4 |
| `plugins/audit/.claude-plugin/plugin.json` | 版本 + description | 5 |
| `docs/superpowers/specs/2026-06-07-audit-review-trigger-simplification-design.md` | 状态 → implemented | 5 |

---

## Task 1: 共享规则 — 删除 T1/T2，升级 T3 v3，新增 T4

**Files:**

- Modify: `plugins/audit/skills/review/SKILL.md`（约 L222、L292–350）

- [ ] **Step 1: 更新阶段 2 委派 prompt 引用（L222）**

将：

```markdown
- 下方「共享规则」全文（含证据与触发规则 E1/R1/T1–T3）
```

改为：

```markdown
- 下方「共享规则」全文（含证据与触发规则 E1/R1/T3–T4）
```

- [ ] **Step 2: 将 `## 证据与触发规则（E1 / R1 / T1–T3）` 至自检列表（L292–350）替换为以下全文**

```markdown
## 证据与触发规则（E1 / R1 / T3–T4）

### E1 变更点证据

写入 `相关代码证据 → 变更点证据`，每条**必填**：

1. **文件路径**
2. **符号**：函数 / 方法 / 类名（对应 diff 锚点）
3. **行号区间**：辅助定位，**不得**作为唯一追溯依据
4. **关键代码片段**：3～15 行，含缺陷相关语句；兄弟对比须体现差异（如有过滤 vs 无过滤）
5. **变更摘要**：一句话说明差异性质

### R1 可达性证据

写入 `相关代码证据 → 可达性证据`，三块**均必填**：

1. **用户可见入口（R1-a）**：配置面 + 键/参数 + refs（定义/注册）。类型：环境变量、CLI、YAML/配置文件、CR spec、HTTP/RPC API、SDK 构造参数。找不到任何用户可见入口 → **不得输出**该 finding。
2. **完整调用链（R1-b）**：从 R1-a 入口到缺陷函数，每跳 `符号名 @ 文件路径:行号`；中间框架层（Ray、HTTP router、K8s controller）保留。内部模块间函数调用**只写此处**，**不得**写入参考场景的「外部输入输出」。
3. **防护未生效原因（R1-c）**：validation / defaulting / fallback / 兄弟路径对比为何未挡住。

**R1 与触发条件边界：** R1 写前提如何沿代码路径到达缺陷函数；触发条件写用户侧如何复现（参考场景）及可选反面例子（非触发场景）。

### T3 参考触发场景（v3）

`缺陷的触发条件` 中须提供 **参考触发场景** 块（≥1 条），为**唯一必填**触发格式。每条须含：

- 场景来源（`code_synth` / `pr_context` / `hybrid`）
- **用户配置**（结构化条目；无则写「无」）
- **外部输入输出**（结构化条目；无则写「无（纯用户配置/内部运行时触发）」）
- **应用层行为**（用户可理解的操作结果，非函数名罗列）

**禁止**仅用函数内变量、局部分支、指针状态作为触发描述（那些写入 R1-b）。每条场景的用户配置与外部 I/O 须有代码 `path:line` 或 PR 原文依据；hedge 语不得进入场景内容。

**用户配置**每条：配置面、键或参数、取值、定义/注册 refs、读取/生效 refs。

**外部输入输出**分两类（按实际存在选用）：

- **外部客户端输入**：HTTP/CLI/gRPC/MQ 等外部主动发给本软件的请求
- **外部服务响应**：Ray/K8s/第三方 API 等本软件依赖的外部返回

每条条目含：I/O 类型、请求标识或来源服务、关键参数/字段与取值、定义/注册 refs、传入软件 refs。

多触发路径：写多条场景，每条独立可读；同一路径只需一条，禁止为凑数拆分。

**严禁**「大概」「可能」「未来」「某些情况下」及同义含糊语。**已删除**「量化观测」字段（后果由「造成的代码后果和业务功能后果」承担）。

### T4 非触发场景（可选）

`缺陷的触发条件` 中可追加 **非触发场景** 块（**最多 1 条**；**可不写**）。

- **何时写**：能从代码/配置明确推断出与某条参考场景仅差一两项的反例时
- **何时省略**：纯内部竞态、无用户可见开关、无法构造有意义反例时
- **若写了**，须含：**对比说明**（相对哪条参考场景、哪项配置或外部 I/O 不同）、**用户配置** 和/或 **外部输入输出**（只写差异项；结构同 T3）、**应用层行为**（此情况下正常发生什么）
- 差异项须有配置面/I/O 类型 + refs；适用与 T3 相同的禁止词表
- **不得**把反证检查里的代码兜底复述为非触发场景

**输出候选缺陷前（2a/2b/2c/2d 共享）：**

1. 从 diff/锚点提取配置键、默认值、schema、常量、外部 API 定义（Grep/Read）。
2. 从阶段 1 变更声称提取 `pr_context`（若有）。
3. 合成 ≥1 条自洽参考场景（用户配置 + 外部 I/O + 应用层行为 + refs）。
4. **若**能从代码推断清晰反例 → 写 1 条非触发场景；否则省略。
5. 构建 E1 变更点证据（符号 + 片段，非仅行号）。
6. 2b 主责构建 R1 完整链路（见 2b 流程）；其他 agent 可写初步 caller。
7. 自检：参考场景无禁止词；用户配置/外部 I/O 须有配置面或 I/O 类型 + refs；不得把内部函数调用写入外部输入输出；非触发场景（若有）有对比说明 + refs。
```

- [ ] **Step 3: 校验 T1/T2 已移除**

```bash
rg -n 'T1 顶层逻辑|映射逻辑条件编号|顶层逻辑条件' plugins/audit/skills/review/SKILL.md || echo "OK: T1 removed from shared rules"
```

Expected: 仅匹配候选格式/字段要求等待 Task 2 清理的行，或零匹配

- [ ] **Step 4: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): replace T1/T2 with T3 v3 and optional T4 in shared rules"
```

---

## Task 2: 候选格式与字段要求

**Files:**

- Modify: `plugins/audit/skills/review/SKILL.md`（约 L380–452）

- [ ] **Step 1: 替换候选缺陷输出格式中 `缺陷的触发条件` 块（L398–415）**

```markdown
- 缺陷的触发条件：
  - **参考触发场景**（≥1 条；T3 v3）：
    - **场景1**（来源：code_synth | pr_context | hybrid）
      - **用户配置**：
        - {配置面} `{键}` = `{取值}`
          - 定义/注册：path:line
          - 读取/生效：path:line
        - 或：无
      - **外部输入输出**：
        - {I/O 类型} {请求标识或来源服务} …
          - 关键参数/字段：…
          - 定义/注册：path:line
          - 传入软件：path:line
        - 或：无（纯用户配置/内部运行时触发）
      - **应用层行为**：…
    - **场景2**（…）：…
  - **非触发场景**（可选；最多 1 条）：
    - **对比说明**：相对场景1，哪项配置或外部 I/O 不同
    - **用户配置** / **外部输入输出**（只写差异项）
    - **应用层行为**：此情况下正常发生什么
```

- [ ] **Step 2: 重写 `### 缺陷的触发条件` 字段要求（L431–452）**

```markdown
### 缺陷的触发条件

须使用 **参考触发场景（T3 v3）** 作为唯一必填块；**非触发场景（T4）** 可选。模板见上文。

**禁止词**（参考场景与非触发场景均适用，含同义变体）：

- 大概、可能、也许、似乎、潜在、有一定概率、在某些情况下
- 未来、将来、若以后、一旦升级后（无当前 diff/代码依据时）
- 无主体操作：用户执行某操作后、配置不当时

**内容归属：**

| 内容 | 写入位置 |
| --- | --- |
| env / CLI / YAML / CR 用户配置 | 参考触发场景 → 用户配置 |
| 外部 HTTP/CLI/gRPC 请求 | 参考触发场景 → 外部输入输出 → 客户端输入 |
| Ray/K8s/第三方 API 响应 | 参考触发场景 → 外部输入输出 → 外部服务响应 |
| 安全/反面配置取值 | 非触发场景 → 用户配置 / 外部输入输出（可选） |
| 内部模块间函数调用 | R1-b 完整调用链（**不得**写入外部输入输出） |
| 调用链、函数分支、`ptr==nil` 落点 | R1-b / R1-c |
| validation/兜底为何未生效 | 反证检查 |
| 用户可观察的错误结果 | 应用层行为 + 造成的后果 |

若参考场景缺结构化出处、或仅裸 `key=value`、或把内部调用误作外部输入 → **不要输出**该候选缺陷。非触发场景缺失**不**影响 finding 成立；若写了非触发场景但缺对比说明或 refs → 删除非触发场景块或补全，**不**因此删除整条 finding。
```

- [ ] **Step 3: 全文件校验无遗留 T1 字段**

```bash
rg -n '顶层逻辑条件|映射条件|条件1（config|T1 v2|T1–T3' plugins/audit/skills/review/SKILL.md || echo "OK: no T1 legacy in SKILL"
```

Expected: 零匹配（Task 3/4 尚未改时可能仍有质检/约束行，Task 3/4 完成后须零匹配）

- [ ] **Step 4: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): update candidate template for T3 v3 and optional T4"
```

---

## Task 3: 阶段 3 质检 — 废弃 T1 拒收项，新增 T4

**Files:**

- Modify: `plugins/audit/skills/review/SKILL.md`（约 L697–731）

- [ ] **Step 1: 将 `### 证据与触发合规` 标题改为 `### 证据与触发合规（E1 / R1 / T3–T4，证据不足则删除）`**

- [ ] **Step 2: 替换拒收表与处理规则（L699–730）**

```markdown
| 代号 | 说明 |
| --- | --- |
| `change_evidence_symbol_missing` | E1：变更点缺符号 |
| `change_evidence_snippet_missing` | E1：变更点缺片段或仅行号 |
| `reachability_no_user_entry` | R1：无用户可见入口 |
| `reachability_chain_gap` | R1：调用链断点无法补全 |
| `trigger_function_level_only` | 参考场景仅有函数内部分支/变量，无用户可见配置或外部 I/O |
| `trigger_scenario_hedge` | 参考触发场景含禁止词 |
| `trigger_scenario_no_provenance` | T3：用户配置或外部 I/O 缺配置面/I/O 类型/定义 refs/生效 refs |
| `trigger_scenario_bare_value` | T3：仅裸 key=value 无出处 |
| `trigger_scenario_internal_as_external` | T3：内部函数调用写入外部输入输出 |
| `trigger_scenario_external_missing` | T3：代码有明确外部 API/依赖却写「无」 |
| `trigger_scenario_quant_obs_present` | T3：仍含「量化观测」字段（应删除） |
| `trigger_scenario_no_concrete_value` | T3：参考场景缺用户配置取值或外部 I/O 关键参数 |
| `non_trigger_no_contrast` | T4：非触发场景未说明与参考场景的差异 |
| `non_trigger_no_provenance` | T4：非触发场景差异项缺配置面/I/O 类型/refs |
| `non_trigger_hedge` | T4：非触发场景含禁止词 |

**处理：**

- 可修复：补全 E1 符号+片段、R1 入口+链路、T3/T4 结构化出处，删除禁止词 → 保留 finding
- T4 违规：删除非触发场景块或补全；**不**因此删除整条 finding
- 无法修复：删除 finding（不得仅润色含糊语）

处理规则：

- 成立：补充证据；将触发条件改为 T3 v3 合规参考场景（+ 可选 T4），结构化出处、无禁止词；适当修正严重性等级；
- 不成立：删除；
- 证据不足：删除。

**防漏报（合并后质检）：**

- 仅当反证后**证据不足**才可删除；**不得**因「2a/2b/2c/2d 中其他 agent 未报同一问题」而删除。
- 描述模糊但成立 → **补充**证据与触发条件，改成确定性表述；**禁止**仅润色后删除（触发条件须符合 T3 v3，禁止仅删掉禁止词而不补结构化出处）。
- 不重新全量审计；允许对单条候选 **Read 锚点函数** 核实反证（不设 Read 数量上限）。
```

- [ ] **Step 3: 校验**

```bash
rg -n 'trigger_logic_|non_trigger_|T3 v3' plugins/audit/skills/review/SKILL.md
```

Expected: 含 `non_trigger_` 三行；**无** `trigger_logic_` 匹配

- [ ] **Step 4: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): update QA codes for T3 v3 and optional T4"
```

---

## Task 4: 阶段 4 与执行约束

**Files:**

- Modify: `plugins/audit/skills/review/SKILL.md`（约 L761、L781、L843–849）

- [ ] **Step 1: 更新阶段 4 处理规则（L761）**

将：

```markdown
- 每条缺陷的 `相关代码证据` 须满足 E1 + R1；`缺陷的触发条件` 须为 T1 v2 + T3 v2 双块（用户配置 + 外部输入输出；无「量化观测」）；函数级路径仅在 R1-b 中出现。
```

改为：

```markdown
- 每条缺陷的 `相关代码证据` 须满足 E1 + R1；`缺陷的触发条件` 须含 T3 v3 参考触发场景（≥1 条；用户配置 + 外部输入输出；无「量化观测」）；非触发场景（T4）可选；函数级路径仅在 R1-b 中出现。
```

- [ ] **Step 2: 更新终稿格式注释（L781）**

将：

```markdown
- 缺陷的触发条件：（T1 v2 + T3 v2：顶层逻辑条件 + 参考触发场景，见候选格式）
```

改为：

```markdown
- 缺陷的触发条件：（T3 v3 参考触发场景 + 可选 T4 非触发场景，见候选格式）
```

- [ ] **Step 3: 更新执行约束 14–15、20（L843–849）**

将约束 14–15 替换为：

```markdown
14. 触发条件须用参考触发场景（T3 v3）表述用户侧复现路径；不得仅用函数内部状态；可选写非触发场景（T4）作反面例子。
15. 参考触发场景与非触发场景（若有）严禁含糊语；用户配置与外部 I/O 须有出处 refs；无外部 I/O 时可写「无」。
```

将约束 20 替换为：

```markdown
20. 参考场景须用「用户配置 + 外部输入输出」结构化出处（T3 v3）；内部函数调用不得写入外部输入输出；禁止「量化观测」字段；非触发场景可选且最多 1 条。
```

- [ ] **Step 4: 全量校验**

```bash
rg -n '顶层逻辑条件|映射条件|T1 v2|T1–T3|trigger_logic_' plugins/audit/skills/review/SKILL.md || echo "OK: T1 fully removed"
rg -c 'T3 v3|非触发场景|T4' plugins/audit/skills/review/SKILL.md
```

Expected: 第一命令零匹配；第二命令 count ≥8

- [ ] **Step 5: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): update stage 4 and constraints for T3 v3 and T4"
```

---

## Task 5: plugin.json 与 spec 状态

**Files:**

- Modify: `plugins/audit/.claude-plugin/plugin.json`
- Modify: `docs/superpowers/specs/2026-06-07-audit-review-trigger-simplification-design.md`

- [ ] **Step 1: bump plugin 版本与 description**

```json
{
  "name": "audit",
  "displayName": "Audit",
  "version": "0.9.7",
  "description": "对 PR/commit/diff 做缺陷审计；T3 v3 参考触发场景；可选 T4 非触发场景；E1/R1 证据出处；阶段2 同轮并行 Task（2a/2b/2c + bugfix 时 2d）",
  "keywords": ["code-review", "pr-review", "audit"],
  "license": "MIT"
}
```

- [ ] **Step 2: 更新 spec 状态**

将 design spec 头部：

```markdown
- 状态：approved（用户审阅通过，待 implementation plan）
```

改为：

```markdown
- 状态：implemented（2026-06-07，见 plan `2026-06-07-audit-review-trigger-simplification.md`）
```

- [ ] **Step 3: 最终校验**

```bash
rg -c 'T3 v3|非触发场景|T4|参考触发场景' plugins/audit/skills/review/SKILL.md
rg -n '顶层逻辑条件|映射条件|trigger_logic_' plugins/audit/skills/review/SKILL.md || echo "OK"
```

Expected: 第一命令 count ≥12；第二命令零匹配

- [ ] **Step 4: Commit**

```bash
git add plugins/audit/.claude-plugin/plugin.json docs/superpowers/specs/2026-06-07-audit-review-trigger-simplification-design.md docs/superpowers/plans/2026-06-07-audit-review-trigger-simplification.md
git commit -m "chore(audit): bump plugin to 0.9.7 and mark trigger-simplification spec implemented"
```

---

## Spec 覆盖自检

| Spec § | Task |
|--------|------|
| §3 终稿字段结构 | Task 2 |
| §4 三块职责边界 | Task 1, 2 |
| §5 T3 v3 | Task 1, 2, 4 |
| §6 T4 非触发场景 | Task 1, 2, 3, 4 |
| §7 规则代号调整 | Task 3 |
| §8 Agent 工作流 | Task 1 |
| §9 内容归属表 | Task 2 |
| §10 正反例 | Task 2（模板体现） |
| §11 SKILL 改动清单 | Task 1–4 |
| §12 验收标准 | Task 5 Step 3 |
| §13 非目标 | 未改 investigate-issue |

无 TBD/占位符。

---

## 执行选项

Plan 已保存至 `docs/superpowers/plans/2026-06-07-audit-review-trigger-simplification.md`。

**1. Subagent-Driven（推荐）** — 每个 Task 派生子 agent，任务间 review

**2. Inline Execution** — 本会话按 Task 1→5 顺序直接改 SKILL.md

请选择执行方式。
