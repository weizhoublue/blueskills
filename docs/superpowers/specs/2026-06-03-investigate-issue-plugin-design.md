# 设计文档：blueskills marketplace — `investigate-issue` 插件与 `investigate` skill

- 日期：2026-06-03
- 状态：已审阅（brainstorming 确认）
- 来源需求：[`docs/report.md`](../../report.md)
- 参考实现：[`plugins/investigate-project/agents/report-quality-challenger.md`](../../../plugins/investigate-project/agents/report-quality-challenger.md)（多层因果 + 术语清单）；[`plugins/audit/agents/audit-challenger.md`](../../../plugins/audit/agents/audit-challenger.md)（**仅借**双轮文件格式；本插件 challenger 为报告深化员，非对抗性质询）
- 运行环境：**仅 Claude Code**（`/plugin install investigate-issue@blueskills`，`/investigate-issue:investigate <问题描述>`）

## 1. 目标

针对开源项目中的**单个问题**（缺陷、行为疑问、架构/设计议题）做深度分析，产出三节 Markdown 报告：

1. **问题描述** — **业务前因后果叙事**（谁、什么场景、怎么出错）+ 兄弟分支对比；函数级调用链仅作佐证，不得作为正文主体
2. **问题后果** — 代码层后果 + 用户/功能层影响；**条件化**表述，含「何时不会出现该后果」（反向）
3. **触发条件** — **正向**（须同时满足的配置/输入/运行时状态）+ **反向**（不触发情形）；再到缺陷落点

采用 **Skill 编排 + 5 sub-agent + 整稿报告深化（全报告 ≤3 轮）**；**终稿仅 stdout**；中间 JSON 写入 `ISSUE_TMP` 临时目录。

### 1.1 与 `investigate-project` 的关键差异

| 维度 | `investigate-project` | `investigate-issue` |
| --- | --- | --- |
| 分析对象 | 整个项目的业务功能 | 单个具体问题 |
| 调用链 | **禁止**函数级调用链（R6） | **必须** C0–C4 可还原，但**终稿以业务叙事呈现**，path:line 为佐证 |
| 终稿 | 落盘 `analysis-report/` | **仅 stdout** |
| 报告深化 | 单向 issues 清单 | **双轮协作**（提问 → 补充；复用 audit 文件格式，**非对抗性质询**） |
| 范围 | 业务功能梳理 | 缺陷 + 行为疑问 + 架构/设计；**报告全文可迭代补全** |

## 2. Brainstorming 决策摘要

| 决策点 | 选择 |
| --- | --- |
| 输入 | **A** 自由文本描述问题 |
| 终稿交付 | **B** 仅 stdout |
| 中间产物 | **A** `ISSUE_TMP=$(mktemp -d)`，默认删除；`ISSUE_KEEP_TMP=1` 保留 |
| 问题范围 | **C** 缺陷 + 行为疑问 + 架构/设计；报告任一细节不足均可被深化 |
| 证据标准 | **B** 代码优先 `path:line`；设计/对比允许文档+行业常识，须显式「未能从代码确认」 |
| Agent 编制 | **C** 6 agent + 主编排 |
| 深化粒度 | **整稿** 四节初稿后统一评审 ≤3 轮（**非**每节独立多轮） |
| 协作模式 | **B** 提问清单 → writer 补充稿 → 终裁（**优化可读性**，非辩驳淘汰） |
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
├── issue-analysis.json
├── sections/
│   ├── problem-description.md
│   ├── consequences.md
│   └── trigger-conditions.md
├── challenges/
│   ├── full-report-round-<N>.json
│   └── full-report-final.json          # 仅 max_rounds_reached 时
└── rebuttals/
    └── full-report-round-<N>.json
