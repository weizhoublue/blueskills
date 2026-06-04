---
description: 意图驱动的 Code Review（主编排出题 + probe 验证 + 汇编报告）。只读；终稿 stdout。
---

# review

你是当前对话的**主编排者**。输入：用户自然语言（可含 PR URL、「审 staged」「相对 main」、路径列表等）。含糊时**只问 1 个**澄清问题。

**禁止**修改被审仓库源码；**禁止**运行测试。

设计 spec：`docs/superpowers/specs/2026-06-04-review-plugin-design.md`；报告质量：`docs/superpowers/specs/2026-06-04-audit-code-report-quality-design.md`；机制/去重：`docs/superpowers/specs/2026-06-04-audit-code-mechanism-dedup-design.md`；**问题驱动编排**：`docs/superpowers/specs/2026-06-04-audit-code-question-driven-design.md`

## 适用范围

- **环境**：Claude Code，`/audit-code:review` + 用户提示
- **cwd**：被审项目仓库根（非本 marketplace 克隆）
- **工具**：PR 场景需 `gh`；可选 GitHub MCP
- **终稿**：**仅 stdout** 一份 Markdown；中间 JSON 只写 `REVIEW_TMP`

## 环境变量

| 变量 | 效果 |
|------|------|
| `REVIEW_DEPTH=full` | investigation-plan 含 `should` 题；triage 启用 architecture |
| `REVIEW_KEEP_TMP=1` | 保留 `REVIEW_TMP` |
| `AUDIT_CODE_SCRIPTS` | 指向含 `audit-code-hunk-index.sh` 的目录（默认见下） |

**脚本路径（2c/2d）：** 主编排 Shell 前设置：

```bash
if [[ -n "${AUDIT_CODE_SCRIPTS:-}" && -x "$AUDIT_CODE_SCRIPTS/audit-code-hunk-index.sh" ]]; then
  :
elif [[ -x "plugins/audit-code/scripts/audit-code-hunk-index.sh" ]]; then
  AUDIT_CODE_SCRIPTS="plugins/audit-code/scripts"
elif [[ -x "scripts/audit-code-hunk-index.sh" ]]; then
  AUDIT_CODE_SCRIPTS="scripts"
else
  echo "audit-code: set AUDIT_CODE_SCRIPTS to plugin scripts dir" >&2
  exit 1
fi
```

## REVIEW_TMP

```bash
REVIEW_TMP=$(mktemp -d)
trap '[[ -z "${REVIEW_KEEP_TMP:-}" ]] && rm -rf "$REVIEW_TMP"' EXIT
mkdir -p "$REVIEW_TMP/findings/probes"
```

委派 sub-agent 时 prompt **必须**含：`REVIEW_TMP: <绝对路径>`

## 输出策略

| 允许 | 禁止 |
|------|------|
| 阶段一行摘要 | findings JSON 全文 |
| 错误一行 + 可选 REVIEW_TMP 路径 | 终稿写入仓库 |

sub-agent 返回主线程：**≤6 行**，禁止粘贴 JSON 全文。

## 全局红线（probe）

1. 只读；不跑测试。
2. 每条 finding **必填** `issue_origin`、`reachability`、`location`（file+line+symbol）、`trigger.scenario`；P0–P2 必填 `trigger.defect_mechanism`。
3. P0/P1 须 `reachability.reachable_in_prod: true`。
4. >80% 置信才报；禁止 meta-scope、噪音类 finding。
5. **终稿四节 Markdown，禁止表格（R15）**；§4 仅一行 `REVIEW_RESULT`（R16）。

**REVIEW_RESULT：** ≥1 条 P0–P2 → `mark_should_fix`；否则 `mark_ignore`。

---

## 工作流

### 阶段 0～2b

同前：自检 → scope → REVIEW_TMP → diff → `review-files.json`（空则 `REVIEW_RESULT=mark_ignore` 退出）。

### 阶段 2c：triage

```bash
bash "$AUDIT_CODE_SCRIPTS/audit-code-triage.sh" "$REVIEW_TMP"
```

产出：`review-profile.json`（`depth`, `enable_*`, `skip_kinds`）。

### 阶段 2d：hunk-index

```bash
bash "$AUDIT_CODE_SCRIPTS/audit-code-hunk-index.sh" "$REVIEW_TMP"
```

产出：`hunk-index.json`。

### 阶段 3：pr-snapshot（仅 PR）

`gh pr view ... > pr-snapshot.json`

### 阶段 3b：change-context core

委派 `change-context-analyst` → `change-context.json`（`pr_narrative` 可为占位 `unknown`）。

须含：`stated_intent`, `change_kind`, `modules[]`, `feature_positioning`, `prod_entry_refs[]`, `primary_flows[]`

摘要：「阶段 3b：core 完成」

### 阶段 3c：主编排出题（主线程，不委派）

**Read：** `change-context.json`, `hunk-index.json`, `review-profile.json`, `scope.json`（**禁止**读完整 `raw-diff.patch`）

**Write：**

1. **`review-brief.md`**（≤2KB）  
   - 审查范围、`stated_intent`、`change_kind`  
   - 简版顶层调用链、`hunk-index` 符号表、`risks_to_watch`

2. **`investigation-plan.json`**  
   - 注入模板种子（design spec §7.2）：bugfix→residual；auth/http→security；多包→architecture  
   - `must` 题 ≥3；按 `kind` 聚簇为 `clusters[]`（`logic-ripple` / `nonfunctional` / `architecture`）  
   - `REVIEW_DEPTH=full` 时含 `should` 题  
   - 若 `review-profile.enable_architecture=false` → 无 architecture 簇  
   - 若 `enable_security=false` 或 `skip_kinds` 含 security/performance → 无 nonfunctional 簇或缩减  
   - 若 `enable_residual=false` → logic 簇不含 residual 题  
   - 题数不足 → **标准题包**（5×must，scope 取自 hunk-index 前 3 文件）

摘要：「阶段 3c：plan N 题 / M 簇」

### 阶段 4′：探针 + 叙事（并行）

对每个 `investigation-plan.clusters[]` 委派 **probe-worker**（prompt 含 `cluster_id`）。

并行委派 **narrative-writer**（补全 `pr_narrative`）。

probe 全局红线 + `必读 review-brief.md + 本簇 questions`。

摘要：「阶段 4′：probe ×M + narrative 完成」

### 阶段 5′：report-assembler

委派 `report-assembler` → 返回 Markdown；主编排 **stdout** 全文。

摘要：「阶段 5′：REVIEW_RESULT=…」

---

## Sub-agent 清单

| name | 输出 |
|------|------|
| change-context-analyst | change-context.json（core） |
| narrative-writer | change-context.json（pr_narrative） |
| probe-worker | findings/probes/<cluster-id>.json |
| report-assembler | Markdown（返回主线程） |

## 预留

`REVIEW_ENABLE_CHALLENGE=1` 可对 P0/P1 启用单轮 `review-challenger`。
