---
description: 对本地代码变更、在线 PR 等进行缺陷分析和质量评审，输出一份完整的缺陷和严重等级的分析报告
disable-model-invocation: true
---

# review

你是当前对话的**主编排者**。输入：用户自然语言（可含 PR URL、「审 staged」「相对 main」、路径列表等）。含糊时**只问 1 个**澄清问题。

**禁止**修改被审仓库源码；**禁止**运行测试。

设计 spec：`docs/superpowers/specs/2026-06-04-review-plugin-design.md`；报告质量：`docs/superpowers/specs/2026-06-04-audit-code-report-quality-design.md`；机制/去重：`docs/superpowers/specs/2026-06-04-audit-code-mechanism-dedup-design.md`；**问题驱动编排**：`docs/superpowers/specs/2026-06-04-audit-code-question-driven-design.md`；**根因聚合/表现点**：`docs/superpowers/specs/2026-06-04-audit-code-root-cause-manifestations-design.md`

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
2. **每题必须先**向下追溯调用链，再与 **兄弟/同类路径**（`peer_compare_refs`）对比 pattern，然后判定；禁止只看 scope 几行就 `confirmed`。
3. 每条 finding **必填** `issue_origin`、`reachability`（`trace_summary` 须与追溯一致）、`location`、`trigger.scenario`；P0–P2 必填 `trigger.defect_mechanism`。
4. P0/P1 须 `reachable_in_prod: true` 且链上无挡板；否则 `refuted` 或 `inconclusive`。
5. >80% 置信才 `confirmed`；链未走通 → `inconclusive`。
6. 禁止 meta-scope、噪音类 finding。
7. **终稿四节 Markdown，禁止表格（R15）**；§4 仅一行 `REVIEW_RESULT`（R16）。

**REVIEW_RESULT：** ≥1 条 P0–P2 → `mark_should_fix`；否则 `mark_ignore`。

---

## 工作流

### 阶段 0～2b

1. **自检** → `scope.json`（含糊则只问 1 题）。
2. **REVIEW_TMP** + `mkdir -p "$REVIEW_TMP/findings/probes"`。
3. **RTK 探测（阶段 2 前，一行）** — 决定本地 `git diff` 怎么写 patch：

```bash
if command -v rtk >/dev/null 2>&1; then AUDIT_CODE_RTK=1; else AUDIT_CODE_RTK=0; fi
```

| `AUDIT_CODE_RTK` | 含义 | 本地 `git diff` 写入 `raw-diff.patch` |
|------------------|------|--------------------------------------|
| `1` | 已装 **rtk** CLI；Claude/Cursor 等 Bash hook 常把裸 `git diff` 改成压缩输出 | **禁止**裸 `git diff > patch`。须用其一：`RTK_DISABLED=1 git diff …`、`rtk proxy git diff …`、`rtk git diff --no-compact …` |
| `0` | 无 rtk | 常规 `git diff … > "$REVIEW_TMP/raw-diff.patch"` |

- **`gh pr diff`** 一般不经 RTK hook，可直接 `gh pr diff … > "$REVIEW_TMP/raw-diff.patch"`。
- 写入后 **快速确认**：`grep -q '^diff --git ' "$REVIEW_TMP/raw-diff.patch"`（或合法空 diff）。若无 `diff --git` 且有改动 → 换用上表 bypass 命令重采，**勿**进入 2d/3c。
- **scope 示例**（无 RTK）：`git diff --staged`、`git diff "${base}...HEAD"`、`git diff A..B`、`git diff -- path`。
- **scope 示例**（有 RTK）：`RTK_DISABLED=1 git diff --staged` 等（参数同左）。

4. **`changed-files.json`** + **阶段 2b `review-files.json`**：

```json
{ "version": 1, "files": ["relative/path.go"] }
```

- `files` 为**字符串路径数组**；禁止把 `changed-files.json` 整结构误写入。
- 应用默认 `ignore_patterns`（spec §5）；空列表 → stdout 短句 + `REVIEW_RESULT=mark_ignore` + 退出。

5. **2d 后自检（有 RTK 时尤其重要）**：若 `hunk-index.json` 各文件 `lines_added`/`lines_removed` 全为 0，且 patch 无 `diff --git` → 判定 diff 被 RTK 压缩，回到步骤 3 用 bypass 重采。

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
   - **待验证根因**（≤5 bullet，来自下方 `root_causes[]`）

