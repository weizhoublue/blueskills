# audit/review 证据出处与可达性追溯（E1 / R1 / T3 v2）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `audit/review` SKILL 中落地 E1（变更点符号+片段）、R1（用户可见入口+完整调用链）、T1 v2（轻量出处）、T3 v2（用户配置+外部输入输出双块、删量化观测），并扩展 2b 向上追溯职责。

**Architecture:** 仅改 `plugins/audit/skills/review/SKILL.md` 与 `plugin.json`；在现有 T1–T3 区块上增量扩展 E1/R1；2b 阶段 B 追加向上追溯；阶段 3 质检叠加拒收代号；不新增报告 `###` 子节。

**Tech Stack:** Markdown skill；`rg` 结构校验；无 pytest。

**Reference:** [`docs/superpowers/specs/2026-06-07-audit-review-evidence-provenance-design.md`](../specs/2026-06-07-audit-review-evidence-provenance-design.md)

---

## 文件结构

| 路径 | 改动 | Task |
|------|------|------|
| `plugins/audit/skills/review/SKILL.md` | E1/R1/T1 v2/T3 v2、模板、2b、质检、约束 | 1–5 |
| `plugins/audit/.claude-plugin/plugin.json` | 版本 + description | 6 |
| `docs/superpowers/specs/2026-06-07-audit-review-evidence-provenance-design.md` | 状态 → implemented | 6 |

---

## Task 1: 共享规则 — 新增 E1 / R1，升级 T1 / T3

**Files:**

- Modify: `plugins/audit/skills/review/SKILL.md`（约 L292–305，`## 触发条件规则` 整节）

- [ ] **Step 1: 将 `## 触发条件规则（T1–T3）` 替换为以下全文**

```markdown
## 证据与触发规则（E1 / R1 / T1–T3）

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

**R1 与 T1 边界：** T1 写抽象布尔前提；R1 写前提如何沿代码路径到达缺陷函数。

### T1 顶层逻辑（v2）

`缺陷的触发条件` 中的 **顶层逻辑条件** 须从用户/运维可见入口表述；每条至少含 **配置面 + 键或参数名 + refs**。**禁止**仅用函数内变量、局部分支、指针状态作为逻辑条件（那些写入 R1-b）。

### T2 场景证据

顶层逻辑条件须有代码 `path:line` 或 PR 原文依据；hedge 语不得进入逻辑条件列表。

### T3 场景具象化（v2）

顶层逻辑条件之后须提供 **参考触发场景** 块（≥1 条）。每条须含：

- 场景来源（`code_synth` / `pr_context` / `hybrid`）
- 映射逻辑条件编号
- **用户配置**（结构化条目；无则写「无」）
- **外部输入输出**（结构化条目；无则写「无（纯用户配置/内部运行时触发）」）
- **应用层行为**（用户可理解的操作结果，非函数名罗列）

**用户配置**每条：配置面、键或参数、取值、定义/注册 refs、读取/生效 refs。

**外部输入输出**分两类（按实际存在选用）：

- **外部客户端输入**：HTTP/CLI/gRPC/MQ 等外部主动发给本软件的请求
- **外部服务响应**：Ray/K8s/第三方 API 等本软件依赖的外部返回

每条条目含：I/O 类型、请求标识或来源服务、关键参数/字段与取值、定义/注册 refs、传入软件 refs。

**严禁**「大概」「可能」「未来」「某些情况下」及同义含糊语。**已删除**「量化观测」字段（后果由「造成的代码后果和业务功能后果」承担）。

**输出候选缺陷前（2a/2b/2c/2d 共享）：**

1. 从 diff/锚点提取配置键、默认值、schema、常量、外部 API 定义（Grep/Read）。
2. 从阶段 1 变更声称提取 `pr_context`（若有）。
3. 合成 ≥1 条参考场景；用户配置与外部 I/O 写结构化出处；映射逻辑条件编号。
4. 构建 E1 变更点证据（符号 + 片段，非仅行号）。
5. 2b 主责构建 R1 完整链路（见 2b 流程）；其他 agent 可写初步 caller。
6. 参考场景自检：无禁止词；用户配置/外部 I/O 须有配置面或 I/O 类型 + refs；不得把内部函数调用写入外部输入输出。
```

- [ ] **Step 2: 校验**

```bash
rg -n 'E1 变更点证据|R1 可达性证据|T3 场景具象化（v2）|用户配置|外部输入输出|量化观测' plugins/audit/skills/review/SKILL.md
```

Expected: 匹配 E1/R1/用户配置/外部输入输出；**不应**在 T3 规则行出现「量化观测」作为必填字段（legacy 引用仅在「已删除」说明中可存在）

