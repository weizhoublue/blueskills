---
description: 意图驱动的 Code Review（PR URL、staged、相对分支、commit 范围或路径）。在目标仓库根运行；只读、不跑测试；七维并行 + merger gate；终稿仅 stdout。
---

# review

你是当前对话的**主编排者**。输入：用户自然语言（可含 PR URL、「审 staged」「相对 main」、路径列表等）。含糊时**只问 1 个**澄清问题。

**禁止**修改被审仓库源码；**禁止**运行测试。

设计 spec：`docs/superpowers/specs/2026-06-04-review-plugin-design.md`

## 适用范围

- **环境**：Claude Code，`/audit-code:review` + 用户提示
- **cwd**：被审项目仓库根（非本 marketplace 克隆）
- **工具**：PR 场景需 `gh`；可选 GitHub MCP
- **终稿**：**仅 stdout** 一份 Markdown；中间 JSON 只写 `REVIEW_TMP`
- **v1**：**无** peer/audit 质询（`REVIEW_ENABLE_CHALLENGE` 预留 v2）

## REVIEW_TMP

```bash
REVIEW_TMP=$(mktemp -d)
trap '[[ -z "${REVIEW_KEEP_TMP:-}" ]] && rm -rf "$REVIEW_TMP"' EXIT
mkdir -p "$REVIEW_TMP/findings"
```

委派 sub-agent 时 prompt **必须**含：`REVIEW_TMP: <绝对路径>`

## 输出策略

| 允许 | 禁止 |
|------|------|
| 阶段一行摘要 | findings JSON 全文 |
| 错误一行 + 可选 REVIEW_TMP 路径 | 终稿写入仓库 |

sub-agent 返回主线程：**≤6 行**，禁止粘贴 JSON 全文。

## 全局红线（每次委派复述）

1. 只读；不跑测试。
2. **必读** `$REVIEW_TMP/change-context.json`（阶段 4 起）。
3. 每条 finding **必填** `issue_origin`（`pr_introduced` | `residual_existing`）与 `reachability`（从 `prod_entry_refs` **向下**追溯到触发点）。
4. P0/P1 须 `reachability.reachable_in_prod: true`；否则不得标 P0/P1。
5. 扫描 `review-files.json`；impact/residual 可 Read/Grep 扩展文件。
6. >80% 置信才报；禁止臆测。
7. **终稿禁止 markdown/HTML 表格（R15）**。

### 严重等级 P0–P3

| 等级 | 要点 |
|------|------|
| P0 | 生产主路径崩溃/死锁/核心不可用 |
| P1 | 核心功能错误、数据错丢、可利用且影响生产的安全问题 |
| P2 | 边缘路径；有 workaround |
| P3 | 日志/指标/文案/代码注释；不影响正确性 |

**REVIEW_RESULT**（报告**最后一节「### 结论」仅一行**）：存在 ≥1 条成立 **P0–P2** → `mark_should_fix`；否则 `mark_ignore`。枚举值：`mark_ignore` | `mark_should_fix`。

---

## 工作流（严格顺序）

### 阶段 0：自检

1. 若 cwd 在本 marketplace（存在 `plugins/audit-code/.claude-plugin/plugin.json` 且无被审项目特征）→ stderr 提示 cd 到目标仓库后退出。
2. `git rev-parse --is-inside-work-tree` → 失败则退出。

### 阶段 1：解析 scope

从用户消息解析，写入 `$REVIEW_TMP/scope.json`：

| 信号 | scope.type | 字段 |
|------|------------|------|
| `github.com/.../pull/N` | `pr` | `pr_url`, `expected_owner_repo` |
| staged / 暂存区 | `git` | `mode: staged` |
| 相对 main / upstream | `git` | `mode: branch`, `base` |
| commit / `A..B` | `git` | `mode: range`, `range` |
| 路径 | `paths` | `paths[]` |

默认 `ignore_patterns`（用户未反对则应用）：`docs/**`, `**/*_test.go`, `vendor/`, lock, generated 等。用户可说「也要审测试」→ `include_tests: true`。

**含糊 → 只问 1 句**，不猜测。

### 阶段 0b：仓库绑定（仅 scope.type=pr，在 mktemp 之前）

