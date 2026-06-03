# 设计文档：blueskills marketplace — `investigate-issue` 插件与 `investigate` skill

- 日期：2026-06-03
- 状态：已审阅（brainstorming 确认）
- 来源需求：[`docs/report.md`](../../report.md)
- 参考实现：[`plugins/investigate-project/agents/report-quality-challenger.md`](../../../plugins/investigate-project/agents/report-quality-challenger.md)、[`plugins/audit/agents/audit-challenger.md`](../../../plugins/audit/agents/audit-challenger.md)
- 运行环境：**仅 Claude Code**（`/plugin install investigate-issue@blueskills`，`/investigate-issue:investigate <问题描述>`）

## 1. 目标

针对开源项目中的**单个问题**（缺陷、行为疑问、架构/设计议题）做深度分析，产出四节 Markdown 报告：

1. **问题描述** — 函数级调用链 + 业务上下游 + 兄弟分支/同类模块对比
2. **问题后果** — 代码层后果（错误分支、数据丢失、竞态、panic 等）+ 用户/功能层影响
3. **触发条件** — 用户配置/输入 → 调用链 → 缺陷落点
4. **背景知识** — 出问题模块在整软件中的功能定位

采用 **Skill 编排 + 6 sub-agent + 双文书质审（每节 ≤3 轮）**；**终稿仅 stdout**；中间 JSON 写入 `ISSUE_TMP` 临时目录。

### 1.1 与 `investigate-project` 的关键差异

| 维度 | `investigate-project` | `investigate-issue` |
| --- | --- | --- |
| 分析对象 | 整个项目的业务功能 | 单个具体问题 |
| 调用链 | **禁止**函数级调用链（R6） | **必须** C0–C4 可还原 |
| 终稿 | 落盘 `analysis-report/` | **仅 stdout** |
| 质审 | 单向 issues 清单 | **双文书辩驳**（对标 `audit-challenger`） |
| 范围 | 业务功能梳理 | 缺陷 + 行为 + 架构/设计；**报告全文可质疑** |

## 2. Brainstorming 决策摘要

| 决策点 | 选择 |
| --- | --- |
| 输入 | **A** 自由文本描述问题 |
| 终稿交付 | **B** 仅 stdout |
| 中间产物 | **A** `ISSUE_TMP=$(mktemp -d)`，默认删除；`ISSUE_KEEP_TMP=1` 保留 |
| 问题范围 | **C** 缺陷 + 行为疑问 + 架构/设计；报告中所有内容可被审计质疑 |
| 证据标准 | **B** 代码优先 `path:line`；设计/对比允许文档+行业常识，须显式「未能从代码确认」 |
| Agent 编制 | **C** 6 agent + 主编排 |
| 质审粒度 | **B** 四节各独立 ≤3 轮（最多 12 轮） |
| 辩驳模式 | **B** challenge → rebuttal → 终裁 |
| 人工确认 | **A** 全自动，不暂停 |
| 架构方案 | **A** 分析 → 合并 JSON → 分节 write↔challenger |

## 3. 命名与仓库布局

```text
blueskills/
├── .claude-plugin/marketplace.json       # 增加 investigate-issue 条目
└── plugins/investigate-issue/
    ├── .claude-plugin/plugin.json        # name: investigate-issue
    ├── skills/investigate/SKILL.md       # /investigate-issue:investigate
    └── agents/
        ├── issue-scout.md
        ├── code-tracer.md
        ├── business-context-analyst.md
        ├── module-background-analyst.md
        ├── issue-writer.md
        └── issue-challenger.md
```

| 层级 | 标识 |
| --- | --- |
| Plugin | `investigate-issue` |
| Skill | `investigate` |
| 调用 | `/investigate-issue:investigate 当 CR 副本数为 0 时 controller panic` |

**不共用** `investigate-project` / `audit` 的 agent 文件：本插件要求函数级调用链，与 `investigate-project` R6 冲突。

## 4. 前置条件

- 用户 **`cd` 到被分析项目仓库根**（与 `report-features` 相同）。
- **阶段 0** marketplace 自检：若 cwd 在本 marketplace 克隆内且无被分析项目特征，stderr 提示后退出。
- **只读分析**：禁止修改被分析仓库；禁止跑测试（除非用户另行要求）。
- 已安装 Claude Code；无需 `gh`（无 PR URL 输入）。