- [ ] **Step 3: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): add E1/R1 shared rules and T3 v2 trigger structure"
```

---

## Task 2: 候选缺陷输出格式与字段要求

**Files:**

- Modify: `plugins/audit/skills/review/SKILL.md`（约 L334–393）

- [ ] **Step 1: 替换「候选缺陷输出格式」代码块为
**

将 L341–366 的 `相关代码证据` 与 `缺陷的触发条件` 部分替换为：

```markdown
- 相关代码证据：
   1. 变更点证据：（E1）
      - 文件路径：
      - 符号：
      - 行号区间：
      - 关键代码片段：（3～15 行）
      - 变更摘要：
   2. 可达性证据：（R1）
      - 用户可见入口：（配置面 + 键/参数 + refs）
      - 完整调用链：（每跳 符号 @ path:line）
      - 防护未生效原因：
- 缺陷的触发条件：
  - **顶层逻辑条件**（须同时满足；T1 + T2）：
    - 条件1（config/input）：{配置面} `{键}` … refs: path:line
    - 条件2（runtime/部署态）：… refs: path:line
  - **参考触发场景**（可评估；T3 v2）：
    - **场景1**（来源：code_synth | pr_context | hybrid）
      - **映射条件**：条件1 + 条件2
      - **用户配置**：
        - {配置面} `{键}` = `{取值}`
          - 定义/注册：path:line
          - 读取/生效：path:line
      - **外部输入输出**：
        - {I/O 类型} {请求标识或来源服务} …
          - 关键参数/字段：…
          - 定义/注册：path:line
          - 传入软件：path:line
        - 或：无（纯用户配置/内部运行时触发）
      - **应用层行为**：…
```

- [ ] **Step 2: 重写 `### 相关代码证据` 字段要求**

替换 L371–373 为：

```markdown
### 相关代码证据

必须同时满足 **E1** 与 **R1**：

- **变更点证据（E1）**：文件 + 符号 + 行号区间 + 关键片段 + 变更摘要；禁止仅行号。
- **可达性证据（R1）**：用户可见入口 + 完整调用链 + 防护未生效原因；禁止仅写一层 caller。
```

- [ ] **Step 3: 重写 `### 缺陷的触发条件` 字段要求**

替换 L375–393 中内容归属表与相关说明：

```markdown
### 缺陷的触发条件

须使用 **顶层逻辑条件（T1 v2）** + **参考触发场景（T3 v2）** 双块结构；模板见上文。

**禁止词**（逻辑条件与参考场景均适用，含同义变体）：

- 大概、可能、也许、似乎、潜在、有一定概率、在某些情况下
- 未来、将来、若以后、一旦升级后（无当前 diff/代码依据时）
- 无主体操作：用户执行某操作后、配置不当时

**内容归属：**

| 内容 | 写入位置 |
| --- | --- |
| env / CLI / YAML / CR 用户配置 | 顶层逻辑条件 / 用户配置 |
| 外部 HTTP/CLI/gRPC 请求 | 外部输入输出 → 客户端输入 |
| Ray/K8s/第三方 API 响应 | 外部输入输出 → 外部服务响应 |
| 内部模块间函数调用 | R1-b 完整调用链（**不得**写入外部输入输出） |
| 调用链、函数分支、`ptr==nil` 落点 | R1-b / R1-c |
| 用户可观察的错误结果 | 应用层行为 + 造成的后果 |

若参考场景缺结构化出处、或仅裸 `key=value`、或把内部调用误作外部输入 → **不要输出**该候选缺陷。
```

- [ ] **Step 4: 校验**

```bash
rg -n '关键代码片段|用户可见入口|用户配置|外部输入输出' plugins/audit/skills/review/SKILL.md | head -15
rg -n '软件配置|业务输入|量化观测' plugins/audit/skills/review/SKILL.md
```

Expected: 前两组有匹配；第二组 `软件配置`/`业务输入`/`量化观测` 仅出现在「已删除」说明或本 plan 不应出现的 legacy 段（Task 1 已删 T3 量化观测必填）

- [ ] **Step 5: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): update finding templates for E1 R1 T3 v2"
```

---

## Task 3: 2b 流程扩展 — 向上追溯与可达性记录

**Files:**

- Modify: `plugins/audit/skills/review/SKILL.md`（约 L444–503，2b 小节）

- [ ] **Step 1: 更新 2b 聚焦描述**

将 L448：

```markdown
**聚焦：** 以变更符号为锚的**一层**调用关系 + 兄弟/同类并行实现对比。
```

改为：

```markdown
**聚焦：** 以变更符号为锚的调用关系（含**向上追溯至用户可见入口**）+ 兄弟/同类并行实现对比；**主责**构建 R1 完整可达性链路。
```

- [ ] **Step 2: 在阶段 B「upstream caller」核实项后追加 R1 向上追溯**

在 L481 表格 upstream caller 核实项之后、`**按需扩展**` 之前插入：

```markdown
**R1 向上追溯（upstream 必填，与一层清单并行）：**