```

**section id（固定）**：

| 中文节名 | section id |
| --- | --- |
| 问题描述 | `problem-description` |
| 问题后果 | `consequences` |
| 触发条件 | `trigger-conditions` |

### 5.3 对话内 vs stdout

| 允许（对话内） | 禁止 |
| --- | --- |
| 阶段一行摘要 | 完整 JSON / 长调用链 |
| 深化摘要（如「问题描述 2/3 complete」） | 终稿写入仓库或 ISSUE_TMP 外 |
| 错误一行 + 可选 ISSUE_TMP 路径 | |

sub-agent 返回主编排：**≤6 行**，含输出文件路径与条数。

## 6. Agent 职责

| Agent | 职责 | Write |
| --- | --- | --- |
| **issue-scout** | 解析用户自由文本；Glob/Grep 建索引；定位相关模块/配置入口/文档 | `scout.json` |
| **code-tracer** | 函数级调用链、config/env 触发路径、错误分支 | `trace.json` |
| **business-context-analyst** | 业务上下游；兄弟分支/同类模块对比 | `business-context.json` |
| **issue-writer** | 按节从 `issue-analysis.json` 扩写；按深化清单补充 | `sections/*.md`, `rebuttals/*.json` |
| **issue-challenger** | **报告深化员**：以「未读过仓库的新手能否读懂」为标准，**提问**并指出缺失的因果层/术语/证据/上下文，驱动 writer **补全**报告；非对抗性质疑 | `challenges/*.json` |

**四节与素材映射**：

- **问题描述** ← scout + trace + business
- **问题后果** ← trace + business
- **触发条件** ← trace + scout

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
  "background_knowledge": {
    "software_purpose": "",
    "domain_context": "",
    "feature_area": {"name": "", "user_visible_behavior": "", "relationship_to_issue": ""},
    "adjacent_capabilities": [{"name": "", "relationship": ""}]
  },
  "industry_terms": [{"term": "", "glossary": ""}]
}
```

`issue-writer` 扩写时不得 contradict 已有 `confirmed` 主张；新增须标 tier 或触发 analysis rollback。

## 8. 主编排工作流

```text
阶段 0   marketplace 自检 + ISSUE_TMP + issue_brief
阶段 1   issue-scout
阶段 2   [code-tracer ∥ business-context-analyst]
阶段 3   主编排合并 → issue-analysis.json
阶段 4   issue-writer（draft_all，一次写齐三节）
阶段 5   整稿 write↔challenger（≤3 轮；scope=full-report）
阶段 6   主编排组装 stdout 终稿
阶段 7   trap 清理 ISSUE_TMP
```

### 8.1 整稿 write↔challenger 循环

**`MAX_REVIEW_ROUNDS = 3`**（**整份三节报告**合计，非每节独立）。

```text
委派 issue-writer(mode=draft_all)    # 三节初稿，无 challenger
round ← 1
while round ≤ 3:
  委派 issue-challenger(scope=full-report, round)
  if resolution in [complete, partial]: break
  if resolution == needs_enrichment:
    委派 issue-writer(mode=supplement, round)
  round ← round + 1
if round==3 且仍有 blocking/major:
  challenger 写 challenges/full-report-final.json
```

### 8.2 Analysis rollback（最多 1 次）

当 **整稿第 1 轮** challenger 出现 ≥2 条 `dimension==call_chain` 且 `severity==blocking`：

1. 重委派 `code-tracer`
2. 重合并 `issue-analysis.json`
3. 重委派 `issue-writer(mode=draft_all)`
4. `round ← 1` 重新整稿评审；全 skill 最多 rollback **1 次**

## 9. `issue-challenger`：报告深化

### 9.0 角色定位（与 `audit-challenger` 的区别）

`issue-challenger` 是**报告深化员**，不是审计淘汰员。首要目标是：**让未读过仓库的读者能读懂报告**。

| 要做 | 不做 |
| --- | --- |
| 以新手读者视角**提问**：「这里缺哪一步因果？」「这个缩写是什么？」 | 以对抗心态「抓错、否决」整段报告 |
| 指出**缺失的细节**（调用链断档、背景未交代、兄弟分支未对比） | 要求 writer「证明报告错了」才能过关 |
| 给出**可执行的补充方向**（补 C2 步骤、补术语解释、补业务情境） | 空泛要求「写长一点」「再详细些」 |
| 核对证据 tier 与 refs 是否支撑已有表述 | 要求「证实」纯 `inference` 推断 |

**默认假设**：writer 初稿方向正确但**不够厚**；challenger 的职责是**优化与补全**，使四节报告层层可读。

中间产物路径仍用 `challenges/`、`rebuttals/`（与 `audit` 插件目录约定一致），语义分别为 **「深化提问清单」** 与 **「按清单补充稿」**。

### 9.1 深化检查维度

报告**任一细节不足**均可列入深化清单。每节按下列维度扫描。

### 9.2 调用链深度 C0–C4（`problem-description`、`trigger-conditions` 必查）

| 层 | 含义 | 缺失级别 |
| --- | --- | --- |
| **C0** | 用户可见入口（config/env/API/CLI/输入） | 缺 → blocking |
| **C1** | 入口 → 第一层分发/路由 | 缺 → major |
| **C2** | 中间关键分支（guard、错误处理） | 缺 → major |
| **C3** | 缺陷落点函数/分支 | 缺 → blocking |
| **C4** | 落点 → 可观察后果 | 缺 → major |

### 9.3 业务因果 B1–B5（四节均查）

| 层 | 含义 |
| --- | --- |
| **B1** | 业务情境（谁、什么部署/配置） |
| **B2** | 用户可观察的坏结果 |
| **B3** | 为何默认/兄弟路径没问题或也有隐患 |
| **B4** | 缺陷在业务流哪一段介入 |
| **B5** | 对用户功能/性能/可靠性的实际影响 |

`problem-description` / `consequences`：缺 B2 或 B4 → blocking。

### 9.4 兄弟分支对比（`problem-description` 必查）

- ≥1 个 peer 路径，或显式「未能找到可对比 peer」
- 说明「为何此处有问题、彼处没有」或「彼处也有但未触发」
- 只有断言无 refs → major

### 9.5 术语与可读性

- 专名/缩写首现须同段解释
- 连续两句 ≥2 个未解释专名 → major
- 读者检验：遮住项目名能否复述因果？不能 → major

### 9.6 证据对齐

- narrative 关键句须映射 `issue-analysis.json` 或 refs
- `confirmed` 但 refs 与主张无关 → blocking

### 9.7 架构/设计主张（范围 C）

- 设计评价须为 `inference` 或 `doc_declared`
- 标 `confirmed` 却无 code ref → blocking
- challenger **不得**要求「证实」纯 `inference` 推断

### 9.9 条件严谨性 R17（`consequences`、`trigger-conditions` 必查）

| 反模式 | 级别 |
| --- | --- |
| 单一配置/字段 = 充分条件（「X=false 即报错」） | blocking |
| 缺反向条件子节（不触发 / 何时不会出现后果） | blocking |
| 正向条件未列运行时状态（cache、fallback 等） | major |

challenger 须对关键断言做**三问**：单独是否足够？还缺什么同时条件？何时有此配置仍正常？

### 9.10 双轮协作（提问 → 补充 → 终裁）

| 步骤 | 动作 |
| --- | --- |
| 1 | challenger → `challenges/<section>-round-N.json`：列出缺失细节与**面向读者的提问**；`resolution` 多为 `needs_enrichment` |
| 2 | writer → `rebuttals/<section>-round-N.json`：逐条**补充**正文或说明为何 `issue-analysis.json` 中暂无依据；可 `clarifications` 解释补充边界 |
| 3 | 下轮或终裁：challenger 读补充稿；未读补充稿不得 `complete`；仍缺关键细节则开下一轮 |

**提问模板**（`question` 优先选用）：

1. **缺环**：读者从入口到落点还缺哪一步？请补并给 ref。
2. **缺背景**：小白不知道 `<术语>` 是什么，请同段解释其在本问题中的作用。
3. **缺对比**：兄弟路径 X 为何没出问题？请补对比或写「未能找到 peer」。
4. **缺情境**：谁在什么配置/部署下会遇到？请补 B1。
5. **读者检验**：遮住项目名，新手能否复述本节因果链？

**challenges JSON 核心字段**：

```json
{
  "section": "problem-description",
  "round": 1,
  "resolution": "needs_enrichment",
  "gaps": [{
    "severity": "blocking",
    "dimension": "call_chain|business|sibling|terminology|evidence|design",
    "question": "读者如何知道 config X 被谁读取？",
    "suggested_addition": "补 C1 步骤：…，refs: path:line"
  }],
  "enrichment_summary": null
}
```

> 兼容说明：实现时 `gaps[]` 可与 audit 系 `issues[]` 同构；字段名 `question` + `suggested_addition`（或 `required_fix`）须体现**补什么**而非**错在哪**。

| severity | 含义 | 是否触发 writer 补充 |
| --- | --- | --- |
| blocking | 缺关键环，新手无法读懂 | 是 |
| major | 缺重要背景/术语/对比 | 是 |
| informational | 可更好，非必须 | 否 |

**resolution 取值**：

- `needs_enrichment`：仍有 blocking/major 未补，进入 writer 补充轮
- `complete`：本节对新手读者已足够读懂（可有 informational）
- `partial`：第 3 轮截止，blocking/major 未全闭合，仍输出并记入 final

**max_rounds 收尾**：第 3 轮仍有 blocking/major → 写 `challenges/<section>-final.json`（`status: max_rounds_reached`）；主编排仍输出该节，附录 C 列**仍未补全的缺失项**。

## 10. 全局红线（每次委派必复述）

1. 只读分析；禁止改代码、禁止跑测试。
2. 证据优先：能 code 印证的必须 `confirmed` + `path:line`；设计判断用 `inference` 并写「未能从代码确认」。
3. 禁止编造；不确定写「未能从文档和代码中确认」。
4. **必须函数级调用链**（本插件核心，与 investigate-project R6 相反）。
5. **禁止无对比的局部分析**：`problem-description` 须含兄弟分支对比或显式说明未能找到 peer。
6. challenger 禁止 Write 分析源文件（`trace.json` 等）；仅 Write `challenges/**`。
7. writer 不得 contradict `issue-analysis.json` 中 `confirmed` 主张。
8. **协作深化**：challenger 输出缺失清单后 writer **必须**补充；challenger 未读补充稿不得 `complete`；challenger **禁止**以「质疑/否决」代替具体的缺失说明。
9. **叙事优先（R16）**：报告以业务前因后果为主体；调用链与 path:line 是分析依据，禁止 code dump（文件清单式根因分析）。
10. **条件严谨性（R17）**：后果与触发条件须正向+反向成对；禁止单一配置 = 必然触发/报错。
11. stdout 终稿禁止 markdown 表格（`| ... |`）与 HTML 表。
12. Read/Write 中间产物仅 `$ISSUE_TMP/**` + 被分析仓库只读。

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

---

## 附录 A：证据分级说明

- 已代码确认：随句 path:line 或标注 (confirmed)
- 文档声明：(doc_declared)
- 未能从代码确认：(inference) 或显式说明

## 附录 B：报告深化摘要

- 整稿深化：2/3 complete

## 附录 C：仍未补全的缺失项（若有）

- [consequences] blocking: 缺反向条件 …
```

附录 B/C 使用 bullet 列表，**禁止** `|` 表格语法。

## 12. 成功标准

读者（未读过仓库的平台/后端工程师，含新手）在读 stdout 终稿后能够：

1. **不看文件名**即可复述：业务上出了什么事、从用户配置/输入到坏结果的完整前因后果；
2. 说明业务上下游与「为何兄弟路径表现不同」；
3. 列出**条件化**的触发条件（正向须同时满足 + 反向不触发情形）与用户可见后果；
4. 理解出问题涉及哪块**用户可见功能**及触发/后果关系（非单独「背景知识」节）；
5. 需要深挖时，能从「代码佐证」或括注中找到 path:line 证据；
6. 区分哪些结论有代码证据、哪些为设计推断。

**反例（不合格）**：
- 以「根本原因：某 yaml 第 N 行某字段 = false」开篇，后跟 path:line 子弹列表，无业务叙事。
- 「trust_remote_code=false → 即报错」，未说明本地 cache、模型是否需 remote code 等反向情形。

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
