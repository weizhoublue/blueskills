# 设计文档：audit-code 根因机制、性能分级与启发式去重

- 日期：2026-06-04
- 状态：已审阅（2026-06-04）
- 范围：`plugins/audit-code`（skill `review`、agents、verify 脚本）
- 前置：
  - `docs/superpowers/specs/2026-06-04-audit-code-report-quality-design.md`（四节终稿、scenario、merger 基础 gate）
  - 试跑反馈（Gateway API PR #46296 类）：finding 有场景/后果但缺「为何这么写会错」；性能误标 P2；同根因多条未合并

## 1. 问题陈述

在上一轮报告质量改进后试跑仍暴露：

1. **缺根因原理**：条目含场景、生产后果、可达性、建议，但未说明**代码机制**——错在哪、为何该写法破坏不变量、如何连到 bad_outcome（例：ParentReference 比较与 `mergeStatusConditions`）。
2. **性能严重度偏高**：纯复杂度类（如 `pruneRouteParentStatuses` 中 O(m×n)）标为 P2；用户要求**纯性能一律 P3**，语义/状态类错误不得挂在 performance 维度。
3. **去重不足**：同一根因（ParentReference 比较语义 vs `reflect.DeepEqual`）在 `status_route.go` 与 `routechecks/*.go` 各出一条，且出现 P2+P3 重复表述；现有 merger 键 `file + line÷20 + 标题` 过粗，无法按机制聚类。

## 2. 目标

1. P0–P2 finding 必须含**代码级** `trigger.defect_mechanism`；终稿展示为 **根因原理**。
2. **维度分流**：语义/状态/比较错误 → `correctness`（可 P2）；纯性能 → `performance` 且 **merger 强制 P3**。
3. **启发式聚类合并**（不新增 `root_cause_id`）：同机制、同 category、位置/符号相关 → 单条 finding，`related_symbols` 并集。
4. 保持既有四节终稿、R15 禁表、R16 单行结论、`REVIEW_RESULT` 仍仅由 P0–P2 驱动。

## 3. 非目标

- 不引入 ML/embedding 去重服务。
- 不要求 analyst 手工维护全局 defect 注册表或 `root_cause_id` 字段。
- 不改变 investigate-issue / audit 插件边界。

## 4. 方案选择

采用**全链路方案 3**（schema → analyst 指令 → merger gate + 聚类 → report-writer → verify），与上一轮报告质量改进一致。拒绝「只改 report-writer」或「只改 merger」——上游无 `defect_mechanism` 时 merger 只能大量拒收，无法稳定产出根因段落。

## 5. Schema 扩展：`trigger.defect_mechanism`

在 `2026-06-04-audit-code-report-quality-design.md` §7 的 `trigger` 上增加：

```json
"trigger": {
  "defect_mechanism": "代码级机制：错在哪 + 为何该写法错 + 如何导致后果（可含 1–3 行关键逻辑或伪代码）",
  "description": "…",
  "failure_mode": "生产后果 + 具体字段/输入取值",
  "scenario": {
    "precondition": "…",
    "trigger": "…",
    "bad_outcome": "…"
  }
}
```

### 5.1 内容硬性要求（P0–P2）

`defect_mechanism` 必须显式覆盖三要素（可合并为一段，但缺一不可）：

| 要素 | 说明 |
|------|------|
| **错在哪** | 点名符号、字段、比较方式（如 `ParentReference.Group`、`slices.Contains` + `==`） |
| **为何这么写会错** | 语言/K8s/API 语义（nil 默认 vs 显式值、DeepEqual vs `!=` 等） |
| **如何连到后果** | 一步因果接到 `scenario.bad_outcome` / `failure_mode`，禁止只重复后果 |

**P3**：强烈建议填写；缺失不拒收，但 `confidence` 不得为 `high`。

### 5.2 反例 / 正例

**反例（merger → `vague_no_mechanism`）**

- 「ParentReference 比较逻辑变更可能影响 mergeStatusConditions」
- 「slices.Contains 与 reflect.DeepEqual 语义可能不一致」（无字段级说明）

**正例**

- 「`mergeStatusConditions` 用 `slices.Contains(parents, ref)` 时，spec 中 `ParentRef.Group` 为非 nil 字符串，status 中同 parent 的 `Group` 为 nil（省略默认）；`==` 判定不等，Contains 认为不存在而 append，产生重复 parent status。」

## 6. 性能 vs 正确性（用户选 B）

| 类型 | `finding_category` | 严重度 |
|------|-------------------|--------|
| 比较语义、状态重复/误删、不变量破坏 | `correctness` | 按影响 P0–P2 |
| 复杂度、分配、热路径、锁竞争（**无**状态/语义错误） | `performance` | analyst 自评 ≤P3；merger **强制 P3** |

### 6.1 performance-analyst

- 只产出纯性能项；**禁止**用 performance 描述「状态错乱、重复 entry、误删 status」等。
- 若审查对象实质为比较/协调逻辑错误，**不得**写入 `findings/performance.json`（由 correctness 覆盖）。

### 6.2 correctness-analyst

- 承担 `slices.Contains` / `reflect.DeepEqual` / `ParentReference` 等等价语义类问题，即使 PR 动机含「性能优化」。
- `defect_mechanism` 必填（P0–P2）。

### 6.3 finding-merger

- `finding_category == performance` → **强制 `severity: P3`**（与 `dry_duplicate` 并列，保留在 `merged.json`）。
- 若 `finding_category == performance` 且 `defect_mechanism` 或 `failure_mode` 命中状态/语义类关键词（见 §8.3 启发式列表）→ `rejected`, `reject_reason: misclassified_dimension`。

