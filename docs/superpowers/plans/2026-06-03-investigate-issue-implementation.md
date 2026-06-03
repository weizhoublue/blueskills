# investigate-issue 插件与 investigate Skill 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 blueskills marketplace 新增 Claude Code 插件 `investigate-issue` 与 skill `investigate`：对用户自由文本描述的单个开源项目问题做深度分析，六 sub-agent 分工 + 四节报告深化（每节 ≤3 轮），**终稿仅 stdout**。

**Architecture:** 主编排 Skill 用 Bash 创建 `ISSUE_TMP=$(mktemp -d)`；scout → 并行 code-tracer / business-context-analyst → module-background-analyst → 主编排合并 `issue-analysis.json` → 四节 `issue-writer` ↔ `issue-challenger` 协作深化 → 主编排组装 Markdown 一次输出 stdout。`issue-challenger` 为**报告深化员**（提问补全缺失细节），非对抗性质询。

**Tech Stack:** Claude Code marketplace、plugin manifest、`SKILL.md`、sub-agent Markdown frontmatter；工具：`Read`/`Grep`/`Glob`/`Write`(受限)/Bash(主编排)。

**Reference:** [`docs/superpowers/specs/2026-06-03-investigate-issue-plugin-design.md`](../specs/2026-06-03-investigate-issue-plugin-design.md)

**Conventions:**

- Plugin 内 SKILL/agent **正文中文**；frontmatter `name` 英文 kebab-case，`description` 中文。
- 无传统单测；每 task 用 **`scripts/verify-investigate-issue-plugin.sh`** + `rg` 关键词检查。
- 使用 `ISSUE_TMP`，**禁止** `REPORT_ROOT` / `analysis-report/`（那是 investigate-project）。
- `MAX_ROUNDS_PER_SECTION = 3`；resolution 用 `needs_enrichment` / `complete` / `partial`（非 audit 的 `needs_rebuttal` / `accepted`）。

---

## 文件结构（决策已锁定）

| 路径 | 职责 | Task |
|------|------|------|
| `.claude-plugin/marketplace.json` | 注册 `investigate-issue` | 1 |
| `plugins/investigate-issue/.claude-plugin/plugin.json` | 插件 manifest | 1 |
| `plugins/investigate-issue/skills/investigate/SKILL.md` | 主编排（阶段 0–7） | 2–4 |
| `plugins/investigate-issue/agents/issue-scout.md` | 解析问题 + 索引 | 5 |
| `plugins/investigate-issue/agents/code-tracer.md` | 函数级调用链 | 6 |
| `plugins/investigate-issue/agents/business-context-analyst.md` | 业务流 + 兄弟对比 | 7 |
| `plugins/investigate-issue/agents/module-background-analyst.md` | 模块背景 | 8 |
| `plugins/investigate-issue/agents/issue-writer.md` | 四节 Markdown + 补充稿 | 9 |
| `plugins/investigate-issue/agents/issue-challenger.md` | 报告深化员 | 10 |
| `plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh` | 结构校验 | 11 |
| `docs/installation.md` | 安装与用法 | 12 |

---

## Task 1: Marketplace 与 plugin manifest

**Files:**

- Modify: `.claude-plugin/marketplace.json`
- Create: `plugins/investigate-issue/.claude-plugin/plugin.json`

- [ ] **Step 1: 创建目录**

```bash
mkdir -p plugins/investigate-issue/.claude-plugin \
  plugins/investigate-issue/skills/investigate \
  plugins/investigate-issue/agents \
  plugins/investigate-issue/scripts
```

- [ ] **Step 2: 写入 `plugins/investigate-issue/.claude-plugin/plugin.json`**

```json
{
  "name": "investigate-issue",
  "displayName": "Investigate Issue",
  "version": "0.1.0",
  "description": "针对开源项目单个问题做深度分析（investigate Skill + 六个 sub-agent，终稿 stdout）",
  "keywords": ["issue-analysis", "code-tracing", "debugging"],
  "license": "MIT"
}
```

