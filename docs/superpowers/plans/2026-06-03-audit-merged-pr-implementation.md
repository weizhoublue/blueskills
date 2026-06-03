# audit 插件与 audit-merged-pr Skill 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 blueskills marketplace 新增 Claude Code 插件 `audit` 与 skill `audit-merged-pr`：对已合入缺省分支的 PR 做静态审计，多 sub-agent 分析 + 逐条质询，**最终报告仅 stdout**。

**Architecture:** 主编排 Skill 用 Bash 完成 `gh`/git/commit 定位/diff 归一化，中间 JSON 写入 `AUDIT_TMP=$(mktemp -d)`；8 个 sub-agent 只读仓库 + 读写临时目录约定路径；阶段 6 质询后 **仅 P0–P2 成立项** 进入 `findings-final` 与终稿。

**Tech Stack:** Claude Code marketplace (`.claude-plugin/marketplace.json`)、plugin (`plugins/audit/.claude-plugin/plugin.json`)、`SKILL.md`、sub-agent Markdown frontmatter；工具：`Read`/`Grep`/`Glob`/`Write`(受限)/Bash(主编排)。

**Reference:** [`docs/superpowers/specs/2026-06-03-audit-pr-plugin-design.md`](../specs/2026-06-03-audit-pr-plugin-design.md)（v3+：含 effective-diff、§5.7 P0–P3、§7.1–7.2、§4.10 输出策略、P3 淘汰）。

**Conventions:**

- Plugin 内 SKILL/agent **正文中文**；frontmatter `name` 英文 kebab-case，`description` 中文。
- 无传统单测；每 task 用 **结构校验脚本** + `rg` 关键词检查替代。
- 不要复制 `investigate-project` 的 `REPORT_ROOT` / `analysis-report/` 命名。

---

## 文件结构（决策已锁定）

| 路径 | 职责 | Task |
|------|------|------|
| `.claude-plugin/marketplace.json` | 注册 `audit` 插件 | 1 |
| `plugins/audit/.claude-plugin/plugin.json` | 插件 manifest | 1 |
| `plugins/audit/skills/audit-merged-pr/SKILL.md` | 主编排（阶段 0–7） | 2–4 |
| `plugins/audit/agents/pr-intent-analyst.md` | PR 意图与 author positions | 5 |
| `plugins/audit/agents/business-accuracy-analyst.md` | 业务准确性 | 6 |
| `plugins/audit/agents/language-defect-analyst.md` | 语言/并发/性能类缺陷 | 7 |
| `plugins/audit/agents/security-analyst.md` | 安全 | 8 |
| `plugins/audit/agents/edge-effect-analyst.md` | 边缘效应 | 9 |
| `plugins/audit/agents/similar-defect-scout.md` | 同类未修（条件） | 10 |
| `plugins/audit/agents/audit-challenger.md` | 质询 ≤5 轮 + severity_review | 11 |
| `plugins/audit/agents/report-writer.md` | 终稿 Markdown（返回主线程，不写盘） | 12 |
| `docs/installation.md` | 安装与 `/audit:audit-merged-pr` 用法 | 13 |
| `scripts/verify-audit-plugin.sh` | 本地结构校验（可选但推荐） | 14 |

---

## Task 1: Marketplace 与 plugin manifest

**Files:**

- Modify: `.claude-plugin/marketplace.json`
- Create: `plugins/audit/.claude-plugin/plugin.json`

- [ ] **Step 1: 创建目录**

```bash
mkdir -p plugins/audit/.claude-plugin plugins/audit/skills/audit-merged-pr plugins/audit/agents
```

- [ ] **Step 2: 写入 `plugins/audit/.claude-plugin/plugin.json`**

```json
{
  "name": "audit",
  "displayName": "Audit",
  "version": "0.1.0",
  "description": "对已合入缺省分支的 PR 做静态审计（audit-merged-pr Skill + 八个 sub-agent，终稿 stdout）",
  "keywords": ["pr-audit", "code-review", "security"],
  "license": "MIT"
}
```

