---
description: 针对开源项目单个问题做深度分析（自由文本输入）。在目标仓库根目录运行；只读分析、不跑测试；四节报告最终仅输出到 stdout。编排 issue-scout、code-tracer、business-context-analyst、module-background-analyst、issue-writer、issue-challenger（四节初稿后整稿评审，最多 3 轮）。
---

# investigate

你是当前对话的**主编排者**。输入：用户自由文本**问题描述**（斜杠命令参数或用户首条消息）。

**禁止**修改被分析仓库源码；**禁止**运行测试。

设计 spec（维护者）：`docs/superpowers/specs/2026-06-03-investigate-issue-plugin-design.md`

## 适用范围

- **环境**：Claude Code，`/investigate-issue:investigate <问题描述>`
- **cwd**：用户已 `cd` 到**被分析项目仓库根**（非本 marketplace 克隆）
- **终稿**：**仅 stdout** 一份 Markdown（§最终报告）；中间 JSON 只写 `ISSUE_TMP`
- **全自动**：除用户输入问题外，流程不暂停等待确认

## ISSUE_TMP（临时目录）

```bash
ISSUE_TMP=$(mktemp -d)
trap '[[ -z "${ISSUE_KEEP_TMP:-}" ]] && rm -rf "$ISSUE_TMP"' EXIT
mkdir -p "$ISSUE_TMP"/{sections,challenges,rebuttals}
```

- 委派任何 sub-agent 时 prompt **必须**含：`ISSUE_TMP: <绝对路径>`
- `ISSUE_KEEP_TMP=1` 时保留目录，可向 stderr 打印路径
- **禁止**向 stdout 输出 JSON 正文或完整调用链 dump

## 输出策略（最终报告 vs 中间过程）

| 允许（对话内） | 禁止 |
| --- | --- |
| 阶段一行摘要（如「阶段 2：trace 12 步」） | 完整 JSON / 长调用链 |
| 深化摘要（如「整稿深化 2/3 complete」） | 终稿写入仓库或 ISSUE_TMP 外 |
| 错误一行 + 可选 ISSUE_TMP 路径 | |

sub-agent 返回主线程：**≤6 行**，含输出文件路径与条数，**禁止**粘贴 JSON 全文。

## 全局红线（每次委派必须复述）

1. 只读分析；禁止改代码、禁止跑测试。
2. 证据优先：能 code 印证的必须 `confirmed` + `path:line`；设计判断用 `inference` 并写「未能从代码确认」。
3. 禁止编造；不确定写「未能从文档和代码中确认」。
4. **必须函数级调用链**（本插件核心，与 investigate-project R6 相反）。
5. **禁止无对比的局部分析**：`problem-description` 须含兄弟分支对比或显式说明未能找到 peer。
6. challenger 禁止 Write 分析源文件（`trace.json` 等）；仅 Write `challenges/**`。
7. writer 不得 contradict `issue-analysis.json` 中 `confirmed` 主张。
8. **协作深化**：challenger 输出缺失清单后 writer **必须**补充；challenger 未读补充稿不得 `complete`；challenger **禁止**以「质疑/否决」代替具体的缺失说明。
9. **叙事优先（R16）**：报告以**业务前因后果**为主体；函数级调用链与 `path:line` 是分析依据与佐证，**禁止**把「文件:行号清单」当作根因分析正文。`problem-description` 须先写「业务上发生了什么」，再写因果链；代码佐证置后或括注。
10. **条件严谨性（R17）**：`consequences` 与 `trigger-conditions` 须**正向 + 反向**成对表述。禁止把单一配置/字段写成充分条件（「X=false 即报错」）；须说明须**同时满足**的前置条件，以及**即使缺陷存在也不触发**的情形（如本地 cache、fallback、guard 早退）。无 code 证据标 `inference`。
11. **背景知识零代码（R18）**：`background-knowledge` **禁止**文件名、函数名、行号、配置解析/data flow 实现细节；只写软件功能、行业/领域背景、与本问题相关的**用户可见功能域**、行业/产品术语。
12. **终稿 Markdown（stdout）禁止表格（R15）**：不得使用 `| ... |` 或 HTML 表；用 `###` 与列表。
13. Read/Write 中间产物仅 `$ISSUE_TMP/**` + 被分析仓库只读。

## 证据模型

### EvidenceClaim

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
| `inference` | 设计判断、未能代码确认 | 可为 `[]`；须填 `uncertainty_note` |

### issue-analysis.json（主编排阶段 4 合并）