## 7. 启发式聚类去重（用户选 B）

在写入 `merged.json` 前，于既有「`file + line÷20 + 标题`」去重**之前**增加 **cluster pass**。

### 7.1 聚类条件

两条 finding **同时满足 ≥2 条** 则视为同根因簇：

1. **同类**：`finding_category` 相同；或均为 `correctness`（`architecture` 不与 `correctness` 互并，除非标题归一化后高度重合）。
2. **机制相似**：对 `defect_mechanism` + `failure_mode` 做小写、去标点、分词后，共享 **≥3** 个实词（长度≥4 或来自白名单：`parentreference`、`deepequal`、`slices`、`contains`、`reflect`、`mergestatus`、`prune`、`group`、`kind` 等，实施时在 merger 文档列出可扩展表）。
3. **位置相关**：`location.file` 同目录（`dirname` 相同）；或一方 `location` 出现在另一方 `related_symbols`；或双方 `related_symbols` 存在相同 `file:symbol`。

### 7.2 合并策略

- **保留** severity 最高者为主记录；同级取 `defect_mechanism` 更长且含具体字段名的一条。
- **`related_symbols`**：并集去重（按 `file`+`line`+`symbol`）。
- **`dimensions[]`**：合并来源 analyst 列表。
- **标题**：保留更具体者（含 symbol 名、动词明确者优先）。
- **被合并项**：写入 `rejected.json`，`reject_reason: duplicate_cluster`，附 `merged_into: <保留项 id>`（可选字段，便于调试）。

### 7.3 与旧去重键关系

- Cluster pass 先执行，再在簇内/簇外应用 `file + line÷20 + 归一化标题` 去重，避免同文件邻近行重复。

### 7.4 预期效果（试跑样例）

- `mergeStatusConditions`（httproute/tlsroute/grpcroute）+ `pruneRouteParentStatuses` 的 ParentReference 语义问题 → **1 条 correctness P2**，相关符号列全。
- `O(m×n)` 仅 **1 条 performance P3**，不与语义项合并。

## 8. Merger 新增 / 更新 Gate

| 条件 | 动作 |
|------|------|
| P0–P2 缺 `trigger.defect_mechanism` 或未覆盖 §5.1 三要素 | `rejected`, `reject_reason: vague_no_mechanism` |
| `finding_category == performance` | 强制 `severity: P3` |
| performance 项描述状态/语义错误（§8.3 关键词） | `rejected`, `reject_reason: misclassified_dimension` |
| 聚类重复 | `rejected`, `reject_reason: duplicate_cluster` |
| （沿用）`dry_duplicate` | 强制 P3 |
| （沿用）`vague_no_scenario`, `meta_scope_not_a_defect`, … | 不变 |

### 8.3 `misclassified_dimension` 关键词（节选，实施可扩）

`状态`、`重复`、`误删`、`parent status`、`mergeStatus`、`等价`、`DeepEqual`、`语义不一致`、`协调错误`、`不一致` — 出现在 performance 项的 `title` / `defect_mechanism` / `failure_mode` 时拒收。

## 9. report-writer 终稿字段顺序

每条 §2/§3 finding（P0–P3 同结构）：

```markdown
#### P2 — 标题
- **位置**：`path:line` · `symbol`
- **相关**：…
- **根因原理**：…（`trigger.defect_mechanism`）
- **场景**：前置 → 触发 → 错误结果
- **生产后果**：…（`failure_mode`）
- **可达性**：…
- **建议**：…
```

P3 的 performance / dry_duplicate 仍输出 **根因原理**（若有）；无机制时省略该行或写「见场景」——优先要求 analyst 对 P3 也写简短机制。

## 10. 变更文件清单

| 文件 | 变更 |
|------|------|
| `agents/correctness-analyst.md` | schema + `defect_mechanism` 必填说明 |
| `agents/performance-analyst.md` | 纯性能范围；禁止语义类；最高 P3 |
| `agents/security-analyst.md` | 同步 schema（`defect_mechanism`） |
| `agents/architecture-analyst.md` | 同步 schema；DRY 仍 P3 |
| `agents/residual-defect-scout.md` | 同步 schema |
| `agents/finding-merger.md` | cluster pass、新 gate、performance 封顶 |
| `agents/report-writer.md` | **根因原理** 行与字段顺序 |
| `skills/review/SKILL.md` | 全局红线与 reject_reason 表 |
| `scripts/verify-audit-code-plugin.sh` | rg `defect_mechanism`、`根因原理`、`duplicate_cluster`、`misclassified_dimension`、performance 封顶 |

## 11. 验收标准

1. 试跑 PR #46296（或同类）：每条 P0–P2 含可读 **根因原理**（三要素齐全）。
2. ParentReference / DeepEqual / slices.Contains **语义类**至多 **1 条** P2（correctness），无同义 P2+P3 对。
3. `pruneRouteParentStatuses` O(m×n) 仅为 **P3**（performance）。
4. `./scripts/verify-audit-code-plugin.sh` 通过更新检查。
5. 四节结构、R15、R16 与上一轮 spec 仍满足。

## 12. Spec 自检

- [x] 无 TBD / TODO
- [x] 与 `audit-code-report-quality-design`、REVIEW_RESULT、R15/R16 无矛盾
- [x] 用户确认：根因 A、性能分流 B、去重 B
- [x] 单份 implementation plan 可覆盖（不拆仓库外系统）
