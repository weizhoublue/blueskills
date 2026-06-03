# 设计文档：blueskills marketplace — `audit` 插件与 `audit-merged-pr` skill

- 日期：2026-06-03
- 状态：已审阅（v9：质询双文书辩驳 rebuttals，见 [`2026-06-03-audit-adversarial-debate-design.md`](./2026-06-03-audit-adversarial-debate-design.md)；v8 peer-path 见 [`2026-06-03-audit-peer-path-comparison-design.md`](./2026-06-03-audit-peer-path-comparison-design.md)）
- 来源需求：[`docs/README.md`](../../README.md)（PR 静态审计经验与报告结构；**不含** llm 会话 / resume CLI 一节）
- 运行环境：**仅 Claude Code**（`/plugin install audit@blueskills`，`/audit:audit-merged-pr <PR_URL>`）

## 1. 目标

将既有 PR 审计经验固化为可重复执行的 **Skill 编排 + 多 sub-agent**，实现：

1. 从 **PR URL** 获取元数据与评论（`gh` 为主，GitHub MCP 兜底）。
2. 在 **本地缺省分支**（如 `main`）上定位已合入 PR 的 **commit / diff**（本地 `git` 优先，API 拉 patch 为最后手段）。
3. **PR diff 归一化**：从原始变更中筛出 **effective_files**（生产相关代码），排除文档/示例/测试/vendor/lock/生成物/纯 rename-format 等，避免四维 analyst 空耗。
4. **多视角** 静态发现缺陷（业务 / 语言 / 安全 / 边缘 / 可选同类未修）；**仅扫描 effective_files**。
5. **`audit-challenger` 对每条 finding 最多 5 轮质疑**，重点：更深调用链、**严重等级/触发/后果核实**、作者有意为之则撤回或降级；适用 §7.2 降级矩阵。
6. **最终审计报告仅 stdout**（见 §4.10 输出策略）；中间过程可有简短进度日志；结构化产物只写 `AUDIT_TMP`。

## 2. 命名与仓库布局

```text
blueskills/
├── .claude-plugin/marketplace.json    # 增加 audit 插件条目
└── plugins/audit/
    ├── .claude-plugin/plugin.json     # name: audit
    ├── skills/audit-merged-pr/SKILL.md   # /audit:audit-merged-pr
    └── agents/
        ├── pr-intent-analyst.md
        ├── business-accuracy-analyst.md
        ├── language-defect-analyst.md
        ├── security-analyst.md
        ├── edge-effect-analyst.md
        ├── similar-defect-scout.md
        ├── peer-path-comparator.md
        ├── peer-parity-challenger.md
        ├── audit-challenger.md
        └── report-writer.md
```

| 层级 | 标识 |
|------|------|
| Plugin | `audit` |
| Skill | `audit-merged-pr` |
| 调用 | `/audit:audit-merged-pr https://github.com/owner/repo/pull/123` |

## 3. 前置条件与用户职责

- 用户 **`cd` 到目标仓库根**（与 `report-features` 相同）；**阶段 0b** 会校验本地 `remote.*.url` 是否与 PR URL 的 `owner/repo` 一致（任一 remote 命中即可，含 `upstream`）。
- 当前分支应为 **缺省分支**（`main` / `master` 等）；skill **不自动 checkout 其它分支**，仅对当前分支执行 `git pull`（或 `git pull --ff-only`）尝试更新。
- 已安装并登录 **`gh`**；可选配置 GitHub MCP 作搜索兜底。
- **禁止**修改代码、**禁止**运行测试；忽略示例/纯文档改动、忽略注释准确性。

## 4. 主编排阶段（`audit-merged-pr` SKILL.md）

### 4.1 阶段 0：解析 PR 与 marketplace 自检

```text
1. 解析 PR_URL → pr_owner, pr_repo, pr_number（正则；失败则 stderr 一行并退出）
   例：https://github.com/llm-d/llm-d-router/pull/1416 → llm-d / llm-d-router / 1416
   canonical 期望仓库：expected_owner_repo ← "pr_owner/pr_repo"（PR 链接中的仓库，通常为合入目标）
2. 自检：cwd 疑似 blueskills marketplace 克隆（存在 plugins/audit/.claude-plugin/plugin.json 且无被审项目特征）
   → stderr 提示 cd 到目标仓库后退出（不创建 AUDIT_TMP）
```

### 4.1b 阶段 0b：仓库绑定校验（Shell only，在 `mktemp` / `gh` 之前）

**目的：** 避免在错误目录（如 `cilium` 克隆）审计 `llm-d/llm-d-router` 的 PR，导致后续无代码依据、空耗 token。

```text
1. git rev-parse --is-inside-work-tree → 失败则退出（非 Git 仓库）
2. repo_root ← git rev-parse --show-toplevel
3. 枚举所有 remote URL（不限名称）：
     git config --get-regexp '^remote\..*\.url$'
4. 对每条 URL 归一化为 owner/repo（主编排 Shell 或短脚本）：
     - https://github.com/cilium/cilium.git  → cilium/cilium
     - git@github.com:weizhoublue/cilium.git → weizhoublue/cilium
     - 非 github.com host → 记入 unparsed_remotes[]，不参与匹配
5. binding_ok ← ∃ 归一化结果 == expected_owner_repo
6. 若 ¬binding_ok：
     stderr 一行：期望 expected_owner_repo；当前已解析 remotes 摘要（name→owner/repo，逗号分隔）
     不创建 AUDIT_TMP；不调用 gh；退出码 1
7. 若 binding_ok：继续 §4.1c
```

**匹配规则（已确认）：** 仅与 PR URL 中的 `owner/repo` 比对；**不**在 0b 阶段拉 `gh pr view` 的 head/base。fork 场景：本地 `origin` 为个人 fork、`upstream` 为上游时，只要**任一** remote 与 PR 链接仓库一致即通过。

**YAGNI（0b 不做）：** 不自动 clone/cd；不把 merge commit 是否存在并入 0b（阶段 2 负责）。