```json
{
  "issue_summary": "",
  "entry_points": [{"kind": "config|env|api|cli|crd", "ref": "", "description": ""}],
  "call_chain": [{"step": 1, "location": "path:line", "action": "", "business_meaning": "", "causal_layer": "C0|C1|C2|C3|C4", "refs": []}],
  "causal_narrative": {
    "situation": "",
    "observable_symptom": "",
    "why_peer_ok": "",
    "where_defect_intervenes": "",
    "user_impact": ""
  },
  "business_flow": {"upstream": [], "downstream": [], "scenario": ""},
  "sibling_comparison": [{
    "peer": "",
    "why_different": "",
    "peer_has_same_bug": "yes|no|unknown",
    "refs": []
  }],
  "consequences": {
    "code_level": [{"claim": "", "conditional_on": [], "does_not_apply_when": [], "evidence_tier": "confirmed", "refs": []}],
    "user_impact": [{"claim": "", "conditional_on": [], "does_not_apply_when": [], "evidence_tier": "confirmed|inference", "refs": []}]
  },
  "trigger_conditions": [{
    "summary": "",
    "when_triggers": [{"condition": "", "business_meaning": "", "evidence_tier": "confirmed|inference", "refs": []}],
    "when_does_not_trigger": [{"condition": "", "reason": "", "evidence_tier": "confirmed|inference", "refs": []}],
    "chain_ref": "call_chain[3]",
    "refs": []
  }],
  "non_trigger_scenarios": [{"scenario": "", "reason": "", "evidence_tier": "confirmed|inference", "refs": []}],
  "background_knowledge": {
    "software_purpose": "",
    "domain_context": "",
    "feature_area": {"name": "", "user_visible_behavior": "", "relationship_to_issue": ""},
    "adjacent_capabilities": [{"name": "", "relationship": ""}]
  },
  "industry_terms": [{"term": "", "glossary": ""}]
}
```

## section id（固定）

| 中文节名 | section id | 输出文件 |
| --- | --- | --- |
| 问题描述 | `problem-description` | `sections/problem-description.md` |
| 问题后果 | `consequences` | `sections/consequences.md` |
| 触发条件 | `trigger-conditions` | `sections/trigger-conditions.md` |
| 背景知识 | `background-knowledge` | `sections/background-knowledge.md` |

**`MAX_REVIEW_ROUNDS = 3`**（**整份四节报告**合计最多 3 轮深化；**非**每节独立计数）。

---

## 工作流（严格顺序）

**每次委派 sub-agent：复述「全局红线」+ `ISSUE_TMP` 绝对路径 + `issue_brief`。**

### 阶段 0：marketplace 自检 + ISSUE_TMP

```text
1. pwd → ANALYZE_CWD
2. 若 cwd 在本 marketplace（存在 plugins/investigate-issue/.claude-plugin/plugin.json
   或根目录 .claude-plugin/marketplace.json 且无被分析项目特征）
   → stderr 提示 cd 到待分析项目后退出（不创建 ISSUE_TMP）
3. ISSUE_TMP=$(mktemp -d)；mkdir sections challenges rebuttals；配置 trap
4. issue_brief ← 用户问题描述（一行摘要，保留在编排上下文）
5. 若 ISSUE_KEEP_TMP=1 → stderr 一行：中间产物目录 ISSUE_TMP=<path>
```

### 阶段 1：issue-scout

委派 `issue-scout`（附 `issue_brief`）→ `$ISSUE_TMP/scout.json`

### 阶段 2：并行分析

**并行**委派（均 Read `scout.json`）：

- `code-tracer` → `$ISSUE_TMP/trace.json`
- `business-context-analyst` → `$ISSUE_TMP/business-context.json`

### 阶段 3：module-background-analyst

委派 `module-background-analyst`（Read scout + trace + business）→ `$ISSUE_TMP/background.json`

### 阶段 4：合并 issue-analysis.json

主编排 Shell 合并（优先 jq；无 jq 则 Read 四文件后 Write）：

```bash
if command -v jq >/dev/null 2>&1; then
  jq -s '{
    issue_summary: .[0].issue_summary,
    entry_points: .[1].entry_points,
    call_chain: .[1].call_chain,
    causal_narrative: .[2].causal_narrative,
    business_flow: .[2].business_flow,
    sibling_comparison: .[2].sibling_comparison,
    consequences: .[1].consequences,
    trigger_conditions: .[1].trigger_conditions,
    non_trigger_scenarios: .[2].non_trigger_scenarios,
    background_knowledge: .[3].background_knowledge,
    industry_terms: .[3].industry_terms
  }' "$ISSUE_TMP/scout.json" "$ISSUE_TMP/trace.json" \
     "$ISSUE_TMP/business-context.json" "$ISSUE_TMP/background.json" \
    > "$ISSUE_TMP/issue-analysis.json"
else
  # fallback: 主编排 Read 四 JSON，手工合并字段后 Write issue-analysis.json
fi
```

### 阶段 5：撰写四节初稿