- [ ] **Step 3: 在 `marketplace.json` 的 `plugins` 数组追加**

```json
    {
      "name": "audit",
      "source": "./plugins/audit",
      "description": "Static audit of merged PRs on default branch (audit-merged-pr; final report to stdout only)."
    }
```

- [ ] **Step 4: 结构校验**

```bash
python3 -c "
import json
m=json.load(open('.claude-plugin/marketplace.json'))
names=[p['name'] for p in m['plugins']]
assert 'audit' in names
p=json.load(open('plugins/audit/.claude-plugin/plugin.json'))
assert p['name']=='audit'
print('OK', names)
"
```

Expected: `OK` 且列表含 `audit`

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/marketplace.json plugins/audit/.claude-plugin/plugin.json
git commit -m "feat(audit): add plugin manifest and marketplace entry"
```

---

## Task 2: SKILL.md — 阶段 0–2b（AUDIT_TMP、gh、commit、effective-diff）

**Files:**

- Create: `plugins/audit/skills/audit-merged-pr/SKILL.md`

- [ ] **Step 1: 写入 frontmatter 与 §0 适用范围**

```markdown
---
description: 审计已合入缺省分支的 GitHub PR（输入 PR URL）。在目标仓库根目录运行；静态分析、不跑测试；最终审计报告仅输出到 stdout。编排 pr-intent、四维分析、similar-defect-scout、audit-challenger（每条 finding 最多 5 轮）、report-writer。
---

# audit-merged-pr

