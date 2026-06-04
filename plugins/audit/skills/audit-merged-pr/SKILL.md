---
description: 审计已合入缺省分支的 GitHub PR（输入 PR URL）。在目标仓库根目录运行；静态分析、不跑测试；最终审计报告仅输出到 stdout。编排 pr-intent、四维、5b 去重、peer 质询≤2 轮/finding、audit 质询≤3 轮/finding、report-writer。
---

# audit-merged-pr

你是当前对话的**主编排者**。输入：`PR_URL`（斜杠命令参数或用户首条消息中的 GitHub PR 链接）。

**禁止**修改被审仓库源码；**禁止**运行测试。

设计 spec（维护者）：`docs/superpowers/specs/2026-06-03-audit-pr-plugin-design.md`

## 适用范围

- **环境**：Claude Code，`/audit:audit-merged-pr <PR_URL>`
- **cwd**：用户已 `cd` 到**被审项目仓库根**（非本 marketplace 克隆）；**阶段 0b** 校验至少一条 `remote.*.url` 与 PR URL 的 `owner/repo` 一致
- **分支**：当前分支应为**缺省分支**（`main` / `master`）；本 skill **不自动 checkout**，仅 `git pull` 更新当前分支
- **工具**：已登录 `gh`；可选 GitHub MCP（`gh` 失败或 search 时）
- **终稿**：**仅 stdout** 一份 Markdown（§最终报告）；中间 JSON 只写 `AUDIT_TMP`

## AUDIT_TMP（临时目录）

```text
AUDIT_TMP=$(mktemp -d)    # 例：/tmp/audit-pr-123-XXXXXX
trap '[[ -z "${AUDIT_KEEP_TMP:-}" ]] && rm -rf "$AUDIT_TMP"' EXIT
mkdir -p "$AUDIT_TMP/findings" "$AUDIT_TMP/challenges" "$AUDIT_TMP/peer-challenges" "$AUDIT_TMP/rebuttals/peer" "$AUDIT_TMP/rebuttals/audit"
```

- 委派任何 sub-agent 时 prompt **必须**含：`AUDIT_TMP: <绝对路径>`
- `AUDIT_KEEP_TMP=1` 时保留目录，可向 stderr 打印路径；**仍禁止**向 stdout 输出 JSON 正文

## 输出策略（最终报告 vs 中间过程）

| 允许（对话内） | 禁止 |
|----------------|------|
| 阶段一行摘要（如「阶段 2b：effective 12，ignored 38」） | 完整 findings/challenges JSON |
| 质询摘要（如「F-003 peer 2/2 accepted」「F-003 audit 2/3 P0→P2 M4」） | 长 `git log`、完整 diff、patch 全文 |
| 错误一行 + 可选 AUDIT_TMP 路径 | 终稿写入仓库或 AUDIT_TMP 外路径 |

sub-agent 返回主线程：**≤6 行**，含输出文件路径与条数，**禁止**粘贴 JSON 全文。

## 全局红线（每次委派必须复述）

1. 只读静态分析；禁止改代码、禁止跑测试。
2. 忽略示例、纯文档改动、注释准确性（已在 effective-diff 排除的不得再报）。
3. 触发场景须有**代码依据**；禁止猜测；排除仅单测可达且生产上游已防护（见 README fix_mark_ignore.5）。
4. 描述路径用「阶段 + 守卫点 + path:line」，**禁止**冗长函数名调用链列表。
5. 作者在设计说明中明确接受的风险 → 不得 P0/P1（challenger 强制查 intent / comment）。
6. 四维 analyst **仅**审计 `effective-diff.json` 的 `effective_files`。
7. 四维 analyst **必须**执行 §执行路径一致性（不得只分析 diff hunk，须 Read 完整函数体与相关未改代码）。
8. **终稿 Markdown（stdout）禁止表格（R15）**：不得使用 `| ... |` 或 HTML 表；用 `###` 与列表；`report-writer` 委派时须复述。
9. **质询双文书辩驳（方案 B）**：每轮 challenger `needs_rebuttal` 后，**必须**委派 proposer 写 `rebuttals/`；禁止 proposer 空泛服从；challenger 未回应 `counterclaims` 不得 `withdrawn`。

### 辩护模式（委派 proposer 回应质询时全文复述）

主线程委派 `F.source_agent` 辩护时，除全局红线外附上：