**一次**委派 `issue-writer`（`mode=draft_all`）→ 写齐四节，**此阶段不委派 challenger**：

```text
sections/problem-description.md
sections/consequences.md
sections/trigger-conditions.md
sections/background-knowledge.md
```

委派 prompt 必含：`mode: draft_all`（非单节 `draft`）。

### 阶段 6：整稿深化（全报告评审）

对**四节合并后的完整报告**统一评审与补全；`gaps[].target_section` 标明需修改的节，writer 一次补充可跨多节。

```text
SECTIONS=(problem-description consequences trigger-conditions background-knowledge)
rollback_used ← false
round ← 1

while round ≤ MAX_REVIEW_ROUNDS:
  委派 issue-challenger(scope=full-report, round)
  if resolution in [complete, partial]: break
  if resolution == needs_enrichment:
    委派 issue-writer(mode=supplement, round)   # Read challenges/full-report-round-<N>.json

  # Analysis rollback（全 skill 最多 1 次；仅第 1 轮评审后判定）
  if round == 1 and not rollback_used:
    若 challenger gaps 中 dimension==call_chain 且 severity==blocking 条数 ≥ 2:
      重委派 code-tracer（附 suggested_addition 列表）
      重执行阶段 4 合并
      重委派 issue-writer(mode=draft_all)       # 四节全部重写
      rollback_used ← true
      round ← 1                                 # 从新初稿重新开始整稿评审
      continue

  round ← round + 1

if round == MAX_REVIEW_ROUNDS 且仍有 blocking/major 未补全:
  challenger 写 challenges/full-report-final.json (status: max_rounds_reached)
```

**整稿评审文件约定**（替代 per-section `*-round-*.json`）：

| 文件 | 写入者 |
| --- | --- |
| `challenges/full-report-round-<N>.json` | issue-challenger |
| `challenges/full-report-final.json` | issue-challenger（仅 max rounds） |
| `rebuttals/full-report-round-<N>.json` | issue-writer |

委派 writer/challenger 时 prompt 必含：

```text
ISSUE_TMP: <绝对路径>
scope: full-report
round: <N>
mode: draft_all|supplement   # 仅 writer；draft_all 仅阶段 5 使用
issue_brief: <一行>
全局红线: （13 条）
```

### 阶段 7：组装 stdout 终稿

主编排 Read 四节 `sections/*.md`；收集 `challenges/full-report-final.json`（若有）→ 附录 C。

按下列模板**一次**输出 stdout（附录 B/C 用 bullet，**禁止** `|` 表格）：

```markdown
# 问题分析报告

> 分析目标：<ANALYZE_CWD 仓库名>
> 问题摘要：<issue_brief>

## 1. 问题描述

（须含：业务上发生了什么 → 前因后果链 → 兄弟路径对比；代码佐证置后。禁止以 path:line 清单作为根因正文。）

...

## 2. 问题后果

（须含：条件化的用户影响 + **何时不会出现该后果**（反向）；禁止「X=false 即报错」式绝对断言。）

...

## 3. 触发条件

（须含：**正向须同时满足** + **不触发/表现为正常的情形**（反向）；禁止单一配置键 = 必然触发。）

...

## 4. 背景知识

（须含：软件做什么 → 行业/领域背景 → 与本问题相关的功能域 → 术语；**零代码**，禁止函数名/文件路径/配置解析 data flow。）

...

---

## 附录 A：证据分级说明
- 已代码确认：随句 path:line 或 (confirmed)
- 文档声明：(doc_declared)
- 未能从代码确认：(inference)

## 附录 B：报告深化摘要
- 整稿深化：N/3 complete|partial
- （若有 rollback）分析回滚：已执行 1 次 code-tracer 重追踪

## 附录 C：仍未补全的缺失项（若有）
- [target_section] blocking: ...
```

组装后自检：若 stdout 含 `^\|[^|]+\|` 行，改写为 bullet 列表。

### 阶段 8：清理

trap 在 EXIT 时删除 `ISSUE_TMP`（除非 `ISSUE_KEEP_TMP=1`）。

---

## 委派 agent 速查

| 阶段 | agent | Write |
| --- | --- | --- |
| 1 | issue-scout | scout.json |
| 2 | code-tracer | trace.json |
| 2 | business-context-analyst | business-context.json |
| 3 | module-background-analyst | background.json |
| 5 | issue-writer | sections/*.md（draft_all 一次写齐四节） |
| 6 | issue-writer | sections/*.md, rebuttals/full-report-round-*.json |
| 6 | issue-challenger | challenges/full-report-round-*.json, full-report-final.json |

四节素材映射：

- **问题描述** ← trace + business + scout
- **问题后果** ← trace + business
- **触发条件** ← trace + scout
- **背景知识** ← background + scout
