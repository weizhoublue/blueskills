# 设计文档：blueskills marketplace — `audit` 插件与 `audit-pr` skill

- 日期：2026-06-03
- 状态：待用户审阅
- 来源需求：[`docs/README.md`](../../README.md)（PR 静态审计经验与报告结构；**不含** llm 会话 / resume CLI 一节）
- 运行环境：**仅 Claude Code**（`/plugin install audit@blueskills`，`/audit:audit-pr <PR_URL>`）

## 1. 目标

将既有 PR 审计经验固化为可重复执行的 **Skill 编排 + 多 sub-agent**，实现：

1. 从 **PR URL** 获取元数据与评论（`gh` 为主，GitHub MCP 兜底）。
2. 在 **本地缺省分支**（如 `main`）上定位已合入 PR 的 **commit / diff**（本地 `git` 优先，API 拉 patch 为最后手段）。
3. **多视角** 静态发现缺陷（业务 / 语言 / 安全 / 边缘 / 可选同类未修）。
4. **`audit-challenger` 对每条 finding 最多 5 轮质疑**，重点：更深调用链与上下游、作者有意为之则撤回或降级。
5. **最终报告仅 stdout**；进程内用 **系统临时目录** 传递结构化中间产物，结束即删除。

## 2. 命名与仓库布局

```text
blueskills/
├── .claude-plugin/marketplace.json    # 增加 audit 插件条目
└── plugins/audit/
    ├── .claude-plugin/plugin.json     # name: audit
    ├── skills/audit-pr/SKILL.md       # /audit:audit-pr
    └── agents/
        ├── pr-intent-analyst.md
        ├── business-accuracy-analyst.md
        ├── language-defect-analyst.md
        ├── security-analyst.md
        ├── edge-effect-analyst.md
        ├── similar-defect-scout.md
        ├── audit-challenger.md
        └── report-writer.md
```

| 层级 | 标识 |
|------|------|
| Plugin | `audit` |
| Skill | `audit-pr` |
| 调用 | `/audit:audit-pr https://github.com/owner/repo/pull/123` |

## 3. 前置条件与用户职责

- 用户 **`cd` 到目标仓库根**（与 `report-features` 相同）。
- 当前分支应为 **缺省分支**（`main` / `master` 等）；skill **不自动 checkout 其它分支**，仅对当前分支执行 `git pull`（或 `git pull --ff-only`）尝试更新。
- 已安装并登录 **`gh`**；可选配置 GitHub MCP 作搜索兜底。
- **禁止**修改代码、**禁止**运行测试；忽略示例/纯文档改动、忽略注释准确性。

## 4. 主编排阶段（`audit-pr` SKILL.md）

### 4.1 阶段 0：锁定 `AUDIT_TMP` 与 PR 标识

```text
1. 解析 PR_URL → owner, repo, number（正则 + 失败则报错退出）
2. AUDIT_TMP ← mktemp -d  （系统 temp，如 /tmp/audit-pr-123-XXXXXX）
3. trap：流程正常/异常结束时 rm -rf AUDIT_TMP；失败时 stderr 打印 AUDIT_TMP 供调试
4. 自检：cwd 疑似 marketplace 克隆且无目标项目特征 → 提示用户 cd 到目标仓库
```

### 4.2 阶段 1：元数据（`gh` 为主）

```bash
gh pr view <PR_URL> --json number,title,body,state,mergedAt,mergeCommit,baseRefName,headRefName,commits,comments,reviews
```

- 写入 `$AUDIT_TMP/pr-context.json`。
- `gh` 失败时：GitHub MCP `pull_request_read` / `issue_read` 补全；仍失败则退出。
- 历史 issue/PR 检索（支撑 `fix_mark_ignore` §1）：`gh search issues` / `gh pr list`；必要时 MCP `search_issues`。

### 4.3 阶段 2：本地 commit 与 diff 范围（策略 D）

```text
1. git pull（当前分支，缺省分支）
2. N ← pr number
3. git log --oneline -n 500  匹配 #N / PR #N / pull request #N（可配置 patterns）
4. 若唯一命中 commit C：
     parent ← C^（或 merge 第一 parent 规则见 4.4）
   否则：
     C ← pr-context.mergeCommit.oid；若无 mergeCommit（rebase-only）→ gh commits 首尾 SHA
5. 若本地无 C：git fetch origin && 再 cat-file / show
6. 最后手段：gh pr diff <PR_URL> 写入 $AUDIT_TMP/patch-fallback.diff
7. 写 $AUDIT_TMP/diff-scope.json：
     { commit, parent, files[], stats, source: local|api-fallback }
```

**Merge 样式补充（实施时写进 SKILL）：**

| 合入方式 | diff 命令倾向 |
|----------|----------------|
| Merge commit | `git diff -m -1 <merge>^1..<merge>` 或 `git show <merge>` |
| Squash | `git diff <C>^..<C>` |
| 多 commit rebase | `git diff <base>..<C>`，`base` 来自 `gh` 的 baseRefOid |

### 4.4 阶段 3：`pr-intent-analyst`

