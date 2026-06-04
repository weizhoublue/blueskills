# audit-code 插件与 review Skill 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `audit-code` 插件（skill `review`）：意图驱动 Code Review；**七维**并行（含 bugfix 专用 residual）；每条 finding 含 `issue_origin` + 顶层入口 `reachability`；merger gate；终稿 stdout + `REVIEW_RESULT`。

**Architecture:** `change-context-analyst`（含 `prod_entry_refs`）→ **7 维并行**（residual 仅 bugfix）→ `finding-merger`（去重、可达性降级、ECC gate）→ `report-writer`（按来源分组）。v1 无质询。

**Tech Stack:** Claude Code marketplace、plugin manifest、`SKILL.md`、sub-agent Markdown frontmatter；工具：`Read`/`Grep`/`Glob`/`Write`(受限)/Bash(主编排)；PR 场景用 `gh`。

**Reference:** [`docs/superpowers/specs/2026-06-04-review-plugin-design.md`](../specs/2026-06-04-review-plugin-design.md)

**Conventions:**

- Plugin 内 SKILL/agent **正文中文**；frontmatter `name` 英文 kebab-case，`description` 中文。
- 无 pytest；用 **`scripts/verify-audit-code-plugin.sh`** + `rg` 关键词检查。
- 与 `audit` **并存**；不修改 `plugins/audit/*`（除非 marketplace 一条 JSON）。
- 临时目录变量名 **`REVIEW_TMP`**（勿用 `AUDIT_TMP`）。

---

## 文件结构（决策已锁定）

| 路径 | 职责 | Task |
|------|------|------|
| `.claude-plugin/marketplace.json` | 注册 `review` | 1 |
| `plugins/audit-code/.claude-plugin/plugin.json` | 插件 manifest | 1 |
| `plugins/audit-code/skills/review/SKILL.md` | 主编排（阶段 0–6） | 2–4 |
| `plugins/audit-code/agents/change-context-analyst.md` | 六维前：意图+模块+定位 | 5 |
| `plugins/audit-code/agents/correctness-analyst.md` | 正确性 | 6 |
| `plugins/audit-code/agents/readability-analyst.md` | 可读性 | 7 |
| `plugins/audit-code/agents/architecture-analyst.md` | 架构 | 8 |
| `plugins/audit-code/agents/security-analyst.md` | 安全 | 9 |
| `plugins/audit-code/agents/performance-analyst.md` | 性能 | 10 |
| `plugins/audit-code/agents/impact-analyst.md` | 影响面（本 PR 波及） | 11 |
| `plugins/audit-code/agents/residual-defect-scout.md` | 第 7 维：bugfix 仓库残留 | 12 |
| `plugins/audit-code/agents/finding-merger.md` | 去重 + 可达性 + ECC Gate | 13 |
| `plugins/audit-code/agents/report-writer.md` | stdout 终稿（按来源分组） | 14 |
| `docs/installation.md` | 安装与用法 | 15 |
| `scripts/verify-audit-code-plugin.sh` | 结构校验 | 16 |

---

## Task 1: Marketplace 与 plugin manifest

**Files:**

- Modify: `.claude-plugin/marketplace.json`
- Create: `plugins/audit-code/.claude-plugin/plugin.json`

- [ ] **Step 1: 创建目录**

```bash
mkdir -p plugins/audit-code/.claude-plugin plugins/audit-code/skills/review plugins/audit-code/agents
```

- [ ] **Step 2: 写入 `plugins/audit-code/.claude-plugin/plugin.json`**

```json
{
  "name": "audit-code",
  "displayName": "Audit Code",
  "version": "0.1.0",
  "description": "意图驱动的通用 Code Review（PR / 本地 diff / 路径）；六维并行 + merger gate；终稿 stdout",
  "keywords": ["code-review", "pr-review", "security"],
  "license": "MIT"
}
```

- [ ] **Step 3: 在 `marketplace.json` 的 `plugins` 数组追加**