### 4.1c 阶段 0c：锁定 `AUDIT_TMP`

```text
1. AUDIT_TMP ← mktemp -d
2. trap：正常/异常结束 rm -rf AUDIT_TMP；AUDIT_KEEP_TMP=1 时保留并在 stderr 打印路径
3. mkdir findings challenges
4. 写入 $AUDIT_TMP/repo-binding.json（schema §6.0）
5. 向用户确认一行：将在 <expected_owner_repo> 审计 PR #N（不打印 AUDIT_TMP 除非 AUDIT_KEEP_TMP）
```

### 4.2 阶段 1：元数据（`gh` 为主）

```bash
gh pr view <PR_URL> --json number,title,body,state,mergedAt,mergeCommit,baseRefName,headRefName,commits,comments,reviews
```

- 写入 `$AUDIT_TMP/pr-context.json`。
- `gh` 失败时：GitHub MCP `pull_request_read` / `issue_read` 补全；仍失败则退出。
- 历史 issue/PR 检索（支撑 `fix_mark_ignore` §1）：`gh search issues` / `gh pr list`；必要时 MCP `search_issues`。

### 4.3 阶段 2：本地 commit 与 diff 范围（省 token / 少 API）

**原则：** commit 定位由 **主编排只跑 Shell** 完成；**禁止**把长 `git log` 原文贴进任何 sub-agent prompt。阶段 1 的 **一次** `gh pr view` 已含 `mergeCommit`，阶段 2 优先用该 SHA 在本地校验，避免「本地扫 500 条 + API 再对一遍」的双重开销。

```text
1. git pull（当前分支，缺省分支）
2. N ← pr number；merge_sha ← pr-context.mergeCommit.oid（阶段 1 已有，不再为定位 commit 单独打 gh）

3. 【路径 A — 常见、零 log 扫描】若 merge_sha 非空：
     git cat-file -e merge_sha  → 成功则 C ← merge_sha，source ← local-merge-sha
     失败则 git fetch origin merge_sha（或 fetch 缺省分支）后再 cat-file

4. 【路径 B — 仅当 A 不可用】主编排 Shell 有界 grep（结果只写入 diff-scope.json，不把 log 灌给模型）：
     按顺序执行，每种模式 --max-count=5，命中即停：
       git log --format=%H -n 1 --grep="Merge pull request #${N}\b"
       git log --format=%H -n 1 --grep="(#${N})\b"
       git log --format=%H -n 1 --grep="#${N}\b"
     若仍 0 条：git log --format=%H -n 5 --grep="#${N}"  → Shell 去重后若唯一则采用
     若 >1 条：写入 diff-scope.json 的 commit_resolution: ambiguous，取 merge_sha 或第一条并 flagged

5. 【路径 C — 仍无 C】使用 pr-context 已带的 commits[] 首尾（阶段 1 JSON，无额外 gh）

6. 【路径 D — 最后手段】gh pr diff → $AUDIT_TMP/patch-fallback.diff

7. 确定 C 后，Shell 生成 diff-scope.json（不让 agent 跑 git）：
     git diff --stat parent..C 、git diff --name-only parent..C
     仅把 { commit, parent, files[], stats, source, commit_resolution } 写入 JSON
```

**Token 预算：** 进入 sub-agent 的与 commit 相关的上下文 **≤ 1KB**（`diff-scope.json` 摘要字段），不含 `git log` 列表。

**Merge 样式补充（实施时写进 SKILL）：**

| 合入方式 | diff 命令倾向 |
|----------|----------------|
| Merge commit | `git diff -m -1 <merge>^1..<merge>` 或 `git show <merge>` |
| Squash | `git diff <C>^..<C>` |
| 多 commit rebase | `git diff <base>..<C>`，`base` 来自 `gh` 的 baseRefOid |

### 4.4 阶段 2b：PR diff 归一化（`effective-diff.json`）

**目的：** 四维 analyst **只读** `effective-diff.json`，不直接消费 `diff-scope.json` 的全量 `files[]`。

**执行者：** 主编排 Shell 规则初筛（**禁止**把全量 file list 贴进 agent）；对 `rename-only` / `format-only` 等疑难项可读 `git diff --numstat parent..C` 前 200 行做判定（仍不委派 agent，除非 v2 增加 `diff-normalizer`）。

**默认忽略规则（写入 `ignored_files`）：**