## 5. `ISSUE_TMP` 与输出策略

### 5.1 创建与清理

```bash
ISSUE_TMP=$(mktemp -d)
trap '[[ -z "${ISSUE_KEEP_TMP:-}" ]] && rm -rf "$ISSUE_TMP"' EXIT
mkdir -p "$ISSUE_TMP"/{sections,challenges,rebuttals}
```

- 委派任何 sub-agent 时 prompt **必须**含：`ISSUE_TMP: <绝对路径>`
- `ISSUE_KEEP_TMP=1` 时保留目录，可向 stderr 打印路径
- **禁止**向 stdout 输出 JSON 正文或完整调用链 dump

### 5.2 目录结构

```text
ISSUE_TMP/
├── scout.json
├── trace.json
├── business-context.json
├── background.json
├── issue-analysis.json
├── sections/
│   ├── problem-description.md
│   ├── consequences.md
│   ├── trigger-conditions.md
│   └── background-knowledge.md
├── challenges/
│   ├── <section>-round-<N>.json
│   └── <section>-final.json          # 仅 max_rounds_reached 时
└── rebuttals/
    └── <section>-round-<N>.json
```

**section id（固定）**：

| 中文节名 | section id |
| --- | --- |
| 问题描述 | `problem-description` |
| 问题后果 | `consequences` |
| 触发条件 | `trigger-conditions` |
| 背景知识 | `background-knowledge` |

### 5.3 对话内 vs stdout

| 允许（对话内） | 禁止 |
| --- | --- |
| 阶段一行摘要 | 完整 JSON / 长调用链 |
| 质审摘要（如「问题描述 2/3 accepted」） | 终稿写入仓库或 ISSUE_TMP 外 |
| 错误一行 + 可选 ISSUE_TMP 路径 | |

sub-agent 返回主编排：**≤6 行**，含输出文件路径与条数。

## 6. Agent 职责

| Agent | 职责 | Write |
| --- | --- | --- |
| **issue-scout** | 解析用户自由文本；Glob/Grep 建索引；定位相关模块/配置入口/文档 | `scout.json` |
| **code-tracer** | 函数级调用链、config/env 触发路径、错误分支 | `trace.json` |
| **business-context-analyst** | 业务上下游；兄弟分支/同类模块对比 | `business-context.json` |
| **module-background-analyst** | 模块在整软件中的功能定位 | `background.json` |
| **issue-writer** | 按节从 `issue-analysis.json` 扩写；回应 challenger | `sections/*.md`, `rebuttals/*.json` |
| **issue-challenger** | 质疑因果深度、证据、术语、局部化；双文书终裁 | `challenges/*.json` |

**四节与素材映射**：

- **问题描述** ← scout + trace + business
- **问题后果** ← trace + business
- **触发条件** ← trace + scout
- **背景知识** ← background + scout

## 7. 证据模型

### 7.1 EvidenceClaim

```json
{
  "claim": "≤ 200 字主张",
  "evidence_tier": "confirmed | doc_declared | inference",
  "refs": ["pkg/foo.go:142", "docs/config.md#replicas"],
  "uncertainty_note": ""
}
```

| tier | 含义 | refs |
| --- | --- | --- |
| `confirmed` | 代码可印证 | ≥1 条 `path:line` |
| `doc_declared` | 文档/CHANGELOG/ADR | ≥1 条 doc 路径 |
| `inference` | 设计判断、行业对比、未能代码确认 | 可为 `[]`；**必须**填 `uncertainty_note`（含「未能从代码确认」） |

**红线**：

- 禁止 `inference` 标为 `confirmed`
- 禁止无 refs 的 `confirmed` / `doc_declared`
- 调用链每步须 `confirmed` + `path:line`

### 7.2 `issue-analysis.json`（主编排合并）