2. **`investigation-plan.json`**

   **按根因归纳（先于分簇，硬性）：**

   1. 从 `hunk-index` + `change-context` 列出候选根因，每项：`root_cause_key`（slug `[a-z0-9]+(-[a-z0-9]+)*`）、`summary`、`grep_tokens[]`（≥2）。  
   2. 写入 plan 根级 `root_causes[]`（与候选列表一致）。  
   3. **每个逻辑类根因仅 1 道** `priority: must` 题，且带 `root_cause_key` + `scopes[]`（覆盖该根因所有触及路径）；**禁止**同一 `root_cause_key` 再按文件拆多道 must 题。  
   4. `ripple` / `correctness` 题若与已有 `root_cause_key` 重叠 → 合并进该题的 `scopes[]` 或降为 `should`。  
   5. 典型 bugfix：`must` 逻辑根因题 ≤2 + residual（若 enable）+ 可选 security/architecture。

   **题目字段：**

   - **每题必填** `entry_ref`、`scope`、`hypothesis`  
   - 带 `root_cause_key` 的题：**必填** `scopes[]`（≥1 路径前缀或文件）、`grep_tokens[]`（≥2）；`scope` 为 `scopes[]` 子集或首屏入口文件  
   - plan 内同一 `root_cause_key`：**至多 1 道** `must` 题（`kind: residual` 除外）  
   - **logic-ripple / correctness / ripple / residual 题必填** `peer_compare_refs[]`（1～3 个兄弟路径前缀或文件）  
   - `must` 题 ≥3；按 `kind` 聚簇为 `clusters[]`（`logic-ripple` / `nonfunctional` / `architecture`）  
   - `REVIEW_DEPTH=full` 时含 `should` 题  
   - 若 `review-profile.enable_architecture=false` → 无 architecture 簇  
   - 若 `enable_security=false` 或 `skip_kinds` 含 security/performance → 无 nonfunctional 簇或缩减  

   **Bugfix 残留扫描（`review-profile.enable_residual=true` 时硬性）：**

   1. 在 plan 根级写 `fix_pattern_summary`（本 PR 修复模式一句话）与 `pr_fix_refs[]`（已修位置 `path:line` · `symbol`，来自 hunk-index）。  
   2. **必须注入 ≥1 道** `template: residual_peer_pattern`、`kind: residual`、`priority: must` 的题（**不得删除**）；`peer_compare_refs` 覆盖 PR **未改** 的兄弟模块/同类 Route 路径。  
   3. 示例题：

   ```json
   {
     "id": "Q-RES-1",
     "kind": "residual",
     "priority": "must",
     "template": "residual_peer_pattern",
     "hypothesis": "仓库内仍有与 PR 修复前相同的错误 pattern，且未应用本 PR 的等价修复",
     "scope": ["pkg/grpcroute/status.go"],
     "entry_ref": "GRPCRoute Reconcile → setStatuses",
     "peer_compare_refs": ["pkg/grpcroute/", "pkg/httproute/"],
     "sibling_prefix": "pkg/",
     "grep_tokens": ["DeepEqual", "ParentReference"]
   }
   ```

   4. 其它模板种子：auth/http→security；多包→architecture。  
   5. 若 `enable_residual=false` → 禁止 `kind: residual` 题。  

   **逻辑根因题示例**（一因多 scope，勿按文件拆题）：

   ```json
   {
     "id": "Q-RC-1",
     "kind": "correctness",
     "priority": "must",
     "template": "semantic_compare",
     "root_cause_key": "parentref-pointer-semantic-compare",
     "hypothesis": "ParentReference 含指针字段，用 == 或 slices.Contains 比较地址而非 API 语义值",
     "scopes": [
       "pkg/gateway-api/status_route.go",
       "pkg/gateway-api/routechecks/",
       "pkg/gateway-api/gateway_reconcile.go"
     ],
     "scope": ["pkg/gateway-api/routechecks/httproute.go"],
     "entry_ref": "Gateway Reconcile → setRouteStatuses → mergeStatusConditions",
     "peer_compare_refs": ["pkg/httproute/", "pkg/grpcroute/"],
     "grep_tokens": ["ParentReference", "slices.Contains", "DeepEqual", "=="]
   }
   ```

   **标准题包**（题数不足时）：5×must，且当 `enable_residual=true` 时**其中 1 道必须是** `residual_peer_pattern`；逻辑类须优先用 `root_cause_key` 聚题而非每文件一题。

摘要：「阶段 3c：plan N 题 / M 簇」

### 阶段 4′：探针 + 叙事（并行）

对每个 `investigation-plan.clusters[]` 委派 **probe-worker**（prompt 含 `cluster_id`）。

并行委派 **narrative-writer**（补全 `pr_narrative`）。

probe 全局红线 + `必读 review-brief、change-context、本簇 questions`；**每题：追溯调用链 → 兄弟/同类对比 → verdict**。

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