- [ ] **Step 3: 在 `marketplace.json` 的 `plugins` 数组追加**

```json
    {
      "name": "investigate-issue",
      "source": "./plugins/investigate-issue",
      "description": "Deep-dive analysis of a single issue in an open-source repo (investigate skill; final report to stdout only)."
    }
```

- [ ] **Step 4: 结构校验**

```bash
python3 -c "
import json
m=json.load(open('.claude-plugin/marketplace.json'))
names=[p['name'] for p in m['plugins']]
assert 'investigate-issue' in names
p=json.load(open('plugins/investigate-issue/.claude-plugin/plugin.json'))
assert p['name']=='investigate-issue'
print('OK', names)
"
```

Expected: `OK` 且列表含 `investigate-issue`

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/marketplace.json plugins/investigate-issue/.claude-plugin/plugin.json
git commit -m "feat(investigate-issue): add plugin manifest and marketplace entry"
```

---

## Task 2: SKILL.md — 阶段 0–4（ISSUE_TMP、scout、并行分析、合并）

**Files:**

- Create: `plugins/investigate-issue/skills/investigate/SKILL.md`

- [ ] **Step 1: 写入 frontmatter 与 §0 适用范围**

```markdown
---
description: 针对开源项目单个问题做深度分析（自由文本输入）。在目标仓库根目录运行；只读分析、不跑测试；四节报告最终仅输出到 stdout。编排 issue-scout、code-tracer、business-context-analyst、module-background-analyst、issue-writer、issue-challenger（每节最多 3 轮报告深化）。
---

# investigate

你是**主编排者**。输入：用户自由文本**问题描述**（命令参数或首条消息）。禁止修改被分析仓库源码。
```

必须包含小节：

- **前置**：用户已 `cd` 被分析项目根；**非**本 marketplace 克隆。
- **阶段 0**：

```bash
ISSUE_TMP=$(mktemp -d)
trap '[[ -z "${ISSUE_KEEP_TMP:-}" ]] && rm -rf "$ISSUE_TMP"' EXIT
mkdir -p "$ISSUE_TMP"/{sections,challenges,rebuttals}
```

  - marketplace 自检（同 investigate-project：存在 `plugins/investigate-issue/.claude-plugin/plugin.json` 且无被分析项目特征 → stderr 退出）
  - 解析 `issue_brief`（一行摘要，保留在编排上下文）
  - stderr 一行：`分析报告中间产物：$ISSUE_TMP`（仅当 `ISSUE_KEEP_TMP=1`）

- **输出策略表**（允许：阶段摘要、深化摘要；禁止：JSON 全文 dump、终稿写盘）

- **全局红线 10 条**（从 spec §10 **原文**粘贴）

- **证据模型**（spec §7.1 EvidenceClaim + §7.2 `issue-analysis.json` schema）

- **阶段 1**：委派 `issue-scout`（prompt 含 `issue_brief` + `ISSUE_TMP`）

- **阶段 2**：**并行**委派 `code-tracer` 与 `business-context-analyst`（均 Read `scout.json`）

- **阶段 3**：委派 `module-background-analyst`（Read scout + trace + business）

- **阶段 4**：主编排 Shell/jq 合并 → `$ISSUE_TMP/issue-analysis.json`（字段见 spec §7.2）

- [ ] **Step 2: 合并伪代码（主编排阶段 4）**

```bash
# 主编排用 jq 合并（示意；实现时可手写 Read+Write）
jq -s '{
  issue_summary: .[0].issue_summary,
  entry_points: .[1].entry_points,
  call_chain: .[1].call_chain,
  business_flow: .[2].business_flow,
  sibling_comparison: .[2].sibling_comparison,
  consequences: .[1].consequences,
  trigger_conditions: .[1].trigger_conditions,
  module_background: .[3].module_background
}' "$ISSUE_TMP/scout.json" "$ISSUE_TMP/trace.json" \
   "$ISSUE_TMP/business-context.json" "$ISSUE_TMP/background.json" \
  > "$ISSUE_TMP/issue-analysis.json"