```json
{
  "issue_summary": "",
  "entry_points": [{"kind": "config|env|api|cli|crd", "ref": "", "description": ""}],
  "call_chain": [{"step": 1, "location": "path:line", "action": "", "refs": []}],
  "business_flow": {"upstream": [], "downstream": [], "scenario": ""},
  "sibling_comparison": [{
    "peer": "",
    "why_different": "",
    "peer_has_same_bug": "yes|no|unknown",
    "refs": []
  }],
  "consequences": {"code_level": [], "user_impact": []},
  "trigger_conditions": [{"config_or_input": "", "chain_ref": "call_chain[3]", "refs": []}],
  "module_background": {"module_role": "", "software_context": "", "refs": []}
}
```

`issue-writer` 扩写时不得 contradict 已有 `confirmed` 主张；新增须标 tier 或触发 analysis rollback。

## 8. 主编排工作流

```text
阶段 0   marketplace 自检 + ISSUE_TMP + issue_brief
阶段 1   issue-scout
阶段 2   [code-tracer ∥ business-context-analyst]   # 并行，均读 scout.json
阶段 3   module-background-analyst
阶段 4   主编排合并 → issue-analysis.json
阶段 5   四节流水线（顺序固定）：
           problem-description  → write ↔ challenger (≤3)
           consequences         → write ↔ challenger (≤3)
           trigger-conditions   → write ↔ challenger (≤3)
           background-knowledge → write ↔ challenger (≤3)
阶段 6   主编排组装 stdout 终稿
阶段 7   trap 清理 ISSUE_TMP
```

### 8.1 单节 write↔challenger 循环

**`MAX_ROUNDS_PER_SECTION = 3`**（四节独立计数，全 skill 最多 12 轮质审）。

```text
round ← 1
委派 issue-writer(section, round=1)    # 首轮写 sections/<section>.md
while round ≤ 3:
  委派 issue-challenger(section, round)
  if resolution in [accepted, withdrawn]: break
  if resolution == needs_rebuttal:
    委派 issue-writer(section, mode=rebuttal, round)
  round ← round + 1
if round==3 且仍有 blocking/major:
  challenger 写 challenges/<section>-final.json (max_rounds_reached)
```

### 8.2 Analysis rollback（最多 1 次）

当 **problem-description** 第 1 轮 challenger 出现 ≥2 条 `dimension==call_chain` 且 `severity==blocking`：

1. 重委派 `code-tracer`（附带 challenger 的 `required_fix`）
2. 重合并 `issue-analysis.json`
3. **仅重跑** `problem-description` 与 `trigger-conditions` 的 write↔challenger
4. 全 skill 最多 rollback **1 次**

## 9. `issue-challenger` 质询清单

报告中**所有内容均可质疑**。每节按下列维度扫描。

### 9.1 调用链深度 C0–C4（`problem-description`、`trigger-conditions` 必查）

| 层 | 含义 | 缺失级别 |
| --- | --- | --- |
| **C0** | 用户可见入口（config/env/API/CLI/输入） | 缺 → blocking |
| **C1** | 入口 → 第一层分发/路由 | 缺 → major |
| **C2** | 中间关键分支（guard、错误处理） | 缺 → major |
| **C3** | 缺陷落点函数/分支 | 缺 → blocking |
| **C4** | 落点 → 可观察后果 | 缺 → major |

### 9.2 业务因果 B1–B5（四节均查）

| 层 | 含义 |
| --- | --- |
| **B1** | 业务情境（谁、什么部署/配置） |
| **B2** | 用户可观察的坏结果 |
| **B3** | 为何默认/兄弟路径没问题或也有隐患 |
| **B4** | 缺陷在业务流哪一段介入 |
| **B5** | 对用户功能/性能/可靠性的实际影响 |

`problem-description` / `consequences`：缺 B2 或 B4 → blocking。

### 9.3 兄弟分支对比（`problem-description` 必查）

- ≥1 个 peer 路径，或显式「未能找到可对比 peer」
- 说明「为何此处有问题、彼处没有」或「彼处也有但未触发」
- 只有断言无 refs → major

### 9.4 术语与可读性

- 专名/缩写首现须同段解释
- 连续两句 ≥2 个未解释专名 → major
- 读者检验：遮住项目名能否复述因果？不能 → major

### 9.5 证据对齐

- narrative 关键句须映射 `issue-analysis.json` 或 refs
- `confirmed` 但 refs 与主张无关 → blocking

### 9.6 架构/设计主张（范围 C）

- 设计评价须为 `inference` 或 `doc_declared`
- 标 `confirmed` 却无 code ref → blocking
- challenger **不得**要求「证实」纯 `inference` 推断

