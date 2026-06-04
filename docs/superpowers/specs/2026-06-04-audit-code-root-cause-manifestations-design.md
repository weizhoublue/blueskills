# 设计文档：audit-code 根因聚合与表现点呈现

- 日期：2026-06-04
- 状态：已审阅（用户确认 §1–§4，选项 A）
- 范围：`plugins/audit-code`（skill `review`、agents、verify 脚本）
- 前置：
  - `docs/superpowers/specs/2026-06-04-audit-code-mechanism-dedup-design.md`（`defect_mechanism`、cluster pass）
  - `docs/superpowers/specs/2026-06-04-audit-code-question-driven-design.md`（主编排出题、probe-worker）
  - `docs/superpowers/specs/2026-06-04-audit-code-report-quality-design.md`（四节终稿、R15/R16）
- 触发：试跑报告将同一根因（ParentReference 指针字段 + `==` / `slices.Contains` 语义比较失效）拆成 3 条独立 P2；用户要求少派重复题、终稿合并为「一因多果」。

## 1. 问题陈述

问题驱动编排 + `report-assembler` cluster pass 上线后，仍出现：

1. **出题按文件/函数切分**：主编排对 `status_route.go`、`routechecks/*`、`gateway_reconcile.go` 各出一题 → probe 各 `confirmed` 一条 → 汇编阶段 3 条 P2。
2. **cluster pass 未命中**：第三条机制表述为「先剪枝再检查顺序」，与前两条「指针比较」用词不同；且文件跨目录，`related_symbols` 未交叉 → 启发式三条件不满足。
3. **终稿形态**：读者看到「3 个 P2」，结论写「均源自同一根因」，信息重复、严重度观感放大。

用户选择 **A**：**1 条 P2** = 一个 **根因原理** + **表现点** 列表（多处位置、各自后果）。

## 2. 目标

1. **上游**：`investigation-plan` 按 **根因假设**（`root_cause_key`）出题，同一根因 **一题多 `scopes[]`**，减少重复派发。
2. **中游**：`probe-worker` 同簇、同 `root_cause_key` **至多一条** finding，`manifestations[]` 承载多位置/多后果。
3. **下游**：`report-assembler` **root_cause pass** 兜底合并；终稿 **表现点** 有序列表（R15 仍禁表）。
4. **计数语义**：`REVIEW_RESULT` 按合并后 **finding 条数**（非表现点数）；§4 可写「1 个 P2（含 N 处表现点）」。
5. 保持四节结构、`defect_mechanism` 三要素、既有 gate（`vague_no_mechanism`、`missing_call_chain` 等）。

## 3. 非目标

- 不引入 ML/embedding 根因分类。
- 不改变 P0–P2 驱动 `mark_should_fix` 的规则（仅减少重复条数）。
- 不要求 probe 全仓二次扫描；合并依赖 plan 键 + 既有 `grep_tokens` / cluster pass。

## 4. 方案选择

| 方案 | 摘要 | 结论 |
|------|------|------|
| 仅汇编合并 | 加强 cluster + 新终稿 | 仍多题、多 token |
| 仅出题合并 | plan 一因一题 | probe 漏标 key 时无兜底 |
| **全链路（采用）** | plan 按根因出题 + probe 簇内合并 + assembler root_cause pass + 表现点终稿 | 墙钟、token、可读性兼顾 |

## 5. Schema：`root_cause_key` 与 `manifestations[]`

### 5.1 Finding（probe 输出 / assembler 合并后）

在既有 finding 上增加：

```json
{
  "id": "F-001",
  "severity": "P2",
  "finding_category": "correctness",
  "issue_origin": "pr_introduced",
  "root_cause_key": "parentref-pointer-semantic-compare",
  "title": "ParentReference 指针字段用 ==/Contains 导致语义比较失效",
  "primary_location": {
    "file": "operator/pkg/gateway-api/routechecks/httproute.go",
    "line": 59,
    "symbol": "mergeStatusConditions"
  },
  "trigger": {
    "defect_mechanism": "ParentReference 含 *Group、*Kind、*Namespace 等指针字段；== 与 slices.Contains 比较指针地址而非 API 语义值。spec 中省略的 nil 与 status 中显式字符串不等，导致 Contains 误判、重复 append 或剪枝漏删。",
    "failure_mode": "（合并项可省略或写最严重后果摘要）",
    "scenario": { "precondition": "…", "trigger": "…", "bad_outcome": "…" }
  },
  "manifestations": [
    {
      "location": { "file": "operator/pkg/gateway-api/status_route.go", "line": 18, "symbol": "pruneRouteParentStatuses" },
      "failure_mode": "跨命名空间及其他 parentRef 字段上剪枝/比较失效",
      "scenario": { "precondition": "…", "trigger": "…", "bad_outcome": "…" },
      "trace_summary": "可选，该表现点简短调用链"
    },
    {
      "location": { "file": "operator/pkg/gateway-api/routechecks/httproute.go", "line": 59, "symbol": "mergeStatusConditions" },
      "failure_mode": "merge 时重复 parent status；tlsroute/grpcroute 同源",
      "related_also": ["tlsroute.go:58", "grpcroute.go:179"]
    },
    {
      "location": { "file": "operator/pkg/gateway-api/gateway_reconcile.go", "line": 924, "symbol": "handleHTTPRouteReconcileErrorWithStatus" },
      "failure_mode": "错误路径上状态条目短暂丢失（先剪枝再检查顺序叠加语义比较问题）"
    }
  ],
  "related_symbols": [],
  "reachability": { "trace_summary": "…", "reachable_in_prod": true, "blocked_by": null },
  "recommendation": "在 prune/merge 路径使用 ParentRef 值比较或 cmp.Equal，勿对 ParentReference 整体用 ==/Contains"
}
```