```text
模式：finding-defense（平等辩驳，非填表过关）
finding_id: F-xxx | line: peer|audit | round: N
Read: 本轮 challenges 或 peer-challenges 文件
Write 仅: $AUDIT_TMP/rebuttals/<line>/F-xxx-round-N.json
须逐条回应 challenges；可 counterclaims 反驳质询；禁止「接受质询」式空回应
详见 agents/finding-defense-mode.md
```

### 执行路径一致性（阶段 4 强制，委派时复述）

对 `effective_files` 中**每个被修改的函数/方法**（Read 预算内）：

| # | 检查 |
|---|------|
| 1 | Grep 调用点，核对与定义处 guard/参数一致 |
| 2 | 多阶段选择：各阶段 eligibility 规则是否一致（path:line 成对列出） |
| 3 | `yield`/回调/闭包：阶段 1 的 `continue`/过滤是否在阶段 2 重复或有不变量保证 |

**启发式 `two_phase_yield`：** 阶段 1 `if !eligible() { continue }` → 阶段 2 `yield(...)` / callback；须 Read 阶段 2 完整块，缺同等检查 → finding + `path_consistency`（见 spec §5.8）。

逻辑类 finding 必填 `path_consistency`（含 `phase_refs`）；各 analyst 返回须含一行：`path_consistency_scanned: N | findings_with_path_consistency: M`。

### 上游防护类型清单（§5.6）

API server schema validation；CRD OpenAPI validation；admission webhook validation；CLI flag parser validation；config loader defaulting；controller enqueue 前过滤；informer cache sync 判断；nil/empty guard；permission / RBAC / authz check；feature gate；platform capability check；version compatibility check；leader election guard；state machine status guard；retry / backoff / circuit breaker。

### 严重等级 P0–P3（§5.7）

| 等级 | 要点 |
|------|------|
| P0 | 生产主路径崩溃/死锁/核心功能完全不可用 |
| P1 | 核心功能错误：数据错丢、主配置静默失效、可利用且影响生产的安全问题 |
| P2 | 边缘路径或特殊配置；有 workaround；性能差但不阻断 |
| P3 | 日志/指标/文案；不影响正确性；理论边缘问题 |

**报告阈值**：阶段 6 结束后 **仅 P0–P2** 进入 `findings-final` 与 stdout。P3 可参与质询但最终淘汰。

---

## 工作流（严格顺序）

**每次委派 sub-agent：复述「全局红线」+ `AUDIT_TMP` 绝对路径。**

### 阶段 0：解析 PR 与 marketplace 自检

```text
1. 从参数/用户消息解析 PR_URL → pr_owner, pr_repo, pr_number
   expected_owner_repo ← "pr_owner/pr_repo"
2. 若 cwd 在本 marketplace（存在 plugins/audit/.claude-plugin/plugin.json 且无被审项目特征）
   → stderr 提示 cd 到目标仓库后退出（不创建 AUDIT_TMP）
```

### 阶段 0b：仓库绑定校验（Shell only，在 mktemp / gh 之前）

**禁止**在绑定失败时调用 `gh` 或委派 sub-agent。

```bash
git rev-parse --is-inside-work-tree   # 失败 → 退出
REPO_ROOT=$(git rev-parse --show-toplevel)

# 枚举所有 remote（origin、upstream 等均参与）
git config --get-regexp '^remote\..*\.url$'
```

对每条 URL **归一化**为 `owner/repo`（主编排用 Shell/Python 短脚本，勿贴长输出进对话）：

| 形式 | 示例 | 结果 |
|------|------|------|
| HTTPS | `https://github.com/cilium/cilium.git` | `cilium/cilium` |
| SSH | `git@github.com:weizhoublue/cilium.git` | `weizhoublue/cilium` |

**判定：** 若 **任意** 归一化结果 `== expected_owner_repo` → 通过；否则 stderr 一行并 **exit 1**：

```text
audit-merged-pr: 仓库不匹配。PR 需要 llm-d/llm-d-router，当前 remotes: weizhoublue/cilium, cilium/cilium。请 cd 到正确仓库后重试。
```

非 `github.com` 的 URL 记入 `unparsed_remotes`，不参与匹配。0b **不**拉 `gh` 核对 head/base。

### 阶段 0c：锁定 AUDIT_TMP