```json
    {
      "name": "audit-code",
      "source": "./plugins/audit-code",
      "description": "Intent-driven code review (PR, local git diff, paths); six-axis analysts + merger gate; stdout only."
    }
```

- [ ] **Step 4: 结构校验**

```bash
python3 -c "
import json
m=json.load(open('.claude-plugin/marketplace.json'))
names=[p['name'] for p in m['plugins']]
assert 'audit-code' in names
p=json.load(open('plugins/audit-code/.claude-plugin/plugin.json'))
assert p['name']=='audit-code'
print('OK', names)
"
```

Expected: `OK` 且列表含 `review`

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/marketplace.json plugins/audit-code/.claude-plugin/plugin.json
git commit -m "feat(audit-code): add plugin manifest and marketplace entry"
```

---

## Task 2: SKILL.md — 阶段 0–2b（REVIEW_TMP、scope、diff、review-files）

**Files:**

- Create: `plugins/audit-code/skills/review/SKILL.md`

- [ ] **Step 1: frontmatter 与 §适用范围**

```markdown
---
description: 意图驱动的 Code Review（PR URL、staged、相对分支、commit 范围或路径）。在目标仓库根运行；只读、不跑测试；终稿仅 stdout。编排六维 analyst、finding-merger、report-writer。
---

# review

你是**主编排者**。输入：用户自然语言（可含 PR URL、审 staged、相对 main、路径等）。禁止修改被审仓库代码；禁止运行测试。

设计 spec：`docs/superpowers/specs/2026-06-04-review-plugin-design.md`
```

必须包含：

- 环境：`/audit-code:review`；cwd 为被审仓库根
- marketplace 自检：存在 `plugins/audit-code/.claude-plugin/plugin.json` 且无被审项目特征 → stderr 退出
- `REVIEW_TMP` + `trap` + `REVIEW_KEEP_TMP`
- 输出策略表（终稿 stdout；中间 JSON 不进对话）

- [ ] **Step 2: 阶段 0–1 scope 解析**

必须写明：

- 从用户消息解析 `scope.type`：`pr` | `git` | `paths`
- PR URL 正则 → `pr_url`、`expected_owner_repo`
- git modes：`staged` | `branch` | `range`
- **含糊时只问 1 个澄清问题**，不得猜测
- 写入 `$REVIEW_TMP/scope.json`（字段见 spec §5）

- [ ] **Step 3: 阶段 0b 仓库绑定（仅 `scope.type=pr`）**

复用 audit 逻辑（Shell only，在 mktemp 之前）：

```bash
git rev-parse --is-inside-work-tree
git config --get-regexp '^remote\..*\.url$'
# 归一化 owner/repo，任一 == expected_owner_repo 则通过
```

失败 stderr 一行并 exit 1。

- [ ] **Step 4: 阶段 2 取 diff（Shell only）**

| scope.type | 命令倾向 |
|------------|----------|
| pr | `gh pr view` + `gh pr diff`；已合并且有 merge_sha 时可 `git diff parent..C` |
| git staged | `git diff --staged` |
| git branch | `git diff ${base}...HEAD` |
| git range | `git diff A..B` |
| paths | `git diff -- <paths>` 或 Read |

产出：`raw-diff.patch`、`changed-files.json`

- [ ] **Step 5: 阶段 2b `review-files.json`**

- 默认 `ignore_patterns`（spec §5）：docs、vendor、lock、generated、tests（除非 `include_tests: true`）
- 用户提示可覆盖（「也要审测试」）
- 若列表为空 → stdout 短句 + `REVIEW_RESULT=fix_mark_ignore` + 清理退出

- [ ] **Step 6: 校验关键词**

```bash
rg -q 'REVIEW_TMP' plugins/audit-code/skills/review/SKILL.md
rg -q 'scope.json' plugins/audit-code/skills/review/SKILL.md
rg -q '只问 1' plugins/audit-code/skills/review/SKILL.md
rg -q 'review-files.json' plugins/audit-code/skills/review/SKILL.md
rg -q 'expected_owner_repo' plugins/audit-code/skills/review/SKILL.md
```

- [ ] **Step 7: Commit**

```bash
git add plugins/audit-code/skills/review/SKILL.md
git commit -m "feat(audit-code): add SKILL orchestration phases 0-2b"
```

---

## Task 3: SKILL.md — 阶段 3–3b–4（PR 快照、背景调研、七维并行）

**Files:**

- Modify: `plugins/audit-code/skills/review/SKILL.md`

- [ ] **Step 1: 阶段 3 pr-snapshot（仅 `scope.type=pr`）**

主编排 Shell：

```bash
gh pr view "$PR_URL" --json number,title,body,labels,comments,reviews \
  > "$REVIEW_TMP/pr-snapshot.json"