对每个缺陷候选锚点（及阶段 B 发现的具体疑点锚点）：

1. 从锚点沿 upstream **逐层** Grep/Read caller，直到：
   - 命中用户可见入口（env / CLI / YAML / CR / HTTP API / SDK 构造参数），或
   - 确认仓库内无法追溯（该 finding 标记为不可输出，写入覆盖说明）
2. 将完整链路写入候选缺陷 `可达性证据 → 完整调用链（R1-b）`；入口写入 `用户可见入口（R1-a）`。
3. 2a/2c/2d 可写初步 caller；合并时 **以 2b 的 R1 为准**。

在「扫描覆盖说明」中必填 **可达性追溯记录**：

```markdown
### 可达性追溯记录

| 锚点 | 用户可见入口 | 链路跳数 | 结论 |
|------|-------------|---------|------|
| add_dp_placement_groups | env VLLM_RAY_… + enable_elastic_ep | 3 | 完整 |
| fnX | （无） | — | 无法追溯，不输出 finding |
```
```

- [ ] **Step 3: 更新 2b 覆盖说明门禁**

在 L498–503 追加：

```markdown
- `- [ ] 可达性追溯记录已生成（含用户可见入口或「无法追溯」结论）`
- `- [ ] 输出 finding 的 R1 链路已从用户可见入口连至缺陷函数`
```

- [ ] **Step 4: 校验**

```bash
rg -n '可达性追溯记录|R1 向上追溯|以 2b 的 R1 为准' plugins/audit/skills/review/SKILL.md
```

Expected: ≥3 行匹配

- [ ] **Step 5: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): extend 2b upstream tracing for R1 reachability"
```

---

## Task 4: 阶段 3 质检 — E1/R1/T3 v2 拒收项

**Files:**

- Modify: `plugins/audit/skills/review/SKILL.md`（约 L615–634）

- [ ] **Step 1: 扩展「触发条件合规」为「证据与触发合规」并追加拒收表**

将 `### 触发条件合规（T1–T3，证据不足则删除）` 改为 `### 证据与触发合规（E1 / R1 / T1–T3，证据不足则删除）`，表格替换为：

```markdown
| 代号 | 说明 |
| --- | --- |
| `change_evidence_symbol_missing` | E1：变更点缺符号 |
| `change_evidence_snippet_missing` | E1：变更点缺片段或仅行号 |
| `reachability_no_user_entry` | R1：无用户可见入口 |
| `reachability_chain_gap` | R1：调用链断点无法补全 |
| `trigger_function_level_only` | 触发条件仅有函数内部分支/变量，无顶层 config/input |
| `trigger_logic_no_config_surface` | T1：顶层条件缺配置面或键名 |
| `trigger_scenario_hedge` | 参考触发场景含禁止词 |
| `trigger_scenario_no_provenance` | T3：用户配置或外部 I/O 缺配置面/I/O 类型/定义 refs/生效 refs |
| `trigger_scenario_bare_value` | T3：仅裸 key=value 无出处 |
| `trigger_scenario_internal_as_external` | T3：内部函数调用写入外部输入输出 |
| `trigger_scenario_external_missing` | T3：代码有明确外部 API/依赖却写「无」 |
| `trigger_scenario_quant_obs_present` | T3：仍含「量化观测」字段（应删除） |
| `trigger_scenario_no_concrete_value` | T3：参考场景缺用户配置取值或外部 I/O 关键参数 |
| `trigger_logic_hedge` | 顶层逻辑条件含 hedge 语 |
```

- [ ] **Step 2: 更新处理规则，删除量化观测相关句**

删除：

```markdown
- 量化观测：允许「未能从代码量化」；禁止「大概 N 秒」「可能降为 0」等
```

将处理规则首条改为：

```markdown
- 可修复：补全 E1 符号+片段、R1 入口+链路、T1/T3 结构化出处，删除禁止词 → 保留 finding
```

- [ ] **Step 3: 校验**

```bash
rg -n 'change_evidence_|reachability_|trigger_scenario_quant_obs|trigger_scenario_internal_as_external' plugins/audit/skills/review/SKILL.md
```

Expected: ≥8 行匹配