```text
1. AUDIT_TMP=$(mktemp -d)；mkdir findings challenges peer-challenges rebuttals/peer rebuttals/audit；配置 trap
2. 写入 $AUDIT_TMP/repo-binding.json（expected_owner_repo, repo_root, matched_remote, all_remotes[]）
3. 向用户确认一行：将在 expected_owner_repo 审计 PR #N（不打印 AUDIT_TMP 除非 AUDIT_KEEP_TMP）
```

### 阶段 1：PR 元数据（gh 为主）

```bash
gh pr view "$PR_URL" --json number,title,body,state,mergedAt,mergeCommit,baseRefName,headRefName,commits,comments,reviews
```

- 写入 `$AUDIT_TMP/pr-context.json`（字段见 spec §6.1）
- `gh` 失败 → GitHub MCP 补全；仍失败则退出
- 可选：`gh search issues` / `gh pr list` 支撑 fix_mark_ignore（结果摘要写入 pr-context，**不**贴全文）

### 阶段 2：commit 定位（Shell only，禁止把 log 贴进对话）

```text
1. git pull（当前分支）
2. merge_sha ← pr-context.mergeCommit.oid
3. 路径 A：git cat-file -e "$merge_sha" → 成功则 C=merge_sha；失败则 git fetch 后重试
4. 路径 B（A 失败）：有界 grep，每种 --max-count=5，只把最终 SHA 写入 diff-scope.json：
   git log --format=%H -n 1 --grep="Merge pull request #${N}\b"
   git log --format=%H -n 1 --grep="(#${N})\b"
   git log --format=%H -n 1 --grep="#${N}\b"
5. 路径 C：pr-context.commits 首尾
6. 路径 D：gh pr diff → $AUDIT_TMP/patch-fallback.diff
7. Shell 生成 diff-scope.json：commit, parent, files[], stats, source, commit_resolution
   git diff --name-only parent..C ；git diff --stat parent..C
```

### 阶段 2b：diff 归一化 → effective-diff.json

主编排按路径规则分类（**Shell/脚本**，不委派 agent）：

| reason | 模式示例 |
|--------|----------|
| docs | `docs/**`, `**/*.md`（若 PR 仅文档可 effective 为空） |
| example code | `examples/**`, `example/**`, `demo/**`, `samples/**` |
| test code | `*_test.go`, `test/`, `tests/`, `__tests__/`, `spec/` |
| vendor | `vendor/`, `third_party/`, `node_modules/` |
| lock file | `go.sum`, `package-lock.json`, `yarn.lock`, `Cargo.lock`, … |
| generated | `*.pb.go`, `zz_generated`, `mock_`, `generated/` |
| ci | `.github/`, `.gitlab-ci.yml` |

- `large_or_generated_files`：单文件变更行数 >500 或二进制
- 写入 `$AUDIT_TMP/effective-diff.json`
- 若 `effective_files` 为空 → stdout 短句 + `REVIEW_RESULT=fix_mark_ignore` + 清理退出

### 阶段 3：pr-intent-analyst

委派 `pr-intent-analyst` → `$AUDIT_TMP/intent.json`

### 阶段 4：四维分析（可并行）

委派时除全局红线外，**必须**附带「§执行路径一致性」全文 + spec §5.8。

| agent | 输出 | §5.8 主责 |
|-------|------|-----------|
| business-accuracy-analyst | findings/business.json | 多阶段业务规则、修复是否只改一阶段 |
| language-defect-analyst | findings/language.json | yield/闭包/defer、迭代器 continue |
| security-analyst | findings/security.json | 分阶段 authz/输入校验是否重复 |
| edge-effect-analyst | findings/edge-effects.json | 未改调用方/兄弟分支；配置依赖、同类配置语义、默认值隐式传播 |

finding 字段见 spec §6.4（含 `upstream_guards_considered`, `trigger.prod_entry_ref`, 逻辑类必填 `path_consistency`）。

### Findings 主链不变式（HARD-GATE）

1. 阶段 6 的 `all-merged.json` **仅**来自 `dedupe-result.json` 的 `canonical_items[]`。
2. 若 `findings/similar-unfixed.json` 存在且 `items.length > 0`，则 5b 必须将其全部计入 dedupe；`input_counts.similar_unfixed` 与 manifest 一致，否则 stderr `similar findings not fed to dedupe` 且**退出码 1**。
3. 每条 similar item 须在 `canonical_items` 或 `superseded-by-dedupe`（含 key + reason）中可追溯；禁止 silent drop。
4. similar 来源 canonical 走与四维相同的 6a → 6a′ → 6a″ → 6b。
5. 阶段 7 / report-writer **仅**读 `findings-final.json`；**禁止**读 `similar-unfixed.json` 写结论或「后续改进」。
6. `problem_type=3` 且质询成立的 P0–P2 survivor **必须**参与 `fix_mark_should_fix`（含「仅 similar 成立」场景）。

