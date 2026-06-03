# 设计增量：`peer-path-comparator` — 等同路径 / 同类模式比较

- 日期：2026-06-03
- 状态：已审阅（待实现）
- 父文档：[`2026-06-03-audit-pr-plugin-design.md`](./2026-06-03-audit-pr-plugin-design.md)（本增量将主文档升至 **v7**）
- 来源需求：用户反馈 — 对 finding 需质疑「同等处理模式在其它路径是否也有问题；若无，为何只改此处」；终稿须含 **同类路径比较** 小结
- 范围决策：**C — 先 A（局部平行分支）后 B（仓库同类模式，有条件、有上限）**

## 1. 目标

1. 对每条进入质询池的 **P0–P2** finding，在 `audit-challenger` 之前生成可验证的 **对等路径对照表**（局部 + 可选仓库）。
2. 供 `audit-challenger` 质询：对照是否过浅、结论是否与证据矛盾（**M13 / M14**）。
3. 供 `report-writer` 在 `fix_mark_should_fix` 终稿中输出 **同类路径比较** 小节。

**非目标（YAGNI）：**

- 不替代阶段 5 `similar-defect-scout`（bugfix 全库找**未修同类缺陷** → 新 finding）。
- 不为 P3 finding 跑仓库级 B（6a′ 不入队）。
- 不自动扩大修复范围（只论证「是否仅本路径需改」，不新增 should_fix 项除非 analyst 已提出）。

## 2. 与现有能力的关系

| 能力 | 区别 |
|------|------|
| `similar-defect-scout`（阶段 5） | 仅 bugfix；产出 **新** finding（`problem_type` = 仓库同类缺陷） |
| `§5.8 执行路径一致性` | 同一函数内多阶段/eligibility 与 yield 是否一致 |
| **`peer-path-comparator`（阶段 6a′）** | 对 **已有** finding 做 parity：兄弟分支 + 可选跨文件 analogue；**注解** finding，不新建 finding |

## 3. 编排（插入阶段 6）

```text
all-merged.json（阶段 6 合并）
  → 6a  subsequent-fix-scout
  → 6a′ peer-path-comparator   ← 新增
  → 6b  audit-challenger（逐条 ≤5 轮）
  → 7   report-writer
```

### 3.1 入队条件（6a′）

对 finding `F`，**同时满足**才委派 `peer-path-comparator`：

1. 未在 6a 因 `subsequent_fix` 淘汰；
2. `F.severity ∈ {P0, P1, P2}`；
3. `F` 非纯 `author_intended` 预淘汰项。

**P3：** 不进入 6a′（阶段 6 已在质询前淘汰）。

### 3.2 Agent：`peer-path-comparator`

| 项 | 内容 |
|----|------|
| 文件 | `plugins/audit/agents/peer-path-comparator.md` |
| 输入 | `findings/all-merged.json`、`effective-diff.json`、`intent.json` |
| 输出 | `$AUDIT_TMP/peer-comparisons.json` |
| 工具 | Read, Grep, Glob, Write（**仅** `peer-comparisons.json`） |
| 约束 | 静态只读仓库；禁止改代码；禁止把长 Grep/log 写入 JSON |

**A — 局部平行分支（必做）：**

1. Read finding 锚点（`code_refs` 主缺陷点）所在 **完整函数/方法** 或等价 handler 块。
2. 枚举 **兄弟路径**（≤8 条），`role` 取：`sibling_branch` | `other_phase` | `other_case` | `other_handler`。
3. 每条填：`same_pattern`、`same_issue`、`why_different`（当 `same_issue=false` 必填）、`evidence_refs`。
4. 给出 `local_conclusion`：`only_this_path_needs_fix` | `all_siblings_share_issue` | `not_applicable`。

**B — 仓库同类（条件 + 上限）：**

- **触发：** A 中至少一条 `same_pattern=true`，**或** finding 标题/描述含系统性/同类/其它路径等措辞。
- **手段：** 基于 anchor 符号、错误处理模板、选择器名等 **≤10 次** Grep/Glob；结果摘要写入 JSON，不贴原文。
- **上限：** `analogues` ≤5。
- **跳过：** `scope_repo.searched=false` 且 `skip_reason` 必填（如 `no_same_pattern_in_local`、`not_applicable_local`）。

### 3.3 主编排合并

质询开始前，主线程将 `peer-comparisons.json` 中对应项合并进 finding 草稿的 `peer_comparison` 字段；质询中 proposer 可修订，challenger 在 `challenges/` 记录争议。

质询 **accepted/downgraded** 且 severity 仍为 P0–P2 时，`findings-final` **必须**含非空 `peer_comparison`（`local_conclusion=not_applicable` 时须 challenger 在最后一轮 `accepted` 且注明理由）。

## 4. 数据契约

### 4.1 `peer-comparisons.json`