```

非 PR 跳过。不在此阶段做深度代码调研。

- [ ] **Step 2: 阶段 3b change-context-analyst（六维前，串行）**

委派 `change-context-analyst` → `$REVIEW_TMP/change-context.json`

委派 prompt 必须含：

```text
AUDIT_TMP 等价 REVIEW_TMP: <绝对路径>
Read: scope.json, review-files.json, pr-snapshot.json（若存在）, raw-diff.patch（或主编排提供的 diff 摘要 ≤2KB）
Write 仅: change-context.json
产出：修改意图、涉及模块、功能在项目中的定位（见 spec §7.0）
```

向用户一行摘要：「阶段 3b：背景调研完成，模块数 M」

- [ ] **Step 3: 全局红线（每次委派复述）**

1. 只读；不跑测试
2. 必读 `change-context.json`；扫描 `review-files.json`（impact/residual 可扩展）
3. 每条 finding **必填** `issue_origin`（`pr_introduced`|`residual_existing`）与 `reachability`（从 `prod_entry_refs` 向下追溯，见 spec §8.0）
4. P0/P1 须 `reachable_in_prod: true`，否则不得上报为该级别
5. 遵守 ECC 误报清单（finding-merger）
6. sub-agent 返回 ≤6 行

- [ ] **Step 4: 阶段 4 七维并行（须在 3b 完成后）**

| agent | 输出 | 条件 |
|-------|------|------|
| correctness-analyst | findings/correctness.json | 总是 |
| readability-analyst | findings/readability.json | 总是 |
| architecture-analyst | findings/architecture.json | 总是 |
| security-analyst | findings/security.json | 总是 |
| performance-analyst | findings/performance.json | 总是 |
| impact-analyst | findings/impact.json | 总是 |
| residual-defect-scout | findings/residual.json | `change_kind==bugfix` 等，否则 `items:[]` |

委派 prompt **必须**含：

```text
REVIEW_TMP: <绝对路径>
必读：change-context.json（含 prod_entry_refs）
扫描：review-files.json
每条 finding 必填：issue_origin, reachability（从生产入口向下追溯）
```

若 `change_kind != bugfix`：仍委派 residual-defect-scout，prompt 注明「跳过搜索，写空 items」。

- [ ] **Step 5: 明确 v1 无质询**

SKILL 中写：**禁止**委派 audit-challenger / peer-parity / rebuttals（v2 `REVIEW_ENABLE_CHALLENGE` 预留一句即可）。

- [ ] **Step 6: Commit**

```bash
git add plugins/audit-code/skills/review/SKILL.md
git commit -m "feat(audit-code): add pr-snapshot, change-context, seven-axis parallel"
```

---

## Task 4: SKILL.md — 阶段 5–6（merger、REVIEW_RESULT、report）

**Files:**

- Modify: `plugins/audit-code/skills/review/SKILL.md`

- [ ] **Step 1: 阶段 5 finding-merger**

- 输入：六维 `findings/*.json`
- 输出：`findings/merged.json`、`findings/rejected.json`
- 一行用户摘要：「阶段 5：去重 N→M 条」

- [ ] **Step 2: REVIEW_RESULT 规则**

```text
merged.json 中 severity ∈ {P0,P1,P2} 且 gate 通过 ≥1 → fix_mark_should_fix
否则 → fix_mark_ignore
P3 不进 REVIEW_RESULT 判定
```

- [ ] **Step 3: 阶段 6 report-writer**

- 读 `merged.json`、`scope.json`、`change-context.json`（`pr-snapshot.json` 可选）
- 复述 **R15**：终稿禁止 markdown/HTML 表格
- 主编排将返回的 Markdown **一次性 stdout**

- [ ] **Step 4: 终稿结构**

必须含：`## review 结论`、`REVIEW_RESULT=`、问题列表、做得好的地方、验证说明

- [ ] **Step 5: Sub-agent 清单表**（10 个 name）

- [ ] **Step 6: Commit**

```bash
git add plugins/audit-code/skills/review/SKILL.md
git commit -m "feat(audit-code): add merger, REVIEW_RESULT, and report phases"
```

---

## Task 5: change-context-analyst

**Files:**

- Create: `plugins/audit-code/agents/change-context-analyst.md`

- [ ] **Step 1: frontmatter**

```yaml
---
name: change-context-analyst
description: 变更背景调研员。六维审查前：修改意图、涉及模块、功能在项目中的定位。输出 change-context.json。
model: inherit
tools: Read, Grep, Glob, Write
---
```

- [ ] **Step 2: 正文必须包含的小节**

1. **修改意图**：`user_stated_goal`、PR title/body、commit message 摘要
2. **涉及模块**：从 `review-files` 反推；`modules[]` 含 `role_in_project`、`neighbors`
3. **项目内定位**：`feature_positioning`、`primary_flows[]`
4. **输出 schema**：spec §7.0.2；**必须**含 `prod_entry_refs[]`、`primary_flows[]`
5. **禁止编造**：`open_questions[]`；未知用 `unknown`
6. Read ≤35, Grep ≤25；Write 仅 `change-context.json`

- [ ] **Step 3: Commit**

```bash
git add plugins/audit-code/agents/change-context-analyst.md
git commit -m "feat(audit-code): add change-context-analyst agent"
```

---

## Task 6: correctness-analyst

**Files:**

- Create: `plugins/audit-code/agents/correctness-analyst.md`

- [ ] **Step 1: frontmatter**

```yaml
---
name: correctness-analyst
description: 正确性审查员。逻辑、边界、错误路径、与测试意图一致性（不执行测试）。仅 review-files。输出 findings/correctness.json。
model: inherit
tools: Read, Grep, Glob, Write
---
```

- [ ] **Step 2: 正文要点**

- **先 Read** `$REVIEW_TMP/change-context.json`，再读 `review-files.json`
- Write **仅** `$REVIEW_TMP/findings/correctness.json`
- 先读相关测试文件**内容**（不运行）以理解意图
- finding schema（spec §10）：`issue_origin`、`reachability` 必填；`id` 前缀 `C-`；`dimension`: `correctness`
- Read ≤40, Grep ≤30
- ECC：>80% 置信才报；禁止臆测
- 返回主线程模板（≤6 行）

- [ ] **Step 3: Commit**

```bash
git add plugins/audit-code/agents/correctness-analyst.md
git commit -m "feat(audit-code): add correctness-analyst agent"
```

---

## Task 7: readability-analyst

**Files:**

- Create: `plugins/audit-code/agents/readability-analyst.md`

- [ ] **Step 1:** 同 Task 6 结构；必读 `change-context.json`；`id` 前缀 `R-`；`dimension`: `readability`；Write `findings/readability.json`

- [ ] **Step 2: Commit**

```bash
git add plugins/audit-code/agents/readability-analyst.md
git commit -m "feat(audit-code): add readability-analyst agent"
```

---

## Task 8: architecture-analyst

**Files:**

- Create: `plugins/audit-code/agents/architecture-analyst.md`

- [ ] **Step 1:** `id` 前缀 `A-`；模式一致性、模块边界、依赖方向、重复代码；读项目 `CLAUDE.md` / 规则若存在

- [ ] **Step 2: Commit**

```bash
git add plugins/audit-code/agents/architecture-analyst.md
git commit -m "feat(audit-code): add architecture-analyst agent"
```

---

## Task 9: security-analyst

**Files:**

- Create: `plugins/audit-code/agents/security-analyst.md`

- [ ] **Step 1:** `id` 前缀 `S-`；嵌入 ECC Security CRITICAL 清单（硬编码密钥、SQL 拼接、XSS、路径遍历、鉴权缺失等）

- [ ] **Step 2:** 无用户可控路径则最高 P3 或不报

- [ ] **Step 3: Commit**

```bash
git add plugins/audit-code/agents/security-analyst.md
git commit -m "feat(audit-code): add security-analyst agent"
```

---

## Task 10: performance-analyst

**Files:**

- Create: `plugins/audit-code/agents/performance-analyst.md`

- [ ] **Step 1:** `id` 前缀 `P-`；N+1、无界查询、热路径、React 重渲染（若适用）

- [ ] **Step 2: Commit**

```bash
git add plugins/audit-code/agents/performance-analyst.md
git commit -m "feat(audit-code): add performance-analyst agent"
```

---

## Task 11: impact-analyst

**Files:**

- Create: `plugins/audit-code/agents/impact-analyst.md`

- [ ] **Step 1:** 第 6 维：本 PR **改动波及**（兄弟路径/调用链/配置）；`issue_origin` 多为 `pr_introduced`；必读 `change-context` + §8.0 `reachability`；Read≤60 Grep≤40；`impact` 字段见 spec §8.3

- [ ] **Step 2: Commit**

```bash
git add plugins/audit-code/agents/impact-analyst.md
git commit -m "feat(audit-code): add impact-analyst agent"
```

---

## Task 12: residual-defect-scout

**Files:**

- Create: `plugins/audit-code/agents/residual-defect-scout.md`

- [ ] **Step 1: frontmatter**

```yaml
---
name: residual-defect-scout
description: 第 7 维。仅 bugfix：在仓库内找与本 PR 修复模式相同但未修的位置。仅 issue_origin=residual_existing。输出 findings/residual.json。
model: inherit
tools: Read, Grep, Glob, Write
---
```

- [ ] **Step 2: 正文（借鉴 audit similar-defect-scout）**

- 仅当 `change-context.change_kind==bugfix`（或主编排标明启用）；否则 `items:[]`, `skipped:true`
- 提取 `fix_pattern_summary`、`pr_fix_pattern_ref`
- 全仓库 Grep 同类未修：`unfixed_evidence_refs[]`
- **所有 finding**：`issue_origin: residual_existing`（固定）；`dimension: residual`
- **reachability 必填**；`reachable_in_prod:false` 不得 P0/P1
- Write 仅 `findings/residual.json`；Read≤50 Grep≤45

- [ ] **Step 3: Commit**

```bash
git add plugins/audit-code/agents/residual-defect-scout.md
git commit -m "feat(audit-code): add residual-defect-scout agent"
```

---

## Task 13: finding-merger

**Files:**

- Create: `plugins/audit-code/agents/finding-merger.md`

- [ ] **Step 1: tools 仅 Read, Write**；Read `change-context.json`

- [ ] **Step 2: 去重规则 D1–D4（写入正文）**

- 键：file + line÷20 + 标题归一化
- 多维同源：合并 `dimensions[]`
- residual vs impact 同根因：保留 residual（spec §9.1）

- [ ] **Step 3: 可达性 Gate**

- 缺 `issue_origin` 或 `reachability` → `gate_failed`
- `reachable_in_prod:false` 且 severity P0/P1 → 降至 P2 或 `unreachable_in_prod`

- [ ] **Step 4: ECC Pre-Report Gate**

1. path:line  2. failure_mode  3. context_read  4. P0/P1 guard 不足

不通过 → `rejected.json`

- [ ] **Step 5: 误报黑名单（ECC 节选，完整列表写入 agent）**

至少包含：空泛 error handling、内部函数重复 validation、非加密 Math.random、测试 fixture hardcode、未读 yield 全文的 two_phase 断言。

- [ ] **Step 6: 输出 schema**

`merged.json`: `{ "version": 1, "items": [...] }`  
`rejected.json`: `{ "version": 1, "items": [{ "reject_reason": "gate_failed|false_positive|duplicate", ... }] }`

- [ ] **Step 7: Commit**

```bash
git add plugins/audit-code/agents/finding-merger.md
git commit -m "feat(audit-code): add finding-merger with reachability and ECC gate"
```

---

## Task 14: report-writer

**Files:**

- Create: `plugins/audit-code/agents/report-writer.md`

- [ ] **Step 1: 仅 Read；不写盘**（返回 Markdown 字符串给主线程）

- [ ] **Step 2: 模板（spec §11.2）** — 分「本 PR 引入」「仓库残留」两小节列出 finding

```markdown
## review 结论

REVIEW_RESULT=fix_mark_ignore|fix_mark_should_fix

### 摘要
...

### 问题列表
（按 P0→P1→P2；禁止 | 表格）

### P3 备注（若有）

### 做得好的地方
（至少 1 条）

### 验证说明
```

- [ ] **Step 3: R15 硬性**

正文含：**禁止** markdown 表格与 HTML table；`peer_path` 类内容用嵌套列表。

- [ ] **Step 4: Commit**

```bash
git add plugins/audit-code/agents/report-writer.md
git commit -m "feat(audit-code): add report-writer agent"
```

---

## Task 15: 文档 installation.md

**Files:**

- Modify: `docs/installation.md`

- [ ] **Step 1: 新增 `## review` 节**

含：

```bash
/plugin install audit-code@blueskills
/audit-code:review 审一下当前 staged 改动
/audit-code:review https://github.com/OWNER/REPO/pull/42
/audit-code:review 相对 upstream/main 的 diff，忽略 vendor
```

- [ ] **Step 2: 与 audit 对比表（3 行）**

| | audit | review |
|---|--------|--------|
| 输入 | 已合入 PR URL 为主 | 意图驱动，PR + 本地 |
| 质询 | 多轮 | v1 无 |
| 场景 | 事后审计 | 通用 review |

- [ ] **Step 3: Commit**

```bash
git add docs/installation.md
git commit -m "docs: add review plugin installation"
```

---

## Task 16: verify-audit-code-plugin.sh

**Files:**

- Create: `scripts/verify-audit-code-plugin.sh`

- [ ] **Step 1: 写入脚本**

```bash
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

test -f plugins/audit-code/.claude-plugin/plugin.json
test -f plugins/audit-code/skills/review/SKILL.md
for a in change-context-analyst correctness-analyst readability-analyst architecture-analyst \
  security-analyst performance-analyst impact-analyst residual-defect-scout \
  finding-merger report-writer; do
  test -f "plugins/audit-code/agents/${a}.md"
done

python3 -c "
import json
m=json.load(open('.claude-plugin/marketplace.json'))
assert any(p['name']=='audit-code' for p in m['plugins'])
"

rg -q 'REVIEW_TMP' plugins/audit-code/skills/review/SKILL.md
rg -q 'scope.json' plugins/audit-code/skills/review/SKILL.md
rg -q 'review-files.json' plugins/audit-code/skills/review/SKILL.md
rg -q '只问 1' plugins/audit-code/skills/review/SKILL.md
rg -q 'finding-merger' plugins/audit-code/skills/review/SKILL.md
rg -q 'REVIEW_RESULT' plugins/audit-code/skills/review/SKILL.md
rg -q 'fix_mark_should_fix' plugins/audit-code/skills/review/SKILL.md
rg -q 'fix_mark_ignore' plugins/audit-code/skills/review/SKILL.md
rg -q 'REVIEW_ENABLE_CHALLENGE' plugins/audit-code/skills/review/SKILL.md
rg -q 'change-context-analyst' plugins/audit-code/skills/review/SKILL.md
rg -q 'change-context.json' plugins/audit-code/skills/review/SKILL.md
rg -q '阶段 3b' plugins/audit-code/skills/review/SKILL.md
rg -q 'feature_positioning' plugins/audit-code/agents/change-context-analyst.md
rg -q '必读' plugins/audit-code/agents/correctness-analyst.md
rg -q 'change-context.json' plugins/audit-code/agents/correctness-analyst.md
rg -q 'residual-defect-scout' plugins/audit-code/skills/review/SKILL.md
rg -q 'issue_origin' plugins/audit-code/skills/review/SKILL.md
rg -q 'reachability' plugins/audit-code/skills/review/SKILL.md
rg -q 'prod_entry_refs' plugins/audit-code/agents/change-context-analyst.md
rg -q 'issue_origin' plugins/audit-code/agents/correctness-analyst.md
rg -q 'reachable_in_prod' plugins/audit-code/agents/finding-merger.md
rg -q 'residual_existing' plugins/audit-code/agents/residual-defect-scout.md
rg -q 'impact-analyst' plugins/audit-code/skills/review/SKILL.md
rg -q 'peer_path' plugins/audit-code/agents/impact-analyst.md
rg -q 'call_chain' plugins/audit-code/agents/impact-analyst.md
rg -q 'Pre-Report Gate' plugins/audit-code/agents/finding-merger.md
rg -q 'failure_mode' plugins/audit-code/agents/finding-merger.md
rg -q 'rejected.json' plugins/audit-code/agents/finding-merger.md
rg -q 'R15' plugins/audit-code/agents/report-writer.md
rg -q '禁止' plugins/audit-code/agents/report-writer.md
rg ! rg -q 'audit-challenger' plugins/audit-code/skills/review/SKILL.md || { echo "SKILL must not reference audit-challenger in v1"; exit 1; }
rg ! rg -q 'peer-parity' plugins/audit-code/skills/review/SKILL.md || { echo "SKILL must not reference peer-parity in v1"; exit 1; }

chmod +x scripts/verify-audit-code-plugin.sh
echo "OK: review plugin structure"
```

- [ ] **Step 2: 运行**

```bash
./scripts/verify-audit-code-plugin.sh
```

Expected: `OK: review plugin structure`

- [ ] **Step 3: Commit**

```bash
git add scripts/verify-audit-code-plugin.sh
git commit -m "chore(review): add verify-audit-code-plugin.sh"
```

---

## Plan 自检（2026-06-04）

| Spec 章节 | 对应 Task |
|-----------|-----------|
| §1 目标四则 | 全计划 Goal |
| §5 意图 scope | Task 2 |
| §6 阶段 0–6（含 3b） | Task 2–4 |
| §7 change-context | Task 5 |
| §8 七维 analyst | Task 6–12 |
| §8.0 issue_origin + reachability | Task 3 红线, Task 6–12, Task 13 |
| §9 merger | Task 13 |
| §10 schema | Task 6, 12 |
| §11 REVIEW_RESULT + 报告 | Task 4, 13 |
| §13 v2 预留 | Task 3, 15 |
| §15 验收 | Task 14, 15 + 手工 smoke |

- [x] 无 TBD 占位
- [x] v1 SKILL 不含质询 agent
- [x] change-context + 七维 residual（Task 5, 12）
- [x] issue_origin + reachability（Task 3, 6–13）
- [x] 与 audit 文件隔离

---

## 手工 Smoke（实施后）

在任意 Go/TS 仓库根：

1. `/audit-code:review` + 「审 staged」→ 应有 scope + 报告或零 finding
2. PR URL → `REVIEW_RESULT` 行存在
3. `REVIEW_KEEP_TMP=1` → stderr 打印临时目录，含 `findings/merged.json`