**硬性规则（P0–P2，合并后单条 finding）：**

| 字段 | 规则 |
|------|------|
| `root_cause_key` | 非空；slug：`[a-z0-9]+(-[a-z0-9]+)*` |
| `trigger.defect_mechanism` | **恰好一段**根因原理（§5.1 三要素，见 mechanism-dedup spec） |
| `manifestations[]` | **≥1**；同一根因合并后 **≥2** 时终稿必须写 **表现点** 列表 |
| `title` | 描述根因类，不以单函数名为唯一标题 |
| `primary_location` | 最严重或 PR 核心改动点 |
| `severity` | `max(manifestations 隐含严重度)` |
| `recommendation` | **一条**统一修复建议 |

**P3**：可选 `manifestations`；无则沿用单点 **位置** 行。

### 5.2 `investigation-plan.json` 题目扩展

```json
{
  "id": "Q-RC-1",
  "kind": "correctness",
  "priority": "must",
  "template": "semantic_compare",
  "root_cause_key": "parentref-pointer-semantic-compare",
  "hypothesis": "ParentReference 含指针字段，用 == 或 slices.Contains 比较的是地址而非 API 语义值",
  "scopes": [
    "operator/pkg/gateway-api/status_route.go",
    "operator/pkg/gateway-api/routechecks/",
    "operator/pkg/gateway-api/gateway_reconcile.go"
  ],
  "scope": ["operator/pkg/gateway-api/routechecks/httproute.go"],
  "entry_ref": "Gateway Reconcile → setRouteStatuses → mergeStatusConditions",
  "peer_compare_refs": ["operator/pkg/httproute/", "operator/pkg/grpcroute/"],
  "grep_tokens": ["ParentReference", "slices.Contains", "DeepEqual", "=="]
}
```

- **`scopes[]`**：本题要验证的全部路径（主编排必填，当 `root_cause_key` 存在时）。
- **`scope`**：保留兼容单文件 probe 预算锚点；应为 `scopes[]` 子集或首屏入口文件。
- 同一 `root_cause_key` 在 plan 内 **只允许 1 道** `must` 题（`residual` 题除外，可引用同一 `grep_tokens` 但 `kind: residual`）。

### 5.3 plan 根级（可选）

```json
{
  "root_causes": [
    {
      "key": "parentref-pointer-semantic-compare",
      "summary": "ParentReference 指针字段语义比较失效",
      "grep_tokens": ["ParentReference", "slices.Contains", "DeepEqual"]
    }
  ]
}
```

assembler 可将未带 `root_cause_key` 的 finding 按 `root_causes[].grep_tokens` 回填键。

## 6. 主编排 3c：按根因出题

在现有 SKILL 3c 流程上增加 **先于分簇** 的步骤：

1. 从 `hunk-index` + `change-context` 归纳 **候选根因**（比较模式迁移、资源泄漏、鉴权遗漏等），每候选分配 `root_cause_key` + `grep_tokens`。
2. **每个候选根因 1 道 must 题**，`scopes[]` 覆盖 hunk 触及且 grep 可能命中的文件/目录。
3. **禁止**对同一 `root_cause_key` 再拆「每文件一题」；ripple 题若与已有 key 重叠 → 合并 scope 或降为 `should`。
4. `residual_peer_pattern`（bugfix）保持独立题，但可在 `hypothesis` 中引用 plan.`root_causes[]`。
5. `review-brief.md` 增加 **「待验证根因」**  bullet（≤5 条），供 probe 对齐。

**题数指引**：典型 bugfix PR `must` 题 3–5 道，其中 **逻辑类 ≤2 道 root_cause 题** + 1 道 residual（若 enable）+ 0–1 道 security/architecture。

## 7. probe-worker

### 7.1 同簇合并

1. 处理题目前读 `root_cause_key`；若本簇 `findings/probes/<id>.json` 已有同 key 的 `items[]` 条目 → **追加 `manifestations[]`**，不新建 item。
2. 单题带 `scopes[]` 时：按 scope 顺序验证，**一次 Write** 输出一条 finding + 多 manifestation（仅当各 scope `confirmed` 或部分 confirmed：confirmed 的入 manifestations，refuted 的不入；全 refuted 则 `verdict: refuted` 无 item）。
3. `defect_mechanism` 只在 finding 顶层写一次；各 manifestation 写自己的 `failure_mode` / `scenario`（可 abbreviated）。