```json
{
  "version": 1,
  "generated_at": "ISO8601",
  "items": [
    {
      "finding_id": "F-001",
      "scope_local": {
        "anchor": { "path": "pkg/x.go", "line": 120, "symbol": "PreferSameNode" },
        "siblings": [
          {
            "path": "pkg/x.go",
            "line_start": 98,
            "line_end": 105,
            "role": "other_phase",
            "same_pattern": true,
            "same_issue": false,
            "why_different": "phase1 已 topologyPreferenceCandidate 过滤",
            "evidence_refs": ["pkg/x.go:102"]
          }
        ],
        "local_conclusion": "only_this_path_needs_fix",
        "local_conclusion_rationale": "≤200 字"
      },
      "scope_repo": {
        "searched": true,
        "skip_reason": null,
        "search_hints": ["topologyPreferenceCandidate"],
        "analogues": [
          {
            "path": "pkg/y.go",
            "line": 45,
            "symbol": "selectNode",
            "same_pattern": true,
            "same_issue": "unknown",
            "why_different": "不同选择器，语义不等价",
            "evidence_refs": ["pkg/y.go:45"]
          }
        ],
        "repo_conclusion": "isolated",
        "repo_conclusion_rationale": "≤200 字"
      },
      "report_blurb_zh": "终稿「同类路径比较」3–6 句摘要"
    }
  ]
}
```

**硬约束：** `siblings.length ≤ 8`；`analogues.length ≤ 5`；`same_issue=false` → `why_different` 非空。

### 4.2 `finding.peer_comparison`（写入 `findings-final`）

```json
"peer_comparison": {
  "local_conclusion": "only_this_path_needs_fix",
  "repo_conclusion": "isolated",
  "report_blurb_zh": "…",
  "table_rows": [
    {
      "location": "pkg/x.go:98-105",
      "same_pattern": "是",
      "same_issue": "否",
      "note": "phase1 已过滤"
    }
  ]
}
```

`table_rows` 建议 ≤8 行（A 优先，B 补充）；供 `report-writer` 直接渲染。

## 5. `audit-challenger` 增量

### 5.1 新 `challenge_type`

| 类型 | 场景 |
|------|------|
| `missing_peer_comparison` | 逻辑/业务类 finding 无 `peer_comparison` 或 6a′ 未覆盖 |
| `peer_survey_shallow` | 应列兄弟分支未列（如 two_phase 仅写单阶段） |
| `peer_conclusion_inconsistent` | `local_conclusion` / `repo_conclusion` 与 siblings/analogues 表矛盾 |

### 5.2 降级矩阵（追加）

| ID | 条件 | 处置 |
|----|------|------|
| **M13** | 声称仅本路径有缺陷；A 中存在代码等价 sibling 且 `same_issue=false`，但 `why_different` 无代码依据 | `withdrawn` 或要求补全后再审 |
| **M14** | 声称全库同类皆有缺陷；B 抽样显示多数路径有 guard 或语义不同 | 最高 **P2** 或 `withdrawn` |

### 5.3 每轮检查项（追加）

- [ ] 同类比较：`peer_comparison` 是否存在且 A 覆盖关键兄弟分支？
- [ ] 结论一致性：对照 M13/M14。

## 6. 终稿报告（`docs/README.md` 对齐）

在 `fix_mark_should_fix` 且存在严重问题时，于 **复现概率** 之后增加：

```markdown
- **同类路径比较** 其它等同/类似处理路径是否也涉及本缺陷？若否，为何本路径需要修改？（须与 peer_comparison 一致，有 path:line 依据）
```

`report-writer` 只读 `findings-final.json` 中的 `peer_comparison`；禁止从 `peer-comparisons.json` 单独 Read（除非主线程未合并 — 实现时应保证已合并）。

## 7. Token 与预算

| 项 | 上限 |
|----|------|
| 每条 finding A siblings | 8 |
| 每条 finding B analogues | 5 |
| Grep / 条 | 10 |
| Read / 次委派 | 15 文件量级（与现有 analyst 同量级） |

## 8. 实现清单（供 writing-plans）

1. `plugins/audit/agents/peer-path-comparator.md`
2. `plugins/audit/skills/audit-merged-pr/SKILL.md` — 阶段 6a′、Sub-agent 清单
3. `plugins/audit/agents/audit-challenger.md` — §5.1–5.3、M13/M14、Read `peer-comparisons.json`
4. `plugins/audit/agents/report-writer.md` — **同类路径比较**
5. `docs/README.md` — 报告结构增加一节
6. `docs/superpowers/specs/2026-06-03-audit-pr-plugin-design.md` — v7 交叉引用、§4.7c、验收 11–13
7. `scripts/verify-audit-plugin.sh` — 关键字与 agent 文件检查

## 9. 验收标准（增量）

1. 阶段 6 顺序为：6a → **6a′** → 6b。
2. 每条 `findings-final` 中 P0–P2 逻辑/业务类项含 `peer_comparison`（或 `not_applicable` 且最后一轮 challenger `accepted` 并记录理由）。
3. `peer-comparisons.json` 存在且 `items[].finding_id` 与 survivors 一一对应（跳过的 P3/subsequent_fix 除外）。
4. stdout 终稿在 should_fix 时含 **同类路径比较**。
5. M13/M14 可在 `challenges/` 追溯。

## 10. 已确认决策

| 议题 | 决策 |
|------|------|
| 比较范围 | **C**：先 A 后 B |
| 落地方案 | 新 agent `peer-path-comparator`，阶段 6a′ |
| P3 | 不跑 6a′ |
| 与 similar-defect-scout | 并存，职责不合并 |
| 报告 | 新增 **同类路径比较** 小节 |