- [ ] **Step 4: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): add E1 R1 T3 v2 QA rejection codes"
```

---

## Task 5: 阶段 4 注释与执行约束

**Files:**

- Modify: `plugins/audit/skills/review/SKILL.md`（约 L670、L690、L737–755）

- [ ] **Step 1: 更新阶段 4 处理规则 L670**

追加：

```markdown
- 每条缺陷的 `相关代码证据` 须满足 E1 + R1；`缺陷的触发条件` 须为 T1 v2 + T3 v2 双块（用户配置 + 外部输入输出；无「量化观测」）。
```

- [ ] **Step 2: 更新终稿格式注释 L690**

将：

```markdown
- 缺陷的触发条件：（T1–T3 双块：顶层逻辑条件 + 参考触发场景，见候选格式）
```

改为：

```markdown
- 相关代码证据：（E1 变更点 + R1 可达性三块，见候选格式）
- 缺陷的触发条件：（T1 v2 + T3 v2：顶层逻辑条件 + 参考触发场景，见候选格式）
```

- [ ] **Step 3: 追加执行约束 18–20**

在 L755 后追加：

```markdown
18. 变更点证据不得仅行号；须含符号与关键代码片段（E1）。
19. 可达性证据须含用户可见入口与完整调用链（R1）；禁止仅写一层 caller。
20. 参考场景须用「用户配置 + 外部输入输出」结构化出处（T3 v2）；内部函数调用不得写入外部输入输出；禁止「量化观测」字段。
```

并更新约束 14–15：

```markdown
14. 触发条件不得仅用函数内部状态冒充顶层条件；须写 config/input 级逻辑条件（含配置面 + refs）+ 结构化参考场景。
15. 参考触发场景严禁含糊语；用户配置与外部 I/O 须有出处 refs；无外部 I/O 时可写「无」。
```

删除或替换原约束 15 中「未能从代码量化」表述。

- [ ] **Step 4: 校验**

```bash
rg -n '^18\.|^19\.|^20\.|E1 变更点|R1 可达性' plugins/audit/skills/review/SKILL.md
```

Expected: ≥4 行匹配

- [ ] **Step 5: Commit**

```bash
git add plugins/audit/skills/review/SKILL.md
git commit -m "feat(audit): update stage 4 and execution constraints for E1 R1 T3 v2"
```

---

## Task 6: plugin.json 与 spec 状态

**Files:**

- Modify: `plugins/audit/.claude-plugin/plugin.json`
- Modify: `docs/superpowers/specs/2026-06-07-audit-review-evidence-provenance-design.md`

- [ ] **Step 1: bump plugin 版本与 description**

```json
{
  "name": "audit",
  "displayName": "Audit",
  "version": "0.9.5",
  "description": "对 PR/commit/diff 做缺陷审计；E1/R1 证据出处与可达性追溯；T3 v2 用户配置+外部输入输出；阶段2 同轮并行 Task（2a/2b/2c + bugfix 时 2d）",
  "keywords": ["code-review", "pr-review", "audit"],
  "license": "MIT"
}
```

- [ ] **Step 2: 更新 spec 状态**

将 design spec 头部：

```markdown
- 状态：待审阅（brainstorming 确认）
```

改为：

```markdown
- 状态：implemented（2026-06-07，见 plan `2026-06-07-audit-review-evidence-provenance.md`）
```

- [ ] **Step 3: 全量校验**

```bash
rg -c 'E1|R1|T3 v2|用户配置|外部输入输出|可达性追溯记录' plugins/audit/skills/review/SKILL.md
rg -n '软件配置|业务输入' plugins/audit/skills/review/SKILL.md || echo "OK: no legacy field names"
rg -n '量化观测' plugins/audit/skills/review/SKILL.md || echo "OK: quant_obs fully removed"
```

Expected: 第一命令 count ≥15；legacy 字段名不存在；`量化观测` 不存在或仅在「已删除」一句（若 Task 1 写了「已删除量化观测」则允许 1 处）

- [ ] **Step 4: Commit**

```bash
git add plugins/audit/.claude-plugin/plugin.json docs/superpowers/specs/2026-06-07-audit-review-evidence-provenance-design.md docs/superpowers/plans/2026-06-07-audit-review-evidence-provenance.md
git commit -m "chore(audit): bump plugin to 0.9.5 and mark evidence-provenance spec implemented"
```

---

## Spec 覆盖自检

| Spec § | Task |
|--------|------|
| §3 E1 | Task 1, 2 |
| §4 R1 | Task 1, 2, 3 |
| §5 T1 v2 | Task 1, 2 |
| §6 T3 v2 | Task 1, 2 |
| §7 2b | Task 3 |
| §8 质检 | Task 4 |
| §10 SKILL 清单 | Task 1–5 |
| §11 验收 | Task 6 Step 3 |
| §12 非目标 | 未改 investigate-issue |

无 TBD/占位符。

---

## 执行选项

Plan 已保存至 `docs/superpowers/plans/2026-06-07-audit-review-evidence-provenance.md`。

**1. Subagent-Driven（推荐）** — 每个 Task 派生子 agent，任务间 review

**2. Inline Execution** — 本会话按 Task 1→6 顺序直接改 SKILL.md

请选择执行方式。