### 阶段 5：similar-defect-scout（条件）

仅当 `intent.pr_kind == bugfix` → `findings/similar-unfixed.json`

### 阶段 5a：findings intake manifest（Shell only）

```text
读取 findings/business.json, language.json, security.json, edge-effects.json,
      及若存在的 similar-unfixed.json
统计各 items.length → 写入 $AUDIT_TMP/findings/intake-manifest.json
schema: { version:1, sources:{ business, language, security, edge, similar_unfixed },
          policy:"all_sources_must_reach_dedupe_and_challenge_or_superseded" }
```

### 阶段 5b：finding 去重（质询前，避免四维重复报同一 defect）

**问题：** business / language / security / edge 常对同一根因各报一条（如 eligibility + yield 漏 guard + 兄弟路径），若不去重会导致阶段 6 多轮重复质询。

```text
1. （可选 Shell）合并四维 items 索引，按 defect path + line÷20 写 $AUDIT_TMP/findings/dedupe-hints.json
2. 委派 finding-dedupe-normalizer
   → $AUDIT_TMP/findings/dedupe-result.json（canonical_items[]）
   → $AUDIT_TMP/findings/superseded-by-dedupe.json（不进质询）
3. 向用户一行摘要：「阶段 5b：去重 N→M 条 canonical」
```

委派时附：四维 + **若存在的** `findings/similar-unfixed.json`、`findings/intake-manifest.json`；规则见 `agents/finding-dedupe-normalizer.md`（D1–D4 合并，K1–K4 分开）。

4. **断言**（主编排 Shell 或 jq）：
   - `dedupe-result.input_counts.*` 与 manifest.sources 一致
   - `dedupe-result.stats.in == sum(manifest.sources)`
   - 若 `manifest.sources.similar_unfixed > 0` 且 `input_counts.similar_unfixed == 0` → stderr `similar findings not fed to dedupe`，**退出码 1**
   - 失败则不进入阶段 6

### 阶段 6：合并、后续修复、等同路径与逐条质询

```text
all ← dedupe-result.json 的 canonical_items[]（勿再直接合并原始四维重复项）
分配 finding_id（F-001…）
写入 $AUDIT_TMP/findings/all-merged.json
rejected ← []；survivors ← []

# 预检：author_intended → rejected
# 初始 severity==P3 → rejected（p3_below_threshold, skip_challenge）

# 阶段 6a：后续修复排查（对齐 README fix_mark_ignore.1）
委派 subsequent-fix-scout → $AUDIT_TMP/subsequent-fixes.json
for F in all:
  若 subsequent-fixes[F].verdict ∈ {already_fixed, fix_in_progress}
     且 confidence ∈ {high, medium}
    → rejected（disposition: subsequent_fix）
    → 不进入 6a′/6a″/6b
  uncertain → 可进入后续 peer/audit 线

# 阶段 6a′：等同路径对照（1 pass，P0–P2，未 subsequent_fix）
委派 peer-path-comparator → $AUDIT_TMP/peer-comparisons.json
主编排：将每项合并为 F.peer_comparison 草稿（含 table_rows 摘要）

# 阶段 6a″：等同路径专质询（≤2 轮 / finding，双文书辩驳）
for F in all \ rejected（severity 降序，且 severity∈{P0,P1,P2}）:
  peer_round ← 1
  while peer_round <= 2:
    委派 peer-parity-challenger(F, peer_round)
    若 resolution ∈ {withdrawn, accepted, downgraded}:
      须已存在与**本轮或上一轮** needs_rebuttal 对应的 rebuttals/peer/F-round-*.json
      若 withdrawn → rejected（peer_line_withdrawn）；跳过 6b；goto next_F
      若 accepted|downgraded → 写 peer-challenges/F-final.json；更新 F.peer_comparison；break
    若 resolution == needs_rebuttal:
      委派 F.source_agent 辩护（finding-defense-mode）→ rebuttals/peer/F-round-<peer_round>.json
      若 stance_summary==proposer_withdraws → rejected；goto next_F
      可选：委派 source_agent 修订 peer_comparison（在 rebuttal 之后）
    peer_round++
  若 peer_round>2 且无 accepted → rejected（peer_inconclusive）；goto next_F

  # 阶段 6b：全链路质询（≤3 轮，双文书；须已有 peer-challenges/F-final.json）
  round ← 1
  while round <= 3:
    委派 audit-challenger(F, round)   # 必读 peer-final；读 rebuttals/audit 当轮及上轮
    若 resolution ∈ {withdrawn, accepted, downgraded}:
      须已存在与**本轮或上一轮** needs_rebuttal 对应的 rebuttals/audit/F-round-*.json
      若 withdrawn → rejected；break
      若 accepted → goto finalize_F
      若 downgraded → F.severity=adjusted；goto finalize_F
    若 resolution == needs_rebuttal:
      委派 F.source_agent 辩护 → rebuttals/audit/F-round-<round>.json
      若 proposer_withdraws → rejected；break
      可选：委派 source_agent 修订 finding（回应 §7.1 证据）
    round++
  若 round>3 → rejected（inconclusive）

  finalize_F:
    若 F.severity==P3 → rejected（p3_below_threshold, after_challenge）
    否则 survivors.append(F)（须含 peer_comparison + peer_line_resolution）

写入 findings-final.json（仅 survivors，severity∈{P0,P1,P2}）
写入 findings-rejected.json
```