- 输入：`pr-context.json`、`diff-scope.json`（文件列表）、可选 `git show` 摘要。
- 输出：`$AUDIT_TMP/intent.json`（见 §6.2）。
- 判定 `pr_kind`: `bugfix | feature | docs-only | chore | unknown`（供是否触发 similar-defect-scout）。

### 4.5 阶段 4：四维分析（可并行委派）

| Agent | 输出文件 |
|--------|----------|
| `business-accuracy-analyst` | `findings/business.json` |
| `language-defect-analyst` | `findings/language.json` |
| `security-analyst` | `findings/security.json` |
| `edge-effect-analyst` | `findings/edge-effects.json` |

- 各 agent prompt 必须带：`AUDIT_TMP` 绝对路径、`diff-scope.json`、全局红线、`intent.json` 摘要。
- 每条 finding 若与 `author_stated_positions` 冲突，须在 finding 内说明或降低 severity。

### 4.6 阶段 5：`similar-defect-scout`（条件）

- **仅当** `intent.pr_kind == bugfix`（或主编排根据 title/body 判定为修复类）。
- 输出：`findings/similar-unfixed.json`。
- 参考原 PR 修复模式在仓库内 Grep/Glob 找同类未修逻辑（静态、只读）。

### 4.7 阶段 6：合并与逐条质询（≤5 轮 / finding）

```text
all ← 合并 findings/*.json 的 items[]，分配全局 finding_id
主编排过滤：intent 已标记 author_intended_waive 且证据充分的项 → 直接 withdrawn 审计记录，不进入质询

for F in all（按 severity 降序，blocking 优先）:
  proposer ← F.source_agent
  round ← 1
  while round <= 5:
    委派 audit-challenger(F, round, prior_challenges)
    读 challenges/<finding_id>-round-<round>.json
    if resolution in (withdrawn, accepted, downgraded):
       更新 F → break
    委派 proposer 修订（必须 Read/Grep 回应 required_evidence）
    round++
  if round > 5 and仍 disputed:
    F.disposition ← inconclusive（默认不进 should_fix）

写入 $AUDIT_TMP/findings-final.json
```

### 4.8 阶段 7：打分与 stdout 报告

- 主编排应用 [`docs/README.md`](../../README.md) 的 `fix_mark_ignore` / `fix_mark_should_fix` 规则。
- 委派 `report-writer`：只读 `$AUDIT_TMP/**`，**返回 Markdown 字符串**（不写仓库、不写持久 report 路径）。
- 主线程 **原样 stdout** 该 Markdown（唯一用户可见终稿）。
- `rm -rf AUDIT_TMP`（除非调试开关 `AUDIT_KEEP_TMP=1`）。

## 5. 全局红线（委派时必须复述）

1. 只读静态分析；禁止改代码、禁止跑测试。
2. 忽略示例代码、纯文档改动、注释准确性问题。
3. 触发场景必须有**代码依据**；禁止无根据猜测；排除仅单测可触发且生产上游已防护的场景（与 README §fix_mark_ignore.5 一致）。
4. 工作原理描述：**禁止冗长函数级调用链**；允许「用户/系统阶段 + 关键守卫点 + `path:line`」的**多层**路径（比 1～2 层更深，满足质询要求）。
5. 作者在设计说明中明确接受的风险/已知问题 → 不得按 P0/P1 上报（`audit-challenger` 强制核查）。

## 6. 中间产物 Schema

### 6.1 `pr-context.json`（主编排写）

```json
{
  "pr_url": "https://github.com/o/r/pull/123",
  "number": 123,
  "title": "...",
  "body": "...",
  "merged_at": "ISO8601",
  "merge_commit": "sha|null",
  "base_ref": "main",
  "comments_summary": [],
  "review_comments_summary": []
}
```

### 6.2 `intent.json`

```json
{
  "pr_kind": "bugfix",
  "stated_goal": "一句话",
  "author_stated_positions": [
    {
      "source": "pr_comment|review|code_comment",
      "ref": "url或 path:line",
      "quote": "原文摘要",
      "effect": "waive|defer|accepted_risk|documented_limitation"
    }
  ],
  "waived_defect_hints": ["与 README fix_mark_ignore 对齐的简短标签"]
}
```

### 6.3 单条 `finding`（各 analyst 共用）

```json
{
  "finding_id": "F-001",
  "source_agent": "language-defect-analyst",
  "dimension": "language|business|security|edge|similar-unfixed",
  "title": "简短标题",
  "severity": "P0|P1|P2|P3",
  "problem_type": 1,
  "problem_type_label": "原PR未达修复意图|原PR引入新问题|仓库同类缺陷",
  "code_refs": [{"path": "pkg/foo.go", "line": 42, "role": "defect|guard|entry"}],
  "trigger": {
    "description": "触发描述",
    "evidence_refs": ["path:line"],
    "prod_reachable": true,
    "reachability_stages": ["入口阶段", "守卫", "问题点"]
  },
  "impact": "用户可见后果",
  "solution": {
    "summary": "...",
    "estimated_lines": 20,
    "risks": "...",
    "confidence_percent": 85
  },
  "author_intent_checked": true,
  "contradicts_author_comment": false
}
```