| `reason` | 路径/模式示例 |
|----------|----------------|
| `docs` | `docs/**`, `**/*.md`（仓库根 README 若仅文档改动）、`doc/**` |
| `example code` | `examples/**`, `example/**`, `demo/**`, `samples/**` |
| `test code` | `**/*_test.go`, `**/test/**`, `**/tests/**`, `**/__tests__/**`, `**/spec/**` |
| `vendor` | `vendor/**`, `third_party/**`, `node_modules/**` |
| `lock file` | `go.sum`, `go.work.sum`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Cargo.lock`, `poetry.lock` |
| `generated` | `**/*.pb.go`, `**/zz_generated*.go`, `**/mock_*.go`, `**/generated/**`（可按仓库 `.gitattributes` 或注释 `Code generated` 增强） |
| `ci` | `.github/**`, `.gitlab-ci.yml`, `Jenkinsfile` |
| `unrelated cleanup` | 主编排 heuristic：单文件仅空白/注释/format 且无逻辑行变化 |

**`large_or_generated_files`：** 单文件 diff 行数 > 500（阈值可配置）或二进制；默认不进入 effective，除非 PR 标题/body 表明其核心为该类文件。

**`effective_files` 准入：** 通过上述过滤的生产代码；`change_type`: `added|modified|deleted|renamed`；`language` 由扩展名推断。

写入 `$AUDIT_TMP/effective-diff.json`（schema §6.2）。若 `effective_files` 为空 → stdout 说明「无可审生产代码」并 `REVIEW_RESULT=fix_mark_ignore`（或提前结束）。

### 6.2b `subsequent-fixes.json`（`subsequent-fix-scout` 写，阶段 6a）

```json
{
  "audited_pr_number": 1416,
  "merge_commit": "sha",
  "scan_to_ref": "HEAD",
  "items": [
    {
      "finding_id": "F-001",
      "verdict": "already_fixed|fix_in_progress|not_addressed|uncertain",
      "confidence": "high|medium|low",
      "evidence": [
        { "kind": "commit", "sha": "...", "subject": "...", "refs": ["path:line"] },
        { "kind": "merged_pr", "number": 1502, "url": "...", "merged_at": "ISO8601", "overlap_paths": [] }
      ],
      "rationale": "一行"
    }
  ]
}
```

### 6.2c `findings/all-merged.json`（主编排写，阶段 6 合并后）

含已分配 `finding_id` 的全部 items，供 `subsequent-fix-scout` 与质询循环使用。

### 4.5 阶段 3：`pr-intent-analyst`

- 输入：`pr-context.json`、`effective-diff.json`（**非**全量 diff-scope）、可选每条 effective 文件的 `git show` 摘要（主编排限制总行数）。
- 输出：`$AUDIT_TMP/intent.json`（见 §6.3）。
- 判定 `pr_kind`: `bugfix | feature | docs-only | chore | unknown`（`docs-only` 且 effective 为空时直接结束）。

### 4.6 阶段 4：四维分析（可并行委派）

| Agent | 输出文件 |
|--------|----------|
| `business-accuracy-analyst` | `findings/business.json` |
| `language-defect-analyst` | `findings/language.json` |
| `security-analyst` | `findings/security.json` |
| `edge-effect-analyst` | `findings/edge-effects.json` |

- 各 agent prompt 必须带：`AUDIT_TMP` 绝对路径、`effective-diff.json`（**仅 effective_files**）、§5.6 上游防护清单、§5.8 执行路径一致性检查清单、`intent.json` 摘要、全局红线。
- **禁止**对 `ignored_files` / `large_or_generated_files` 提 finding（除非 PR 明确以该文件为修复核心且在 effective 中）。
- 每条 finding 须填 `upstream_guards_considered[]`（见 §6.4）；与 `author_stated_positions` 冲突须降级或撤回。
- **禁止**仅基于 diff hunk 断言业务逻辑错误；对 `effective_files` 中每个被修改的函数/方法，须按 §5.8 完成「diff 之外」的完整函数体与调用方 Read（在 Read 预算内）。

### 4.7 阶段 5：`similar-defect-scout`（条件）

- **仅当** `intent.pr_kind == bugfix`（或主编排根据 title/body 判定为修复类）。
- 输出：`findings/similar-unfixed.json`。
- 参考原 PR 修复模式在仓库内 Grep/Glob 找同类未修逻辑（静态、只读）。

### 4.7b 阶段 6a：`subsequent-fix-scout`（后续修复排查，质询前强制）

**目的：** 落实 README **fix_mark_ignore §1**——若发现的问题已在被审 PR **合入之后** 由后续 commit 或已合入 PR 修复（或已有明确修复中 PR），则**不必**进入质询与终稿。

**时机：** 阶段 6 合并 `findings/*.json` 并分配 `finding_id`、完成 `author_intended` / P3 预检之后；**逐条质询之前**。

**输入：**

- `$AUDIT_TMP/findings/all-merged.json`
- `pr-context.json`（`merge_commit`, `merged_at`, `number`）
- `diff-scope.json` 或 `effective-diff.json` 的 `commit`

**手段（Shell + 只读，禁止长 log 进 prompt）：**

| 来源 | 命令倾向 |
|------|----------|
| 后续 commit | `git log <merge_sha>..HEAD -- <code_refs.paths>`；可选 `git log -S<symbol>` |
| 后续已合入 PR | `gh pr list --state merged`（`mergedAt` 晚于被审 PR）；`gh search prs --merged` |
| 已关闭 issue | `gh search issues --state closed`（仅当链接到 PR/commit 时计证） |

**输出：** `$AUDIT_TMP/subsequent-fixes.json`（schema §6.2b）。

**主编排过滤：**

| `verdict` | `confidence` | 处置 |
|-----------|--------------|------|
| `already_fixed` | high / medium | `findings-rejected`，`disposition: subsequent_fix`，**跳过质询** |
| `fix_in_progress` | high / medium | 同上 |
| `uncertain` | * | 进入质询；`audit-challenger` 可读该 JSON 复核 |
| `not_addressed` | * | 进入质询 |

### 4.7c 阶段 6a′：`peer-path-comparator`（1 pass 对照表）

**目的：** 生成「同等/类似路径」对照证据（先 A 局部兄弟 ≤8，再按需 B 仓库 analogue ≤5）。

**时机：** 阶段 6a 之后、阶段 6a″ 之前。**无质询轮次**（单次委派 / finding）。

**输出：** `$AUDIT_TMP/peer-comparisons.json`；主编排合并为 `F.peer_comparison` 草稿。

详见增量 spec §3.2。

### 4.7d 阶段 6a″：`peer-parity-challenger`（等同路径专质询，≤3 轮 / finding）

**目的：** 在 audit 全链路质询之前，专审对照深浅与结论一致性（**M13/M14**）。

**时机：** 6a′ 之后、6b 之前。

**轮次：** 每条 finding **最多 3 轮**；每轮 `needs_rebuttal` 后 proposer 写 `$AUDIT_TMP/rebuttals/peer/**`（见 adversarial-debate spec）；Write 仅 `$AUDIT_TMP/peer-challenges/**`。

**结案：** `peer-challenges/<finding_id>-final.json`（`peer_line_resolution`）。

| 结案 | 主编排 |
|------|--------|
| `withdrawn` | 写入 `findings-rejected`，**跳过 6b** |
| `accepted` / `downgraded` | 更新 `peer_comparison` → 进入 6b |

### 4.8 阶段 6b：合并与逐条质询（audit ≤5 轮 / finding）→ **仅保留成立项**

**前置：** 必须已存在 `peer-challenges/<finding_id>-final.json`（6a″ 通过或 `not_applicable` 记录）。

**与 6a″ 分工：** audit 主责调用链、触发、严重级、§5.8 等；**可读** peer 结案并**交叉验证** peer，但**不得**重复 peer 线已 accepted 的议题，除非本轮提供**新** `path:line`（`peer_reopened_by_audit`）。详见增量 spec §3.4。

**原则：** 质询用于**淘汰不成立**与**优先级过低**的 finding。下列项 **不得** 进入 `findings-final.json` 或阶段 7：

- 不成立：`withdrawn`、`inconclusive`、质询前 `author_intended`
- **后续已修/修复中**：`subsequent_fix`（§4.7b，`already_fixed` / `fix_in_progress` 且 confidence ≥ medium）
- **严重等级 P3**（轻微级，低于本 skill 报告阈值）

阶段 7 / 终稿 **仅保留 P0、P1、P2** 且质询成立的条目。

```text
all ← 合并 findings/*.json 的 items[]，分配全局 finding_id
rejected ← []   # 仅审计追溯，不进终稿

主编排过滤：intent 已标记 author_intended_waive 且证据充分
  → 写入 rejected，reason=author_intended，不进入质询

survivors ← []

for F in all（按 severity 降序）:
  if F.severity == P3:
    rejected.append(F + { disposition: p3_below_threshold, reason: "skip_challenge" })
    goto next F                    # 不进入质询，直接淘汰

  proposer ← F.source_agent
  round ← 1
  while round <= 5:
    委派 audit-challenger(F, round, prior_challenges)
    读 challenges/<finding_id>-round-<round>.json
    if resolution == withdrawn:
       rejected.append(F + { disposition: withdrawn, last_round: round })
       goto next F                    # 不成立，直接淘汰
    if resolution == accepted:
       F.disposition ← accepted
       goto finalize_F
    if resolution == downgraded:
       F.severity ← adjusted_severity
       F.disposition ← downgraded
       goto finalize_F
    委派 proposer 修订（§7.1 证据）
    round++
  # 5 轮仍无法证明成立
  rejected.append(F + { disposition: inconclusive })
  goto next F

  finalize_F:
    if F.severity == P3:
      rejected.append(F + { disposition: p3_below_threshold, reason: "after_challenge" })
    else:
      survivors.append(F)              # 仅 P0|P1|P2
  next F:

写入 $AUDIT_TMP/findings-final.json      # 仅 survivors[]，severity ∈ {P0,P1,P2}
写入 $AUDIT_TMP/findings-rejected.json   # 可选，供调试；不得进入阶段 7
```

**质询结果与是否进入 final：**

| resolution / 条件 | 进入 `findings-final` | 含义 |
|-------------------|----------------------|------|
| `accepted` 且 severity ∈ {P0,P1,P2} | 是 | 成立，维持或上调后仍达报告阈值 |
| `downgraded` 至 P0/P1/P2 | 是 | 成立，仅降级但仍达报告阈值 |
| `downgraded` 至 **P3** 或质询前即为 P3 | **否** | 成立但优先级过低，写入 `findings-rejected`（`p3_below_threshold`） |
| `withdrawn` | **否** | 不成立 |
| `inconclusive` | **否** | 5 轮仍证不出，视为不成立 |

**与 §7.2 矩阵：** M2/M3/M4/M9 等将项定为 P3 时，质询结束后由 `finalize_F` 自动淘汰，**不必**再进入 should_fix 报告正文（与 `fix_mark_ignore` 一致）。

### 4.9 阶段 7：打分与最终报告（stdout）

- **仅读取** `findings-final.json`（`survivors`）；**禁止**把 `findings-rejected.json` 或原始 `findings/*.json` 未质询项当作 should_fix 依据。
- 若 `findings-final.items` 为空 → `REVIEW_RESULT=fix_mark_ignore`（可 stdout 一句「质询后无 P0–P2 成立缺陷」；P3-only 淘汰不计入）。
- 主编排应用 [`docs/README.md`](../../README.md) 的 `fix_mark_ignore` / `fix_mark_should_fix` 规则，并结合 §5.7 校验最高 severity 与等级定义一致。
- 委派 `report-writer`：只读 `$AUDIT_TMP/**`，**返回 Markdown 字符串**（不写仓库、不写持久 report 路径）。
- 主线程将 **§9 结构的审计报告** 作为 **唯一一次完整终稿** 写入 stdout（见 §4.10）。
- `rm -rf AUDIT_TMP`（除非调试开关 `AUDIT_KEEP_TMP=1`）。

### 4.10 输出策略（最终报告 vs 中间过程）

**最终用户可见的审计报告：仅 stdout。**

- 流程**结束**时，主线程向 stdout 输出 **一份**完整 Markdown（§9），对应 `REVIEW_RESULT=…` 及 should_fix 时的各小节。
- **R15（终稿排版）：** 禁止 markdown/HTML **表格**（任何 `| ... |` 行）；用 `###`、有序/无序列表、嵌套 bullet；`peer_comparison.table_rows` 等 JSON 字段在终稿中**仅**渲染为列表，不得成表。
- **禁止**将终稿写入仓库内文件、禁止写入 `AUDIT_TMP` 外的持久路径。

**中间过程（Claude Code 对话内）：允许简短进度，禁止倾倒大块数据。**

| 允许 | 禁止 |
|------|------|
| 阶段起止一行（如「阶段 2b：effective 12 文件，ignored 38」） | 完整 `findings/*.json`、`findings-final.json` |
| 质询轮次摘要（如「F-003 round 2/5 downgraded P0→P2 M1」） | 完整 `challenges/*-round-*.json` |
| 错误/失败原因一行 + 可选 `AUDIT_TMP` 路径（调试） | 长 `git log`、`git diff` / patch 全文 |
| 提前结束时的 **短** 结论（如 effective 为空） | 将 `effective-diff.json` 全量贴出 |

- sub-agent **返回给主线程**的应是 **路径引用 + 条数/摘要**（如 `findings/language.json: 3 items`），非 JSON 全文；全文只存在于 `$AUDIT_TMP/`。
- 实现 SKILL 时写明：编排者与各 agent 遵守上表；`AUDIT_KEEP_TMP=1` 时可在 stderr 提示临时目录供人工打开 JSON，**仍不向 stdout 打印 JSON 正文**。

## 5. 全局红线（委派时必须复述）

1. 只读静态分析；禁止改代码、禁止跑测试。
2. 忽略示例代码、纯文档改动、注释准确性问题。
3. 触发场景必须有**代码依据**；禁止无根据猜测；排除仅单测可触发且生产上游已防护的场景（与 README §fix_mark_ignore.5 一致）。
4. 工作原理描述：**禁止冗长函数级调用链**；允许「用户/系统阶段 + 关键守卫点 + `path:line`」的**多层**路径（比 1～2 层更深，满足质询要求）。
5. 作者在设计说明中明确接受的风险/已知问题 → 不得按 P0/P1 上报（`audit-challenger` 强制核查）。
6. 四维 analyst **仅**针对 `effective-diff.json` 中的文件；质询适用 §7.2 降级矩阵。
7. 四维 analyst **必须**执行 §5.8 执行路径一致性检查；不得只回答「diff 改了什么」而跳过未修改区域的逻辑对照。

### 5.6 上游防护类型清单（analyst / challenger 硬性参照）

分析触发路径时，必须主动查找并记录是否已被下列防护挡住（可多选，写入 finding / challenge）：

- API server schema validation
- CRD OpenAPI validation
- admission webhook validation
- CLI flag parser validation
- config loader defaulting
- controller enqueue 前过滤
- informer cache sync 判断
- nil/empty guard
- permission / RBAC / authz check
- feature gate
- platform capability check
- version compatibility check
- leader election guard
- state machine status guard
- retry / backoff / circuit breaker

### 5.7 严重等级 P0–P3 定义（analyst / challenger / report 统一）

等级描述 **生产环境**（缺省部署、缺省配置、主路径）下的**最高可达后果**；须与 §7.1 生产入口证据一致。定级前先过 §7.2 矩阵，**不得**无依据标 P0/P1。

| 等级 | 名称 | 定义（须同时满足「可达」） | 典型后果示例 |
|------|------|---------------------------|--------------|
| **P0** | 崩溃 / 阻断 | 主路径上**必然或高概率**导致进程崩溃、死锁、无限阻塞，或**核心功能完全不可用**（无法启动、无法完成主事务） | panic/OOM、controller 崩溃循环、数据写入半失败导致不可用、安全边界被绕过导致未授权执行 |
| **P1** | 严重 | 不崩溃但**核心功能错误**：数据错误/丢失（非测试数据）、主路径配置**静默不生效**、严重安全漏洞（可利用且影响生产） | 错误同步导致 DB 脏数据、RBAC 失效、密钥泄漏、主 API 返回错误状态且无降级 |
| **P2** | 普通 | **非主路径**或需**特定配置/边缘触发**的功能错误；有 workaround；性能明显退化但不阻断 | 边缘 API 行为错误、非默认 flag 组合下失败、可恢复的间歇错误、资源泄漏可重启恢复 |
| **P3** | 轻微 | **不影响功能正确性**：观测/日志/文案/指标偏差；极难触发的理论问题；仅开发体验 | 日志级别不当、metric 标签错误、错误 message 误导、极低频 race 且上游可重试成功 |

**本 skill 报告阈值：** P3 可在阶段 4 由 analyst 提出并参与质询（矩阵常将夸大项降至 P3），但阶段 6 结束后 **一律不进入** `findings-final` 与 stdout 问题列表。analyst/challenger 仍可用 P3 作为「成立但忽略」的定级手段。

**硬性约束（与矩阵联动）：**

- 无生产入口证据 → 不得 P0–P2（M1/M2 → withdrawn 或 P3）。
- 仅测试/示例代码路径 → withdrawn。
- 「可能 panic」但上游已有 §5.6 guard 且 proposer 未证伪 → 不得 P0（M8）。
- 安全项无用户可控输入 → 不得 P0/P1（M9）。
- **报告中的「严重等级」** = `findings-final` 中成立项的 **最高** severity；须能在 §9 复现概率一节用代码路径支撑。

### 5.8 执行路径一致性检查（阶段 4 强制，四维共用）

**动机：** 仅看 PR diff 会漏掉「改动与未改动代码不一致」类缺陷（如多阶段选择中，第一阶段有过滤、第二阶段 `yield`/回调未复用相同 eligibility）。

**范围：** 对 `effective-diff.json` 中每个 **被修改** 的函数/方法/逻辑块（含 diff 仅改一两行但语义影响整段控制流的情况），在 Read 预算内完成下列检查；**未修改** 但与改动语义耦合的相邻代码（同函数体、同 `yield` 块、同 iterator）**必须 Read**，不得假设与 diff 一致。

| # | 检查项 | 做法 |
|---|--------|------|
| 1 | **调用点与定义一致** | Grep 该符号/方法的调用方；核对调用参数、前置条件与定义处 guard 是否匹配 |
| 2 | **多阶段 eligibility 一致** | 若存在「先过滤再产出」结构，列出各阶段 path:line，对比各阶段是否应用**相同**准入规则 |
| 3 | **yield / 回调 / 闭包内 guard** | 若阶段 1 有 `continue`/`return`/`if !eligible` 等，检查阶段 2 的 `yield`、回调、子闭包是否遗漏同等检查 |

**启发式：两阶段选择模式（`two_phase_yield`，命名可写入 finding）**

典型形态（以调度/拓扑类代码为常见例，不限语言）：

```text
阶段 1（循环内筛选）:  if !topologyPreferenceCandidate(x) { continue }
阶段 2（产出）:        yield(be, rev)   // 或 callback / channel send / append
```

**审计要求：** 对阶段 2 的产出路径 Read 完整块；若阶段 1 的 eligibility 未在阶段 2 重复或无法由类型/不变式保证等价，则视为 **路径不一致** finding（`path_consistency.pattern`: `two_phase_yield`），除非 PR/注释证明有意为之（查 `intent.json`）。

**分工（四维，可重叠但不可省略本 agent 主责）：**

| Agent | 主责 |
|-------|------|
| `business-accuracy-analyst` | 多阶段业务规则是否一致；修复是否只改了一阶段 |
| `edge-effect-analyst` | 未修改调用方/兄弟分支是否仍假设旧语义；共享状态 |
| `language-defect-analyst` | `yield`/defer/panic/recover、闭包捕获、迭代器提前 continue |
| `security-analyst` | 分阶段校验时，危险操作前是否重复 authz/输入校验 |

**finding 可选字段**（涉及路径不一致时 **必填** `path_consistency`，见 §6.4）：

```json
"path_consistency": {
  "pattern": "two_phase_yield|call_site_mismatch|multi_phase_eligibility|yield_guard_omission",
  "symbol": "PreferSameNode",
  "phase_refs": [
    { "path": "pkg/x.go", "line": 10, "role": "phase1_eligibility" },
    { "path": "pkg/x.go", "line": 28, "role": "phase2_yield" }
  ],
  "inconsistency": "phase2 yield 未重复 phase1 的 topologyPreferenceCandidate"
}
```

**阶段 4 结束自检（各 analyst 返回主线程时一行）：** `path_consistency_scanned: <N symbols> | findings_with_path_consistency: <M>`。

## 6. 中间产物 Schema

### 6.0 `repo-binding.json`（主编排写，阶段 0c）

```json
{
  "pr_url": "https://github.com/llm-d/llm-d-router/pull/1416",
  "expected_owner_repo": "llm-d/llm-d-router",
  "repo_root": "/workspace/git/llm-d-router",
  "binding_ok": true,
  "matched_remote": "origin",
  "matched_url": "https://github.com/llm-d/llm-d-router.git",
  "all_remotes": [
    { "name": "origin", "owner_repo": "llm-d/llm-d-router", "url": "https://github.com/llm-d/llm-d-router.git" }
  ],
  "unparsed_remotes": []
}
```

失败时**不**写入此文件（0b 在 `mktemp` 之前失败）。

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

### 6.2 `effective-diff.json`（主编排写，阶段 2b）

```json
{
  "commit": "sha",
  "parent": "sha",
  "effective_files": [
    {
      "path": "pkg/foo/bar.go",
      "language": "go",
      "change_type": "modified",
      "reason": "production code"
    }
  ],
  "ignored_files": [
    { "path": "docs/usage.md", "reason": "docs" },
    { "path": "examples/demo.go", "reason": "example code" },
    { "path": "pkg/foo/bar_test.go", "reason": "test code" }
  ],
  "large_or_generated_files": [
    { "path": "api/v1/zz_generated.deepcopy.go", "reason": "generated", "lines_changed": 1200 }
  ]
}
```

### 6.3 `intent.json`

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

### 6.4 单条 `finding`（各 analyst 共用）

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
    "reachability_stages": ["入口阶段", "守卫", "问题点"],
    "prod_entry_ref": "path:line|null"
  },
  "upstream_guards_considered": [
    { "guard_type": "feature gate", "ref": "path:line", "blocks_issue": true|false }
  ],
  "impact": "用户可见后果",
  "solution": {
    "summary": "...",
    "estimated_lines": 20,
    "risks": "...",
    "confidence_percent": 85
  },
  "author_intent_checked": true,
  "contradicts_author_comment": false,
  "path_consistency": null
}
```

`path_consistency`：当 finding 断言「修复不完整 / 逻辑不一致 / 漏 guard」时 **不得为 null**；纯新增文件且无多阶段结构时可省略。

### 6.5 `challenges/<finding_id>-round-<N>.json`

```json
{
  "finding_id": "F-001",
  "round": 1,
  "challenges": [
    {
      "challenge_type": "shallow_call_chain|continue_call_chain|trigger_vague_unfounded|trigger_overly_theoretical|trigger_overly_extreme|trigger_contradicts_code|trigger_unreachable_in_prod|impact_overstated|severity_inflated|author_intended|no_code_evidence|upstream_guard_exists",
      "question": "质疑内容",
      "required_evidence": "见 §7.1（shallow_call_chain 时必须列出未满足条目编号）",
      "required_evidence_checklist": {
        "prod_entry": false,
        "param_path": false,
        "upstream_guard": false,
        "guard_insufficient_reason": false,
        "withdraw_if_no_entry": false
      }
    }
  ],
  "severity_review": {
    "original_severity": "P0",
    "proposed_severity": "P2",
    "matrix_rule_id": "M1",
    "trigger_verdict": "reachable|unreachable|uncertain",
    "impact_verdict": "as_stated|overstated|uncertain",
    "rationale": "一句话：为何维持或下调"
  },
  "resolution": "pending|withdrawn|accepted|downgraded|inconclusive",
  "resolution_reason": "...",
  "adjusted_severity": "P2|null"
}
```

### 6.6 `findings-final.json`（仅质询**成立**项）

```json
{
  "pr_number": 123,
  "items": [],
  "rejected_count": 7,
  "REVIEW_RESULT": "fix_mark_ignore|fix_mark_should_fix",
  "REVIEW_RESULT_reasons": []
}
```

- `items[]`：**仅** `disposition ∈ { accepted, downgraded }` 且 **`severity ∈ { P0, P1, P2 }`** 的 finding。
- 不成立项只在 `findings-rejected.json` + `challenges/` 留痕。

### 6.6b `findings-rejected.json`（可选，不进阶段 7）

```json
{
  "items": [
    {
      "finding_id": "F-002",
      "disposition": "withdrawn|inconclusive|author_intended_precheck|p3_below_threshold|subsequent_fix",
      "last_round": 2,
      "reason": "..."
    }
  ]
}
```

## 7. `audit-challenger` 质询清单（硬性）

质询目标：**问题是否成立**、**调用链是否够深**、**严重等级是否诚实**（触发在生产是否成立、后果是否夸大）。每轮必须输出 `severity_review`（§6.5），并引用 §7.2 矩阵填写 `matrix_rule_id`。

### 7.1 调用链过浅：`required_evidence` 硬性清单

当 `challenge_type` 为 `shallow_call_chain` 或 `continue_call_chain` 时，challenger **必须**勾选 proposer 下一轮尚未满足的条目；proposer **下一轮至少补齐其一**，否则 challenger 应判 `withdrawn`：

| # | 必填证据（至少一项） | 写入字段 |
|---|----------------------|----------|
| 1 | **生产入口** `path:line`（CLI / API / controller reconcile / webhook 等） | `trigger.prod_entry_ref` |
| 2 | **参数传递路径**：从入口到问题点的关键阶段（非函数名堆叠） | `reachability_stages` + refs |
| 3 | **上游 guard 是否存在**：对照 §5.6 清单，引用 `path:line` | `upstream_guards_considered[]` |
| 4 | **为何现有 guard 不能阻止该问题**（若 3 存在且 blocks_issue=true 则须解释） | `upstream_guards_considered[].blocks_issue` + 说明 |
| 5 | **若 1 找不到**：必须 **withdrawn**，不得维持 P0/P1 | `resolution: withdrawn` |

challenger 可在同轮直接要求 `continue_call_chain`（「继续深入调用链」），proposer 不得仅用文字否认，须新增 §5.6 类 guard 或入口证据。

### 7.1b 触发场景质询（含糊 / 理论 / 极端 / 无依据）

除「路径是否可达」外，challenger **必须**审查 `trigger.description` 的**表述质量与依据**（与 README fix_mark_ignore.5 一致）。

| `challenge_type` | 情形 |
|------------------|------|
| `trigger_vague_unfounded` | 含糊、推测性措辞，无逐步 `evidence_refs` |
| `trigger_overly_theoretical` | 与缺省部署/配置脱节，非常规手工状态 |
| `trigger_overly_extreme` | 罕见 flag 组合、钻牛角尖、仅恶意/渗透假设 |
| `trigger_contradicts_code` | 描述与实现或上游 guard 矛盾 |

**proposer 回应**须：重写为可核对步骤（每步 path:line）；或证明缺省配置下可达；或接受 withdrawn/P3。

`required_evidence_checklist.trigger_evidence` 四布尔项见 `audit-challenger.md`。

连续 2 轮仍无新 code ref → 倾向 `withdrawn`（**M10**）。

### 7.1c 执行路径一致性质询（§5.8）

当 finding 涉及「修复不完整 / 多阶段逻辑 / yield 漏检 / 调用不一致」时，challenger **必须**审查 proposer 是否只读了 diff hunk：

| `challenge_type` | 情形 |
|------------------|------|
| `shallow_path_consistency` | 未 Read 完整函数体或未列出 `path_consistency.phase_refs` |
| `two_phase_yield_guard_omission` | 声称两阶段不一致，但未对比 phase1 eligibility 与 phase2 yield/callback |
| `call_site_definition_mismatch` | 声称调用方错误，但未 Grep 全部调用点 |

`required_evidence_checklist.path_consistency`（四布尔，见 `audit-challenger.md`）。连续 2 轮无新 `phase_refs` → **M11**。

### 7.2 严重等级降级矩阵（challenger 必须引用 rule_id）

| ID | 条件 | `proposed_severity` / 处置 | 对 `fix_mark` 倾向 |
|----|------|---------------------------|-------------------|
| M1 | 无生产触发路径（§7.1 第 5 条或 M2 确认） | **withdrawn**；不得保留 P0/P1/P2 | ignore |
| M2 | 生产触发路径不确定 | 最高 **P3** | 默认 ignore |
| M3 | 仅影响错误日志、指标、提示文案 | 最高 **P3** | 通常 ignore |
| M4 | 需非默认危险配置才触发 | 最高 **P2**，通常 **P3** | 视是否有意配置 |
| M5 | 有明确 workaround | 最高 **P2** | 视产品承诺 |
| M6 | 只影响边缘功能，不影响主路径 | 最高 **P2** | 视回归风险 |
| M7 | 只影响新引入且未承诺的能力 | **withdrawn** 或 ignore | ignore |
| M8 | 只影响内部健壮性，上游已防护（§5.6） | **withdrawn** | ignore |
| M9 | 声称安全漏洞但无用户可控输入路径 | **withdrawn** 或 **P3** | ignore / 低优 |
| M10 | 触发场景含糊/理论/极端/无代码依据（§7.1b） | **withdrawn** 或最高 **P3** | ignore |
| M11 | 路径一致性断言但仅基于 diff、未对照完整函数/多阶段（§7.1c） | **withdrawn** 或要求补 `path_consistency` | ignore |
| M0 | 证据充分、生产可达、后果与等级匹配 | 维持 proposer 等级 | 可 should_fix |

**执行规则：**

- challenger 的 `severity_review.proposed_severity` **必须**可由上表一行解释；不得只写「建议降级」。
- `trigger_verdict=unreachable` → 至少 M1；`uncertain` → 至少 M2。
- `impact_overstated` → 按实际后果重新套 M0–M6，往往下调 ≥1 级。
- 主编排最终 `fix_mark_*` 须与 `findings-final` 中最高存活 severity 及矩阵一致。

### 7.3 每轮检查项（摘要）

- [ ] 调用链：是否满足 §7.1 或已 withdrawn？
- [ ] 路径一致性：逻辑类 finding 是否有 `path_consistency` 或应 M11？
- [ ] 触发可达性：对照 M1/M2/M4。
- [ ] 后果与等级：对照 §5.7 P0–P3 定义与 M0/M3/M6；`proposed_severity` 不得高于定义允许上限。
- [ ] 作者意图：`author_intended` → withdrawn/downgrade。
- [ ] 后续已修：`subsequent-fixes.json` 是否建议淘汰？proposer 主张仍成立时须反驳 evidence。

`round == 5` 且 severity 仍争议 → `inconclusive`，默认不进 `fix_mark_should_fix`。

## 8. 工具与预算

| 角色 | 工具 | 预算要点 |
|------|------|----------|
| 主编排 | Bash(`gh`,`git`), 委派 Task | 负责 AUDIT_TMP、trap、终稿 stdout、进度摘要 |
| 分析 agent | Read, Grep, Glob | Read ≤40/次委派；Grep ≤30；禁止 Write 仓库 |
| `audit-challenger` | Read, Write | Write **仅** `$AUDIT_TMP/challenges/**` |
| `report-writer` | Read | 只读 AUDIT_TMP；**禁止** Write 文件 |
| GitHub MCP | 可选 | 仅 `gh` 失败或 search 增强 |

**并行：** 阶段 4 四维 analyst 可并行委派；质询阶段 **串行**（每条 finding 内 round 串行，避免竞态写 challenges）。

## 9. 最终报告结构（仅 stdout 输出，映射 `docs/README.md`）

```markdown
## audit PR ${N} 结论

REVIEW_RESULT=<fix_mark_ignore|fix_mark_should_fix>

（若 should_fix：PR 背景、问题种类、问题描述、问题后果、复现概率、**同类路径比较**、严重等级、背景知识、解决方案、代码修改量、方案风险、方案信心）
```

**不包含：** `## audit PR … 的 llm 会话` 及任何 CLI resume 命令。

**排版：** 遵守 **R15** — 终稿全文禁止表格，仅用列表与小节标题。

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
  "description": "Static audit of merged PRs on default branch (audit-merged-pr; final report to stdout only)."
}
```

## 12. 验收标准

1. `/audit:audit-merged-pr <url>` 在已合入 PR、本地 main 已 pull 时，无需 `gh pr diff` 即可完成审计。
2. 存在 `effective-diff.json`；四维 analyst 的 finding 仅引用 `effective_files` 路径。
3. `withdrawn` / `inconclusive` / **P3** 项不在 `findings-final.items` 中（P3 可在 `findings-rejected` 追溯）。
4. 每条 `findings-final` 项在 `challenges/` 可追溯 ≤5 轮，且 `severity_review.matrix_rule_id` 有值。
5. 成立项 severity 符合 §5.7；`shallow_call_chain` 未满足 §7.1 的不得出现在 final 且为 P0/P1。
6. 最终审计报告仅 stdout；中间过程仅有 §4.10 允许的简短进度；`AUDIT_TMP` 默认已删除。
7. 报告无 llm session 节；报告问题列表仅来自 `findings-final`。
8. **阶段 0b**：PR URL 的 `owner/repo` 与 cwd 下**任一** `remote.*.url` 归一化结果不匹配时，必须在 `mktemp` / `gh` 之前失败退出，stderr 含期望仓库与已解析 remotes 摘要。
9. **阶段 4 / §5.8**：对含 `two_phase_yield` 或「漏 guard」类 finding，`path_consistency.phase_refs` 须含 phase1 与 phase2 的 path:line；challenger 可对仅 diff 断言项质询并 M11。
10. **阶段 6a**：对已在 `merge_commit..HEAD` 或后续 merged PR 中修复的 finding，须写入 `subsequent_fix` 并跳过质询与终稿。
11. **阶段 6a′–6a″**：`peer-comparisons.json` + `peer-challenges/*-final.json`；peer 线 ≤3 轮；`withdrawn` 不进 6b。
12. **阶段 6b**：audit ≤5 轮；已 Read peer-final；无重复 peer 议题（除非 `peer_reopened_by_audit` + 新证据）。
13. 终稿 should_fix 含 **同类路径比较**，与 `peer_comparison` 一致。

## 13. 后续增强（非 v1）

- 可选 `codegraph_trace` 加速调用链（Cursor 环境）；Claude Code v1 不依赖。
- `AUDIT_KEEP_TMP=1` 调试开关写入 SKILL 附录。

---

## 附录：已确认决策表

| 议题 | 决策 |
|------|------|
| 环境 | Claude Code only |
| 插件 / skill | `audit` / `audit-merged-pr` |
| PR 输入 | URL |
| 仓库绑定 | **阶段 0b**：所有 `remote.*.url` 归一化后与 PR URL 的 `owner/repo` 任一匹配；否则硬失败 |
| diff | 阶段 2 定位 commit；**阶段 2b** 归一化 → `effective-diff.json` |
| 代码来源 | mergeCommit 本地校验优先；有界 grep（≤5/模式）；`gh` 仅阶段 1 一次 + 最后 diff fallback |
| commit 定位 token | 禁止长 log 进 prompt；仅 JSON 摘要进 agent |
| 质询 | 每条 ≤5 轮；final 仅 P0–P2 成立项；§5.7；§5.8；§7.1–7.2 |
| 路径一致性 | 阶段 4 强制 §5.8；`two_phase_yield` 启发式；finding 可选 `path_consistency` |
| 后续修复 | 阶段 6a `subsequent-fix-scout`；`already_fixed`/`fix_in_progress` → `subsequent_fix` 淘汰 |
| 等同路径比较 | 6a′ `peer-path-comparator`（1 pass）→ 6a″ `peer-parity-challenger`（≤3 轮，M13/M14）→ 6b audit（≤5 轮，peer 交叉验证）；终稿 **同类路径比较** |
| 质询辩驳 | 方案 B：challenge → `rebuttals/` → 终裁；`finding-defense-mode`；challenger 须回应 `counterclaims` |
| GitHub | `gh` 主，MCP 兜底 |
| 终稿 | **最终报告** stdout only；中间允许简短进度（§4.10） |
| 中间产物 | `mktemp -d` |