你是**主编排者**。输入：`PR_URL`（命令参数或用户首条消息）。禁止修改被审仓库代码。
```

必须包含小节：

- **前置**：用户已 `cd` 仓库根、缺省分支、`gh auth` 可用。
- **阶段 0**：解析 URL；`AUDIT_TMP=$(mktemp -d)`；`trap` 清理；`AUDIT_KEEP_TMP=1` 时 stderr 提示路径。
- **§4.10 输出策略**（摘要表：允许进度一行；禁止 dump JSON/diff/log；**最终报告仅 stdout 一次**）。
- **阶段 1**：`gh pr view "$PR_URL" --json number,title,body,state,mergedAt,mergeCommit,baseRefName,headRefName,commits,comments,reviews` → `pr-context.json`。
- **阶段 2**：`git pull`；mergeCommit 本地 `cat-file` 优先；有界 `git log --grep`（每种 `-n 5`，**不得**把 log 贴进对话）→ `diff-scope.json`；最后手段 `gh pr diff` → `patch-fallback.diff`。
- **阶段 2b**：路径规则表（docs/example/test/vendor/lock/generated/ci）→ `effective-diff.json`；`effective_files` 为空则 stdout 短结论 + `fix_mark_ignore` + 清理退出。

- [ ] **Step 2: 校验 SKILL 含关键词**

```bash
rg -n 'AUDIT_TMP|mktemp|effective-diff|fix_mark_ignore|stdout' plugins/audit/skills/audit-merged-pr/SKILL.md
```

Expected: 均有匹配

- [ ] **Step 3: Commit**

```bash
git add plugins/audit/skills/audit-merged-pr/SKILL.md
git commit -m "feat(audit): add audit-merged-pr skill stages 0-2b"
```

---

## Task 3: SKILL.md — 阶段 3–5（intent、四维、similar）

**Files:**

- Modify: `plugins/audit/skills/audit-merged-pr/SKILL.md`

- [ ] **Step 1: 追加全局红线 §5 + §5.6 上游防护清单 + §5.7 P0–P3 表**

从 spec §5、§5.6、§5.7 **原文缩写粘贴**（analyst/challenger 委派时要求复述）。

- [ ] **Step 2: 阶段 3 — 委派 `pr-intent-analyst`**

Prompt 必含：`AUDIT_TMP` 绝对路径；只读 `pr-context.json`、`effective-diff.json`；Write `intent.json`。

- [ ] **Step 3: 阶段 4 — 并行委派四维 analyst**

| agent | 输出 |
|-------|------|
| business-accuracy-analyst | `findings/business.json` |
| language-defect-analyst | `findings/language.json` |
| security-analyst | `findings/security.json` |
| edge-effect-analyst | `findings/edge-effects.json` |

约束：**仅** `effective_files` 路径；finding schema 见 spec §6.4（含 `upstream_guards_considered`、`trigger.prod_entry_ref`）。

- [ ] **Step 4: 阶段 5 — 条件委派 `similar-defect-scout`**

当 `intent.pr_kind == bugfix`；输出 `findings/similar-unfixed.json`。

- [ ] **Step 5: 委派返回格式**

要求各 agent 主线程回复 **≤6 行**（条数、路径），禁止粘贴 JSON 全文（§4.10）。

- [ ] **Step 6: Commit**

```bash
git add plugins/audit/skills/audit-merged-pr/SKILL.md
git commit -m "feat(audit): skill stages 3-5 and global rubrics"
```

---

## Task 4: SKILL.md — 阶段 6–7（质询、P3 淘汰、stdout）

**Files:**

- Modify: `plugins/audit/skills/audit-merged-pr/SKILL.md`

- [ ] **Step 1: 阶段 6 伪代码（与 spec §4.8 一致）**

必须写明：

1. 合并 `findings/*.json` → 分配 `finding_id`
2. 初始 `severity==P3` → `findings-rejected`（`skip_challenge`），不进质询
3. 每条 P0–P2：`audit-challenger` 循环 ≤5 轮；`withdrawn`/`inconclusive` → rejected
4. `finalize_F`：`severity==P3` → rejected（`after_challenge`）；否则 → `survivors`
5. 写 `findings-final.json`（**仅 survivors，severity∈{P0,P1,P2}**）与 `findings-rejected.json`

- [ ] **Step 2: 阶段 7**

- 只读 `findings-final.json` 应用 `docs/README.md` 的 `fix_mark_*` 规则
- 委派 `report-writer` → 接收 Markdown **字符串**
- **一次** `stdout` 输出 §9 结构（无 llm session 节）
- `rm -rf "$AUDIT_TMP"`（除非 `AUDIT_KEEP_TMP`）

- [ ] **Step 3: 校验**

```bash
rg -n 'findings-final|p3_below_threshold|survivors|report-writer|fix_mark_should_fix' plugins/audit/skills/audit-merged-pr/SKILL.md
```

- [ ] **Step 4: Commit**

```bash
git add plugins/audit/skills/audit-merged-pr/SKILL.md
git commit -m "feat(audit): skill stages 6-7 challenger and stdout report"
```

---

## Task 5: Agent — pr-intent-analyst

**Files:**

- Create: `plugins/audit/agents/pr-intent-analyst.md`

- [ ] **Step 1: frontmatter**

```yaml
---
name: pr-intent-analyst
description: PR 意图分析员。解读 title/body/comments/reviews，提取作者声明的 waive/defer 立场，判定 pr_kind，写入 intent.json。只读 pr-context 与 effective-diff。
model: inherit
tools: Read, Write
---
```

- [ ] **Step 2: 正文必含**

- `AUDIT_TMP`：Read `pr-context.json`、`effective-diff.json`；Write **仅** `$AUDIT_TMP/intent.json`
- 输出 schema spec §6.3（`author_stated_positions[]`、`pr_kind`）
- 返回主线程 ≤6 行

- [ ] **Step 3: Commit**

```bash
git add plugins/audit/agents/pr-intent-analyst.md
git commit -m "feat(audit): add pr-intent-analyst agent"
```

---

## Task 6: Agent — business-accuracy-analyst

**Files:**

- Create: `plugins/audit/agents/business-accuracy-analyst.md`

- [ ] **Step 1: frontmatter**（`tools: Read, Grep, Glob, Write`；Write 仅 `$AUDIT_TMP/findings/business.json`）

- [ ] **Step 2: 正文必含**

- 维度：修复是否达成 PR 声明目的（spec §1 业务准确性）
- 仅审计 `effective_files`；finding §6.4；`dimension: business`
- 定级遵守 §5.7；填写 `upstream_guards_considered`
- 禁止测试/示例/文档路径

- [ ] **Step 3: Commit**

```bash
git add plugins/audit/agents/business-accuracy-analyst.md
git commit -m "feat(audit): add business-accuracy-analyst agent"
```

---

## Task 7: Agent — language-defect-analyst

**Files:**

- Create: `plugins/audit/agents/language-defect-analyst.md`

- [ ] **Step 1:** 同 Task 6 模式，输出 `findings/language.json`，维度：空指针、竞态、泄漏、性能等。

- [ ] **Step 2: Commit**

```bash
git add plugins/audit/agents/language-defect-analyst.md
git commit -m "feat(audit): add language-defect-analyst agent"
```

---

## Task 8: Agent — security-analyst

**Files:**

- Create: `plugins/audit/agents/security-analyst.md`

- [ ] **Step 1:** 输出 `findings/security.json`；强调用户可控输入路径（对齐 M9）。

- [ ] **Step 2: Commit**

```bash
git add plugins/audit/agents/security-analyst.md
git commit -m "feat(audit): add security-analyst agent"
```

---

## Task 9: Agent — edge-effect-analyst

**Files:**

- Create: `plugins/audit/agents/edge-effect-analyst.md`

- [ ] **Step 1:** 输出 `findings/edge-effects.json`；未修改业务的边际影响。

- [ ] **Step 2: Commit**

```bash
git add plugins/audit/agents/edge-effect-analyst.md
git commit -m "feat(audit): add edge-effect-analyst agent"
```

---

## Task 10: Agent — similar-defect-scout

**Files:**

- Create: `plugins/audit/agents/similar-defect-scout.md`

- [ ] **Step 1:** 仅 bugfix PR；读 intent + effective-diff；输出 `findings/similar-unfixed.json`；`problem_type` 可为 3（仓库同类缺陷）。

- [ ] **Step 2: Commit**

```bash
git add plugins/audit/agents/similar-defect-scout.md
git commit -m "feat(audit): add similar-defect-scout agent"
```

---

## Task 11: Agent — audit-challenger

**Files:**

- Create: `plugins/audit/agents/audit-challenger.md`

- [ ] **Step 1: frontmatter**（`Read, Write`；Write 仅 `$AUDIT_TMP/challenges/**`）

- [ ] **Step 2: 嵌入 spec §7.1 五条 required_evidence（编号 1–5）**

- [ ] **Step 3: 嵌入 §7.2 降级矩阵 M0–M9**（`matrix_rule_id` 必填）

- [ ] **Step 4: 每轮输出 `challenges/<finding_id>-round-N.json`**（schema §6.5，含 `severity_review`、`required_evidence_checklist`）

- [ ] **Step 5: `continue_call_chain` / `shallow_call_chain` 处理说明**

- [ ] **Step 6: 返回主线程 ≤6 行**（resolution、proposed_severity、matrix_rule_id）

- [ ] **Step 7: Commit**

```bash
git add plugins/audit/agents/audit-challenger.md
git commit -m "feat(audit): add audit-challenger with severity matrix"
```

---

## Task 12: Agent — report-writer

**Files:**

- Create: `plugins/audit/agents/report-writer.md`

- [ ] **Step 1: frontmatter**（`tools: Read` only）

- [ ] **Step 2: 正文必含**

- 只读 `$AUDIT_TMP/findings-final.json`、`pr-context.json`、`intent.json`（**不**读 rejected、原始 findings）
- 按 `docs/README.md` §报告结构生成中文 Markdown（**无** llm session）
- `AUDIT_RESULT=` 行 + should_fix 各小节
- **禁止 Write 任何文件**；在回复正文返回完整 Markdown 供主线程 stdout

- [ ] **Step 3: Commit**

```bash
git add plugins/audit/agents/report-writer.md
git commit -m "feat(audit): add report-writer agent"
```

---

## Task 13: 安装文档

**Files:**

- Modify: `docs/installation.md`

- [ ] **Step 1: 追加 `## 安装 audit` 小节**

```markdown
## 安装 audit（审计已合入 PR）

在**目标仓库根目录**、**缺省分支**（如 main）下使用：

\`\`\`text
/plugin marketplace add weizhoublue/blueskills
/plugin install audit@blueskills
/reload-plugins
\`\`\`

\`\`\`text
/audit:audit-merged-pr https://github.com/OWNER/REPO/pull/123
\`\`\`

- 需要已安装并登录 `gh`
- 最终审计报告仅输出到 stdout；中间产物在系统临时目录，默认结束后删除
```

- [ ] **Step 2: Commit**

```bash
git add docs/installation.md
git commit -m "docs: add audit plugin installation"
```

---

## Task 14: 校验脚本与终验

**Files:**

- Create: `scripts/verify-audit-plugin.sh`

- [ ] **Step 1: 写入脚本**

```bash
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

test -f plugins/audit/.claude-plugin/plugin.json
test -f plugins/audit/skills/audit-merged-pr/SKILL.md
for a in pr-intent-analyst business-accuracy-analyst language-defect-analyst \
  security-analyst edge-effect-analyst similar-defect-scout audit-challenger report-writer; do
  test -f "plugins/audit/agents/${a}.md"
done

python3 -c "
import json
m=json.load(open('.claude-plugin/marketplace.json'))
assert any(p['name']=='audit' for p in m['plugins'])
"

rg -q 'audit-merged-pr' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'findings-final' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'p3_below_threshold' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'severity_review' plugins/audit/agents/audit-challenger.md
rg -q 'matrix_rule_id' plugins/audit/agents/audit-challenger.md
rg -q 'effective-diff' plugins/audit/skills/audit-merged-pr/SKILL.md

echo "OK: audit plugin structure"
```

- [ ] **Step 2: 运行**

```bash
chmod +x scripts/verify-audit-plugin.sh
./scripts/verify-audit-plugin.sh
```

Expected: `OK: audit plugin structure`

- [ ] **Step 3: Commit**

```bash
git add scripts/verify-audit-plugin.sh
git commit -m "chore(audit): add plugin structure verify script"
```

---

## 计划自检（对照 spec）

| Spec 章节 | 覆盖 Task |
|-----------|-----------|
| 插件 audit / skill audit-merged-pr | 1, 2–4 |
| 阶段 2b effective-diff | 2 |
| 仅 Claude Code / 无 llm session | 4, 12 |
| gh 主 + git 定位 | 2 |
| §4.10 最终报告 stdout | 2, 4, 12 |
| 8 agents | 5–12 |
| §7.1 调用链证据 | 11 |
| §7.2 降级矩阵 | 11 |
| §5.7 P0–P3 | 3, 6–11 |
| 阶段 6 P3 淘汰、仅 survivors | 4, 11 |
| findings-rejected | 4 |

---

## 手工验收（实现完成后）

在任意已合入 PR 的仓库根、缺省分支：

```text
/audit:audit-merged-pr <PR_URL>
```

检查：

1. 对话内仅有简短阶段进度，无大块 JSON/diff
2. 结束时有完整 `## audit PR N 结论` 与 `AUDIT_RESULT=`
3. `AUDIT_KEEP_TMP=1` 时 `$AUDIT_TMP/findings-final.json` 中 severity 均为 P0–P2