### 7.2 与调用链 / peer 对比

- `call_chain_trace` / `peer_pattern_compare`：顶层一份；manifestation 可含 `trace_summary` 一句。
- `missing_call_chain` gate：顶层 `reachability` 须满足；单 manifestation 可不单独链式追溯若顶层已覆盖生产入口。

### 7.3 输出示例（片段）

```json
{
  "cluster_id": "logic-1",
  "answers": [
    {
      "question_id": "Q-RC-1",
      "verdict": "confirmed",
      "root_cause_key": "parentref-pointer-semantic-compare",
      "manifestation_count": 3
    }
  ],
  "items": [ { "...": "见 §5.1" } ]
}
```

## 8. report-assembler

### 8.1 合并顺序

```text
扁平化 items[]
  → root_cause pass（按 root_cause_key；无 key 则 grep_tokens 启发）
  → cluster pass（沿用 mechanism-dedup §7，合并结果写入 manifestations）
  → line÷20 去重
  → gates + severity
  → Markdown
```

### 8.2 root_cause pass

| 条件 | 动作 |
|------|------|
| 相同 `root_cause_key`（非空） | 合并为 1 条；`manifestations` 并集；`defect_mechanism` 取最长且含字段名者 |
| 无 key，但 plan.`root_causes[].grep_tokens` 与 finding 标题/机制命中 ≥2 token | 赋予 key 后合并 |
| 无 key，同 `finding_category` 且 `grep_tokens` 交集 ≥2（从 plan 题目或 finding 文本提取） | 合并，生成 slug key `inferred-<hash8>` |
| 合并后 `manifestations.length === 1` 且另有条目被并入 | 保留单条（不强制 ≥2） |

被合并项 → `rejected.json`，`reject_reason: duplicate_root_cause`，`merged_into: <id>`。

### 8.3 cluster pass 调整

- 合并时：若双方已有 `manifestations`，取并集；若仅 `location`，将 loser 迁入 `manifestations`。
- **不再**要求「同目录」作为合并必要条件（当 `root_cause_key` 相同或 root_cause pass 已合并时跳过目录约束）。

### 8.4 终稿：表现点（选项 A）

**当 `manifestations.length >= 2` 时**，替换原「位置 + 生产后果」为：

```markdown
#### P2 — ParentReference 指针字段用 ==/Contains 导致语义比较失效

- **根因原理**：…（`trigger.defect_mechanism`）
- **表现点**：
  1. `status_route.go:18` · `pruneRouteParentStatuses` — **后果**：跨命名空间剪枝失效…
  2. `routechecks/httproute.go:59` · `mergeStatusConditions`（及 tlsroute、grpcroute 同源）— **后果**：重复 parent status…
  3. `gateway_reconcile.go:924` · `handleHTTPRouteReconcileErrorWithStatus` — **后果**：错误路径状态短暂丢失…
- **场景**：（可选）仅当各表现点 scenario 差异大时写；否则省略本节或写顶层摘要
- **可达性**：…
- **建议**：…（一条统一修复）

```

**当 `manifestations.length === 1` 或缺失**：保持现有「**位置** + **根因原理** + **生产后果**」格式。

§4 结论可补充说明：`1 个 P2（含 3 处表现点）`（非强制，推荐）。

## 9. 变更文件清单

| 文件 | 变更 |
|------|------|
| `skills/review/SKILL.md` | 3c 按根因出题、`root_cause_key`/`scopes[]`、`root_causes[]` |
| `agents/probe-worker.md` | 簇内合并、manifestations、单 finding 多 scope |
| `agents/report-assembler.md` | root_cause pass、表现点终稿、duplicate_root_cause |
| `docs/installation.md` | 报告样例含表现点 |
| `scripts/verify-audit-code-plugin.sh` | rg `root_cause_key`、`manifestations`、`表现点`、`duplicate_root_cause` |
| `docs/superpowers/specs/2026-06-04-audit-code-mechanism-dedup-design.md` | 交叉引用本文；cluster pass 与目录约束说明 |

## 10. 验收标准

1. ParentReference / DeepEqual / `slices.Contains` 类试跑：§2 **至多 1 条** P2（correctness），终稿含 **≥2 个表现点**。
2. `investigation-plan` 中同一 `root_cause_key` **仅 1 道** must 逻辑题（residual 除外）。
3. `findings/probes/*.json` 同簇同 key **≤1** item（合并前临时多条须在 assembler 兜底为 1）。
4. `./scripts/verify-audit-code-plugin.sh` 通过新增检查。
5. 四节、R15、R16、`REVIEW_RESULT` 语义不变。

## 11. Spec 自检

- [x] 无 TBD / TODO
- [x] 与 question-driven、mechanism-dedup、report-quality 无矛盾
- [x] 用户确认：终稿形态 A（一因多表现点）
- [x] 单份 implementation plan 可覆盖