### 阶段 7：打分与 stdout 终稿

- **仅读** `findings-final.json` 应用 [`docs/README.md`](../../../docs/README.md) 的 `fix_mark_ignore` / `fix_mark_should_fix`
- 若 `items` 为空 → `fix_mark_ignore`（无 P0–P2 成立缺陷）
- 委派 `report-writer` → 取得 Markdown 字符串（**复述 R15：终稿禁止 markdown 表格**）
- **一次性输出到 stdout**（§最终报告结构，**无** llm session 节，**无**表格）
- 清理 `AUDIT_TMP`（除非 `AUDIT_KEEP_TMP=1`）

### fix_mark 要点（主编排）

**fix_mark_ignore** 当：无 P0–P2 成立项；或 **subsequent-fix-scout** 证实问题已在后续 commit/PR 修复或修复中；或 issues 已修；或非严重缺陷；或无清晰方案；或作者 comment 表明接受；或生产不可达等（README 全文）。

**fix_mark_should_fix** 当：存在 P0–P2 成立项且有清晰修复方案。
- 含 `dimension=similar-unfixed` 或 `problem_type=3` 的 P0–P2 survivor 与 PR 内 defect 同等计入。
- **禁止**因「不在本 PR diff」对未质询的 similar 使用 fix_mark_ignore。

---

## 最终报告结构（stdout）

```markdown
## audit PR ${N} 结论

REVIEW_RESULT=<fix_mark_ignore|fix_mark_should_fix>

若 should_fix，输出如下各小节信息
- PR 背景
- 问题种类
- 问题描述
- 问题后果
- 复现概率
- 同类路径比较
- 严重等级
- 背景知识
- 解决方案
- 代码修改量
- 方案风险
- 方案信心
```

**禁止**输出「audit PR … 的 llm 会话」或任何 CLI resume 命令。

**R15（终稿排版）：** 全文禁止 markdown/HTML 表格；各小节用 `- **标题**` 与嵌套列表；`peer_comparison.table_rows` 仅作列表素材。

## Sub-agent 清单

| name | 职责 |
|------|------|
| pr-intent-analyst | intent.json |
| business-accuracy-analyst | findings/business.json |
| language-defect-analyst | findings/language.json |
| security-analyst | findings/security.json |
| edge-effect-analyst | findings/edge-effects.json |
| similar-defect-scout | findings/similar-unfixed.json |
| finding-dedupe-normalizer | dedupe-result.json、superseded-by-dedupe.json（阶段 5b） |
| subsequent-fix-scout | subsequent-fixes.json（阶段 6a，已修/修复中则淘汰） |
| peer-path-comparator | peer-comparisons.json（阶段 6a′，1 pass） |
| peer-parity-challenger | peer-challenges/*-round-*.json、*-final.json（阶段 6a″，≤2 轮，M13/M14） |
| audit-challenger | challenges/*-round-*.json（阶段 6b，≤3 轮；peer 交叉验证） |
| report-writer | 返回 Markdown（不写盘） |