```

若未安装 jq，主编排用 Read 四文件后 Write 合并 JSON（SKILL 须写明 fallback）。

- [ ] **Step 3: 校验 SKILL 含关键词**

```bash
rg -n 'ISSUE_TMP|mktemp|issue-analysis\.json|code-tracer|business-context-analyst|MAX_ROUNDS_PER_SECTION|stdout' \
  plugins/investigate-issue/skills/investigate/SKILL.md
```

Expected: 均有匹配

- [ ] **Step 4: Commit**

```bash
git add plugins/investigate-issue/skills/investigate/SKILL.md
git commit -m "feat(investigate-issue): add investigate skill stages 0-4"
```

---

## Task 3: SKILL.md — 阶段 5（四节 write↔challenger + rollback）

**Files:**

- Modify: `plugins/investigate-issue/skills/investigate/SKILL.md`

- [ ] **Step 1: 定义 section 顺序常量**

```text
SECTIONS=(problem-description consequences trigger-conditions background-knowledge)
MAX_ROUNDS_PER_SECTION=3
```

- [ ] **Step 2: 单节循环伪代码（与 spec §8.1 一致）**

```text
for section in SECTIONS:
  round ← 1
  委派 issue-writer(section, mode=draft, round=1)
  while round ≤ MAX_ROUNDS_PER_SECTION:
    委派 issue-challenger(section, round)
    if resolution in [complete, partial]: break
    if resolution == needs_enrichment:
      委派 issue-writer(section, mode=supplement, round)
    round ← round + 1
  if round==MAX_ROUNDS_PER_SECTION 且 challenges 仍有 blocking/major:
    challenger 写 challenges/<section>-final.json
```

- [ ] **Step 3: Analysis rollback（spec §8.2，全 skill 最多 1 次）**

条件：`section==problem-description` 且 `round==1` 且 challenger `gaps` 中 `dimension==call_chain` 且 `severity==blocking` 的条数 ≥2。

动作：重委派 `code-tracer`（附 `suggested_addition` 列表）→ 重合并 `issue-analysis.json` → 仅重跑 `problem-description` 与 `trigger-conditions` 两节的阶段 5 循环。

- [ ] **Step 4: 委派 prompt 模板（阶段 5）**

每次委派 writer/challenger 必含：

```text
ISSUE_TMP: <绝对路径>
section: <section-id>
round: <N>
mode: draft|supplement   # 仅 writer
全局红线: （10 条）
```

- [ ] **Step 5: 校验**

```bash
rg -n 'needs_enrichment|complete|partial|rollback|problem-description|trigger-conditions' \
  plugins/investigate-issue/skills/investigate/SKILL.md