### 9.7 双文书辩驳

| 步骤 | 动作 |
| --- | --- |
| 1 | challenger → `challenges/<section>-round-N.json`，`resolution` 多为 `needs_rebuttal` |
| 2 | writer → `rebuttals/<section>-round-N.json`，逐条回应，可 `counterclaims` |
| 3 | 下轮或终裁：challenger 读 rebuttal；未读 rebuttal 不得 `accepted`/`withdrawn` |

**challenges JSON 核心字段**：

```json
{
  "section": "problem-description",
  "round": 1,
  "resolution": "needs_rebuttal",
  "issues": [{
    "severity": "blocking",
    "dimension": "call_chain|business|sibling|terminology|evidence|design",
    "question": "",
    "required_fix": ""
  }],
  "debate_summary": null
}
```

| severity | 是否触发 writer 修订 |
| --- | --- |
| blocking | 是 |
| major | 是 |
| informational | 否 |

**max_rounds 收尾**：第 3 轮仍有 blocking/major → 写 `challenges/<section>-final.json`（`status: max_rounds_reached`）；主编排仍输出该节，附录 C 列未闭合项。

## 10. 全局红线（每次委派必复述）

1. 只读分析；禁止改代码、禁止跑测试。
2. 证据优先：能 code 印证的必须 `confirmed` + `path:line`；设计判断用 `inference` 并写「未能从代码确认」。
3. 禁止编造；不确定写「未能从文档和代码中确认」。
4. **必须函数级调用链**（本插件核心，与 investigate-project R6 相反）。
5. **禁止无对比的局部分析**：`problem-description` 须含兄弟分支对比或显式说明未能找到 peer。
6. challenger 禁止 Write 分析源文件（`trace.json` 等）；仅 Write `challenges/**`。
7. writer 不得 contradict `issue-analysis.json` 中 `confirmed` 主张。
8. 辩驳平等：challenger 出题后 writer 必须 rebuttal；challenger 未读 rebuttal 不得终裁。
9. stdout 终稿禁止 markdown 表格（`| ... |`）与 HTML 表。
10. Read/Write 中间产物仅 `$ISSUE_TMP/**` + 被分析仓库只读。

## 11. stdout 终稿模板

```markdown
# 问题分析报告

> 分析目标：<仓库名或路径>
> 问题摘要：<issue_brief 一行>

## 1. 问题描述

<sections/problem-description.md>

## 2. 问题后果

<sections/consequences.md>

## 3. 触发条件

<sections/trigger-conditions.md>

## 4. 背景知识

<sections/background-knowledge.md>

---

## 附录 A：证据分级说明

- 已代码确认：随句 path:line 或标注 (confirmed)
- 文档声明：(doc_declared)
- 未能从代码确认：(inference) 或显式说明

## 附录 B：质审摘要

- 问题描述：2/3 accepted
- 问题后果：2/3 accepted
- 触发条件：1/3 accepted
- 背景知识：3/3 accepted

## 附录 C：未闭合质询（若有）

- [problem-description] blocking: …
```

附录 B/C 使用 bullet 列表，**禁止** `|` 表格语法。

## 12. 成功标准

读者（未读过仓库的平台/后端工程师，含新手）在读 stdout 终稿后能够：

1. 复述从 config/env/输入到缺陷落点的调用链；
2. 说明业务上下游与「为何兄弟路径表现不同」；
3. 列出触发条件与用户可见后果；
4. 理解出问题模块在整软件中的位置；
5. 区分哪些结论有代码证据、哪些为设计推断。

## 13. 实现范围外（YAGNI）

- 不引入 `improvement-log`（无落盘报告）
- 不支持 PR URL / GitHub Issue URL 作为必填输入（仅自由文本；scout 可自行 Grep 关联）
- 不做跨仓库对比分析
- 不自动 fix 或提交 patch

## 14. marketplace 注册

实现阶段在 `.claude-plugin/marketplace.json` 的 `plugins[]` 追加：

```json
{
  "name": "investigate-issue",
  "source": "./plugins/investigate-issue",
  "description": "Deep-dive analysis of a single issue in an open-source repo (investigate skill; final report to stdout only)."
}
```