### 6.4 `challenges/<finding_id>-round-<N>.json`

```json
{
  "finding_id": "F-001",
  "round": 1,
  "challenges": [
    {
      "challenge_type": "shallow_call_chain|no_prod_trigger|severity_inflated|author_intended|no_code_evidence|upstream_guard_exists",
      "question": "质疑内容",
      "required_evidence": "proposer 必须补充的证据形式"
    }
  ],
  "resolution": "pending|withdrawn|accepted|downgraded|inconclusive",
  "resolution_reason": "...",
  "adjusted_severity": "P2|null"
}
```

### 6.5 `findings-final.json`

```json
{
  "pr_number": 123,
  "items": [],
  "audit_result": "fix_mark_ignore|fix_mark_should_fix",
  "audit_result_reasons": []
}
```

## 7. `audit-challenger` 质询清单（硬性）

每轮至少检查：

- [ ] **调用链深度**：proposer 的 `reachability_stages` 是否少于 3 个阶段且未解释上游守卫？
- [ ] **生产可达**：是否仅靠单测/假设配置？能否引用上游封装或部署默认值否定？
- [ ] **严重性**：P0/P1 是否靠 panic/数据丢失支撑？降级后是否仍为 should_fix？
- [ ] **作者意图**：`intent.author_stated_positions` 与行内 comment 是否已覆盖？
- [ ] **历史已修**：`gh search` 是否显示同类已合入修复（支撑 ignore §1）？

`round == 5` 且仍有 `blocking` 级争议 → `resolution: inconclusive`，默认不进入 `fix_mark_should_fix`。

## 8. 工具与预算

| 角色 | 工具 | 预算要点 |
|------|------|----------|
| 主编排 | Bash(`gh`,`git`), 委派 Task | 负责 AUDIT_TMP、trap、stdout |
| 分析 agent | Read, Grep, Glob | Read ≤40/次委派；Grep ≤30；禁止 Write 仓库 |
| `audit-challenger` | Read, Write | Write **仅** `$AUDIT_TMP/challenges/**` |
| `report-writer` | Read | 只读 AUDIT_TMP；**禁止** Write 文件 |
| GitHub MCP | 可选 | 仅 `gh` 失败或 search 增强 |

**并行：** 阶段 4 四维 analyst 可并行委派；质询阶段 **串行**（每条 finding 内 round 串行，避免竞态写 challenges）。

## 9. stdout 报告结构（映射 `docs/README.md`）

```markdown
## audit PR ${N} 结论

AUDIT_RESULT=<fix_mark_ignore|fix_mark_should_fix>

（若 should_fix：PR 背景、问题种类、问题描述、问题后果、复现概率、严重等级、背景知识、解决方案、代码修改量、方案风险、方案信心）
```

**不包含：** `## audit PR … 的 llm 会话` 及任何 CLI resume 命令。

## 10. 与 `investigate-project` 的关系

- **独立插件** `audit`，不并入 `investigate-project`（领域不同：PR 审计 vs 功能报告）。
- **复用模式**：主编排 + 临时/中间 JSON + 质审 agent + 全局红线 6 条（PR 场景改为 §5 五条并加强调用链深度）。
- **不复用** `REPORT_ROOT` / `analysis-report/` / `report-quality-challenger` 文件（质询逻辑 PR 专用）。

## 11. marketplace 变更

`.claude-plugin/marketplace.json` 增加：

```json
{
  "name": "audit",
  "source": "./plugins/audit",
  "description": "Static PR audit on merged default branch (audit-pr skill + challengers, stdout report)."
}
```

## 12. 验收标准

1. `/audit:audit-pr <url>` 在已合入 PR、本地 main 已 pull 时，无需 `gh pr diff` 即可完成审计。
2. 每条进入 `findings-final` 的项，在 `challenges/` 中可追溯 ≤5 轮记录。
3. 终稿仅出现在 stdout；`AUDIT_TMP` 默认已删除。
4. 对「作者 comment 明确接受」的项，challenger 记录为 `withdrawn` 或 `downgraded`，且 `AUDIT_RESULT` 不误判为 should_fix。
5. 报告无 llm session 节。

## 13. 后续增强（非 v1）

- 可选 `codegraph_trace` 加速调用链（Cursor 环境）；Claude Code v1 不依赖。
- `AUDIT_KEEP_TMP=1` 调试开关写入 SKILL 附录。

---

## 附录：已确认决策表

| 议题 | 决策 |
|------|------|
| 环境 | Claude Code only |
| 插件 / skill | `audit` / `audit-pr` |
| PR 输入 | URL |
| 代码来源 | 本地缺省分支 commit，D 策略 + API fallback |
| GitHub | `gh` 主，MCP 兜底 |
| 终稿 | stdout only |
| 中间产物 | `mktemp -d` |
| 质询 | 每条 finding ≤5 轮 |
| 质询重点 | 深层调用链 + 作者有意为之 |