```

- [ ] **Step 6: Commit**

```bash
git add plugins/investigate-issue/skills/investigate/SKILL.md
git commit -m "feat(investigate-issue): skill stage 5 section enrichment loops"
```

---

## Task 4: SKILL.md — 阶段 6–7（stdout 终稿组装）

**Files:**

- Modify: `plugins/investigate-issue/skills/investigate/SKILL.md`

- [ ] **Step 1: 阶段 6 — 主编排组装 stdout**

从 `$ISSUE_TMP/sections/*.md` 读取四节；从 `$ISSUE_TMP/challenges/*-final.json`（若存在）收集附录 C；按 spec §11 模板组装。**一次**输出到 stdout。

附录 B 示例（bullet，禁表）：

```markdown
## 附录 B：报告深化摘要

- 问题描述：2/3 complete
- 问题后果：2/3 complete
- 触发条件：1/3 partial
- 背景知识：3/3 complete
```

- [ ] **Step 2: 阶段 7 — 清理**

trap 在 EXIT 时删除 `ISSUE_TMP`（除非 `ISSUE_KEEP_TMP=1`）。

- [ ] **Step 3: 校验终稿禁表**

SKILL 须写明：组装后 `grep -E '^\|[^|]+\|'`` 自检失败则主编排改写为 bullet 列表。

- [ ] **Step 4: Commit**

```bash
git add plugins/investigate-issue/skills/investigate/SKILL.md
git commit -m "feat(investigate-issue): skill stages 6-7 stdout assembly"
```

---

## Task 5: Agent — issue-scout

**Files:**

- Create: `plugins/investigate-issue/agents/issue-scout.md`

- [ ] **Step 1: frontmatter**

```yaml
---
name: issue-scout
description: 问题信息搜集员。解析用户自由文本问题；Glob/Grep 建索引；定位相关模块、配置入口、文档与初始代码路径。禁止编造；未能确认须明示。Write 仅 scout.json。
model: inherit
tools: Read, Grep, Glob, Bash
---
```

- [ ] **Step 2: 正文必含**

- `ISSUE_TMP`：Write **仅** `$ISSUE_TMP/scout.json`
- 输入：主线程传入 `issue_brief`（用户原文）
- Read 预算：默认 ≤ **40** 次（每次 ≤200 行）；Grep ≤15；Glob ≤10
- 排除：`test/`、`tests/`、`vendor/`、`node_modules/`、`.github/`（同 investigate-project）
- **输出 schema**：

```json
{
  "issue_summary": "对用户问题的理解（≤150字）",
  "keywords": ["panic", "replica", "controller"],
  "candidate_modules": [{"name": "", "code_paths": [], "doc_paths": [], "rationale": ""}],
  "entry_point_hints": [{"kind": "config|env|api|cli|crd", "hint": "", "refs": []}],
  "related_docs": [{"path": "", "relevance": ""}],
  "open_questions": ["未能从文档和代码中确认：…"]
}
```

- 返回主线程 ≤6 行（含 `scout.json` 路径、candidate_modules 条数）

- [ ] **Step 3: Commit**

```bash
git add plugins/investigate-issue/agents/issue-scout.md
git commit -m "feat(investigate-issue): add issue-scout agent"
```

---

## Task 6: Agent — code-tracer

**Files:**

- Create: `plugins/investigate-issue/agents/code-tracer.md`

- [ ] **Step 1: frontmatter**

```yaml
---
name: code-tracer
description: 代码追踪员。基于 scout.json 追踪函数级调用链、config/env 触发路径、错误分支与后果。每步须 path:line 证据；禁止凭空推断。Write 仅 trace.json。
model: inherit
tools: Read, Grep, Glob, Write
---
```

- [ ] **Step 2: 正文必含**

- Read：`$ISSUE_TMP/scout.json` + 被分析仓库
- Write：**仅** `$ISSUE_TMP/trace.json`
- **必须输出函数级调用链**（与 investigate-project R6 **相反**）
- C0–C4 检查清单（spec §9.2）写入 agent 正文
- **输出 schema**：

```json
{
  "entry_points": [{"kind": "config|env|api|cli|crd", "ref": "path or key", "description": "", "refs": ["path:line"]}],
  "call_chain": [{"step": 1, "location": "path:line", "function": "", "action": "", "refs": ["path:line"]}],
  "defect_site": {"location": "path:line", "branch_or_condition": "", "refs": []},
  "consequences": {
    "code_level": [{"claim": "", "evidence_tier": "confirmed", "refs": ["path:line"]}],
    "user_impact": [{"claim": "", "evidence_tier": "confirmed|inference", "refs": [], "uncertainty_note": ""}]
  },
  "trigger_conditions": [{"config_or_input": "", "chain_ref": "call_chain[N]", "refs": ["path:line"]}],
  "unverified": ["未能从文档和代码中确认：…"]
}
```

- rollback 模式：主线程可附 `enrichment_gaps[]`（来自 challenger），须优先补全 call_chain

- [ ] **Step 3: Commit**

```bash
git add plugins/investigate-issue/agents/code-tracer.md
git commit -m "feat(investigate-issue): add code-tracer agent"
```

---

## Task 7: Agent — business-context-analyst

**Files:**

- Create: `plugins/investigate-issue/agents/business-context-analyst.md`

- [ ] **Step 1: frontmatter**

```yaml
---
name: business-context-analyst
description: 业务上下文分析员。梳理问题在业务流中的上下游；对比兄弟分支/同类模块（为何此处有问题、彼处没有或也有隐患）。Write 仅 business-context.json。
model: inherit
tools: Read, Grep, Glob, Write
---
```

- [ ] **Step 2: 正文必含**

- Read：`scout.json`；可选读 `trace.json` 若已存在（并行阶段仅 scout）
- Write：`$ISSUE_TMP/business-context.json`
- B1–B5 业务因果层（spec §9.3）
- **兄弟分支对比必填**（≥1 peer 或显式 `peer_not_found: true`）
- **输出 schema**：

```json
{
  "business_flow": {
    "upstream": [{"claim": "", "evidence_tier": "confirmed|doc_declared|inference", "refs": [], "uncertainty_note": ""}],
    "downstream": [],
    "scenario": ""
  },
  "sibling_comparison": [{
    "peer": "模块/路径/功能名",
    "why_different": "",
    "peer_has_same_bug": "yes|no|unknown",
    "evidence_tier": "confirmed|inference",
    "refs": [],
    "uncertainty_note": ""
  }],
  "peer_not_found": false,
  "peer_not_found_reason": ""
}
```

- [ ] **Step 3: Commit**

```bash
git add plugins/investigate-issue/agents/business-context-analyst.md
git commit -m "feat(investigate-issue): add business-context-analyst agent"
```

---

## Task 8: Agent — module-background-analyst

**Files:**

- Create: `plugins/investigate-issue/agents/module-background-analyst.md`

- [ ] **Step 1: frontmatter**

```yaml
---
name: module-background-analyst
description: 模块背景分析员。说明出问题模块在整软件中的功能定位、与相邻模块关系。Write 仅 background.json。
model: inherit
tools: Read, Grep, Glob, Write
---
```

- [ ] **Step 2: 正文必含**

- Read：`scout.json`、`trace.json`、`business-context.json`
- Write：`$ISSUE_TMP/background.json`
- **输出 schema**：

```json
{
  "module_background": {
    "module_role": "",
    "software_context": "",
    "adjacent_modules": [{"name": "", "relationship": "", "refs": []}],
    "refs": ["docs/...", "path:line"]
  },
  "terms": [{"term": "", "glossary": "是什么 + 在本上下文中的作用"}]
}
```

- [ ] **Step 3: Commit**

```bash
git add plugins/investigate-issue/agents/module-background-analyst.md
git commit -m "feat(investigate-issue): add module-background-analyst agent"
```

---

## Task 9: Agent — issue-writer

**Files:**

- Create: `plugins/investigate-issue/agents/issue-writer.md`

- [ ] **Step 1: frontmatter**

```yaml
---
name: issue-writer
description: 问题报告撰写员。从 issue-analysis.json 扩写四节 Markdown；按 issue-challenger 深化清单补充缺失细节。Write 仅 sections/ 与 rebuttals/。
model: inherit
tools: Read, Write
---
```

- [ ] **Step 2: 正文必含**

- Read：`$ISSUE_TMP/issue-analysis.json`、当轮 `challenges/<section>-round-N.json`（supplement 模式）
- Write：
  - `$ISSUE_TMP/sections/<section>.md`
  - `$ISSUE_TMP/rebuttals/<section>-round-N.json`（supplement 模式）
- **禁止** contradict `issue-analysis.json` 中 `confirmed` 主张
- **禁止** markdown 表格
- 四节内容指引（spec §6 映射）：

| section | 必含要素 |
|---------|----------|
| `problem-description` | 调用链 C0–C4、业务上下游、兄弟对比 |
| `consequences` | code_level + user_impact 两层 |
| `trigger-conditions` | 配置/输入 → 链 → 落点 |
| `background-knowledge` | 模块角色 + 术语首现解释 |

- **rebuttals schema**：

```json
{
  "section": "problem-description",
  "round": 1,
  "responses": [{"gap_id": 0, "action": "supplemented|cannot_supplement", "text": "", "refs": []}],
  "clarifications": ["为何 analysis 中暂无某细节"]
}
```

- [ ] **Step 3: Commit**

```bash
git add plugins/investigate-issue/agents/issue-writer.md
git commit -m "feat(investigate-issue): add issue-writer agent"
```

---

## Task 10: Agent — issue-challenger（报告深化员）

**Files:**

- Create: `plugins/investigate-issue/agents/issue-challenger.md`

- [ ] **Step 1: frontmatter**

```yaml
---
name: issue-challenger
description: 报告深化员（非对抗性质询）。以新手读者能否读懂为标准，提问并指出缺失的因果层/术语/证据，驱动 issue-writer 补全。Write 仅 challenges/。
model: inherit
tools: Read, Write
---
```

- [ ] **Step 2: 角色定位（spec §9.0 原文缩写入 agent 开头）**

必含「要做 / 不做」表；强调**默认初稿方向正确但不够厚**。

- [ ] **Step 3: 深化清单**

- C0–C4、B1–B5、兄弟对比、术语、证据对齐、设计主张（spec §9.2–§9.7）
- 提问模板 5 条（spec §9.8）
- **禁止**空泛「写长一点」；`suggested_addition` 须指明补哪一层、补什么

- [ ] **Step 4: challenges JSON schema**

```json
{
  "section": "problem-description",
  "round": 1,
  "resolution": "needs_enrichment",
  "gaps": [{
    "severity": "blocking",
    "dimension": "call_chain",
    "question": "读者如何知道 config X 被谁读取？",
    "suggested_addition": "补 C1：… refs path:line"
  }],
  "enrichment_summary": null
}
```

- `resolution`: `needs_enrichment` | `complete` | `partial`
- 第 3 轮仍有 blocking/major → 额外 Write `challenges/<section>-final.json`：

```json
{"section": "...", "status": "max_rounds_reached", "unresolved_gaps": [...]}
```

- 未读当轮 `rebuttals/` 不得 `complete`

- [ ] **Step 5: Commit**

```bash
git add plugins/investigate-issue/agents/issue-challenger.md
git commit -m "feat(investigate-issue): add issue-challenger report enricher agent"
```

---

## Task 11: 校验脚本 verify-investigate-issue-plugin.sh

**Files:**

- Create: `plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh`

- [ ] **Step 1: 写入脚本**

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
err() { echo "ERROR: $*" >&2; fail=$((fail + 1)); }

# manifest
[[ -f "$ROOT/.claude-plugin/plugin.json" ]] || err "missing plugin.json"
python3 -c "import json; assert json.load(open('$ROOT/.claude-plugin/plugin.json'))['name']=='investigate-issue'"

# skill
SKILL="$ROOT/skills/investigate/SKILL.md"
[[ -f "$SKILL" ]] || err "missing SKILL.md"
for kw in ISSUE_TMP mktemp issue-analysis.json MAX_ROUNDS_PER_SECTION needs_enrichment stdout; do
  grep -q "$kw" "$SKILL" || err "SKILL missing: $kw"
done

# agents
for a in issue-scout code-tracer business-context-analyst module-background-analyst issue-writer issue-challenger; do
  [[ -f "$ROOT/agents/${a}.md" ]] || err "missing agent: $a"
done

# challenger must say 深化员 or 报告深化
grep -qE '深化|补全' "$ROOT/agents/issue-challenger.md" || err "challenger missing enricher role"

# marketplace
python3 -c "
import json
m=json.load(open('.claude-plugin/marketplace.json'))
assert any(p['name']=='investigate-issue' for p in m['plugins'])
"

[[ $fail -eq 0 ]] && echo "verify OK" || { echo "verify FAILED: $fail"; exit 1; }
```

- [ ] **Step 2: 可执行并运行**

```bash
chmod +x plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh
./plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh
```

Expected: `verify OK`（Task 1–10 完成后）

- [ ] **Step 3: Commit**

```bash
git add plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh
git commit -m "feat(investigate-issue): add plugin structure verify script"
```

---

## Task 12: 文档 docs/installation.md

**Files:**

- Modify: `docs/installation.md`

- [ ] **Step 1: 追加章节**

```markdown
## 安装 investigate-issue（单问题深度分析）

在 Claude Code 中：

\`\`\`
/plugin install investigate-issue@blueskills
\`\`\`

用法（先 `cd` 到待分析开源项目根目录）：

\`\`\`
/investigate-issue:investigate 当 CR 副本数为 0 时 controller panic
\`\`\`

终稿报告仅输出到 stdout；中间 JSON 在临时目录（`ISSUE_KEEP_TMP=1` 可保留）。
```

- [ ] **Step 2: Commit**

```bash
git add docs/installation.md
git commit -m "docs: add investigate-issue installation section"
```

---

## Task 13: 整体验收

- [ ] **Step 1: 运行校验脚本**

```bash
./plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh
```

Expected: `verify OK`

- [ ] **Step 2: 关键词交叉检查**

```bash
rg -l 'REPORT_ROOT|analysis-report' plugins/investigate-issue/ && echo UNEXPECTED || echo OK no investigate-project paths
rg -n 'needs_rebuttal|accepted|withdrawn' plugins/investigate-issue/ && echo WARN audit vocabulary || echo OK resolution vocabulary
rg -n '报告深化|needs_enrichment|complete|partial' plugins/investigate-issue/
```

Expected: 无 `REPORT_ROOT`；resolution 用 investigate-issue 词汇

- [ ] **Step 3: 人工 smoke（可选）**

在任意小型开源仓库根目录运行 `/investigate-issue:investigate <简单问题>`，确认：

1. stderr 无 marketplace 误报
2. stdout 含四节 + 附录 A/B
3. stdout 无 `| ... |` 表格行

- [ ] **Step 4: Commit（若有 smoke 修复）**

```bash
git status
# 若有修复
git add -A plugins/investigate-issue/
git commit -m "fix(investigate-issue): address smoke test findings"
```

---

## Spec 覆盖自检

| Spec 章节 | 对应 Task |
|-----------|-----------|
| §1 四节报告 | Task 4, 9 |
| §5 ISSUE_TMP | Task 2 |
| §6 Agent 职责 | Task 5–10 |
| §7 证据模型 | Task 2, 6–9 |
| §8 工作流 + rollback | Task 2–4 |
| §9 报告深化员 + C0–C4/B1–B5 | Task 10 |
| §10 全局红线 | Task 2 |
| §11 stdout 模板 | Task 4 |
| §14 marketplace | Task 1 |
| §13 YAGNI（无 improvement-log） | 全 plan 未引入 |

---

## 执行交接

Plan 已保存至 `docs/superpowers/plans/2026-06-03-investigate-issue-implementation.md`。

**两种执行方式：**

1. **Subagent-Driven（推荐）** — 每 Task 派发独立 subagent，Task 间人工/主编排 review
2. **Inline Execution** — 本会话按 Task 顺序直接实现，每 2–3 Task 设 checkpoint

请选择哪种方式开始实现。