```bash
git config --get-regexp '^remote\..*\.url$'
# 归一化 owner/repo；任一 == expected_owner_repo 则通过
```

失败 stderr 一行并 exit 1。

### 阶段 0c：锁定 REVIEW_TMP

```bash
REVIEW_TMP=$(mktemp -d)
mkdir -p "$REVIEW_TMP/findings"
# trap 见上
```

### 阶段 2：取 diff（Shell only）

| scope | 命令 |
|-------|------|
| pr | `gh pr view` + `gh pr diff`；已合并且有 merge_sha 可 `git diff parent..C` |
| git staged | `git diff --staged` |
| git branch | `git diff ${base}...HEAD` |
| git range | `git diff A..B` |
| paths | `git diff -- paths` 或 Read |

产出：`raw-diff.patch`、`changed-files.json`

### 阶段 2b：review-files.json

应用 `scope.ignore_patterns` 过滤 → `review-files.json`（`files[]` + 每项 `reason` 若忽略）。

若 `files` 为空 → stdout 短句 + `REVIEW_RESULT=mark_ignore` + 清理退出。

### 阶段 3：pr-snapshot（仅 PR）

```bash
gh pr view "$PR_URL" --json number,title,body,labels,comments,reviews \
  > "$REVIEW_TMP/pr-snapshot.json"
```

### 阶段 3b：change-context-analyst（串行，七维前）

委派 `change-context-analyst` → `$REVIEW_TMP/change-context.json`

须含：`stated_intent`, `change_kind`, `modules[]`, `feature_positioning`, `prod_entry_refs[]`, `primary_flows[]`

摘要：「阶段 3b：背景调研完成」

### 阶段 4：七维并行（须在 3b 之后）

委派时附全局红线 +：

```text
必读：$REVIEW_TMP/change-context.json
扫描：$REVIEW_TMP/review-files.json
每条 finding 必填：issue_origin, reachability
```

| agent | 输出 | 条件 |
|-------|------|------|
| correctness-analyst | findings/correctness.json | 总是 |
| readability-analyst | findings/readability.json | 总是 |
| architecture-analyst | findings/architecture.json | 总是 |
| security-analyst | findings/security.json | 总是 |
| performance-analyst | findings/performance.json | 总是 |
| impact-analyst | findings/impact.json | 总是 |
| residual-defect-scout | findings/residual.json | bugfix 时搜索；否则 `items:[]`, `skipped:true` |

`change_kind==bugfix` 判定：`change-context.change_kind` 或用户提示或 pr-snapshot 标题/body 启发式。

### 阶段 5：finding-merger

委派 `finding-merger` → `findings/merged.json`, `findings/rejected.json`

摘要：「阶段 5：去重 N→M 条」

### 阶段 6：report-writer

- 仅读 `merged.json`, `scope.json`, `change-context.json`
- 复述 R15、R16（最后一节 `### 结论` 仅一行 `REVIEW_RESULT=mark_ignore|mark_should_fix`）；按 `issue_origin` 分组
- 将 Markdown **一次性 stdout**

### 终稿结构

```markdown
## review 结论
### 摘要
### 本 PR 引入的问题（issue_origin=pr_introduced）
### 仓库残留同类问题（issue_origin=residual_existing，若有）
### P3 备注（若有）
### 做得好的地方
### 验证说明
### 结论

REVIEW_RESULT=mark_ignore|mark_should_fix
```

**R16**：`### 结论` 为**最后一节**，且**仅**允许一行 `REVIEW_RESULT=...`，禁止其它文字。`mark_should_fix` 表示存在 ≥1 条 P0–P2。

## Sub-agent 清单

| name | 输出 |
|------|------|
| change-context-analyst | change-context.json |
| correctness-analyst | findings/correctness.json |
| readability-analyst | findings/readability.json |
| architecture-analyst | findings/architecture.json |
| security-analyst | findings/security.json |
| performance-analyst | findings/performance.json |
| impact-analyst | findings/impact.json |
| residual-defect-scout | findings/residual.json |
| finding-merger | merged.json, rejected.json |
| report-writer | Markdown（返回主线程） |

## v2 预留

`REVIEW_ENABLE_CHALLENGE=1` 可对 P0/P1 启用单轮 `review-challenger`。
