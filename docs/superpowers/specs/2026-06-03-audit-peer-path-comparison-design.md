# 设计增量：`peer-path-comparator` + `peer-parity-challenger` — 等同路径比较

- 日期：2026-06-03
- 状态：已审阅 v2.1（**模式 2**：1 次对照 + peer ≤2 轮 + audit ≤3 轮交叉验证）
- 父文档：[`2026-06-03-audit-pr-plugin-design.md`](./2026-06-03-audit-pr-plugin-design.md)（主文档 **v8**）
- 来源需求：等同路径比较 + 专质询；audit 后续轮次可补强 peer，但不重复已结案议题
- 范围决策：**C — 先 A（局部）后 B（仓库，有条件）**

## 1. 目标

1. **6a′** 一次性生成 `peer-comparisons.json`（A 兄弟分支 + 可选 B 仓库 analogue）。
2. **6a″** `peer-parity-challenger` 对每条 P0–P2 finding **最多 2 轮**专质询（M13/M14、对照深浅、结论一致性），写入 `peer-challenges/`。
3. **6b** `audit-challenger` **最多 3 轮**全链路质询；**可读 peer 结案**，在调用链/触发/严重级证据下**交叉验证** peer，**禁止**重复 peer 线已 accepted 的议题（除非本轮提供**新** `path:line`）。
4. 终稿含 **同类路径比较**（来自 `findings-final.peer_comparison`）。

**非目标：** 不替代 `similar-defect-scout`；不为 P3 跑 6a′/6a″；peer 线 `withdrawn` 后不再进入 audit 质询。

## 2. 与现有能力的关系

| 能力 | 区别 |
|------|------|
| `similar-defect-scout`（阶段 5） | bugfix 全库找**未修**同类 → **新** finding |
| `§5.8 执行路径一致性` | 同函数多阶段/eligibility 与 yield |
| **`peer-path-comparator`（6a′）** | **1 pass** 对照表，不质询 |
| **`peer-parity-challenger`（6a″）** | **≤2 轮/finding**，仅 peer 议题 |
| **`audit-challenger`（6b）** | **≤3 轮/finding**，全链路 + peer **交叉验证** |

## 3. 编排（阶段 6）

```text
all-merged.json
  → 6a   subsequent-fix-scout
  → 6a′  peer-path-comparator     （1 pass / finding → peer-comparisons.json）
  → 6a″  peer-parity-challenger   （≤2 轮 / finding → peer-challenges/）
  → 6b   audit-challenger          （≤3 轮 / finding → challenges/）
  → 7    report-writer
```

### 3.1 入队（6a′ / 6a″ 相同）

对 finding `F`：

1. 未因 `subsequent_fix` 淘汰；
2. `F.severity ∈ {P0, P1, P2}`；
3. 非 `author_intended` 预淘汰。

**P3：** 不进入 6a′ / 6a″。

### 3.2 Agent：`peer-path-comparator`（6a′，无质询轮次）

| 项 | 内容 |
|----|------|
| 文件 | `plugins/audit/agents/peer-path-comparator.md` |
| 轮次 | **1**（单次委派；**无** 1–5 轮循环） |
| 输出 | `$AUDIT_TMP/peer-comparisons.json` |
| 工具 | Read, Grep, Glob, Write（仅上述 JSON） |

**A（必做）：** 完整函数 + 兄弟路径 ≤8。  
**B（条件）：** `same_pattern=true` 或系统性措辞；analogues ≤5；Grep ≤10/条。

主编排将条目合并为 `F.peer_comparison` 草稿，供 6a″ 使用。

### 3.3 Agent：`peer-parity-challenger`（6a″，≤3 轮 / finding）

| 项 | 内容 |
|----|------|
| 文件 | `plugins/audit/agents/peer-parity-challenger.md` |
| 轮次 | **每条 finding 最多 2 轮**（`round` 1..2） |
| 输入 | `peer-comparisons.json`、`F`（含 `peer_comparison`）、`intent.json` |
| Write | **仅** `$AUDIT_TMP/peer-challenges/<finding_id>-round-<N>.json` |
| proposer | **始终为** `F.source_agent`（修订 `peer_comparison` / 回应质询） |

**每轮必扫：** `missing_peer_comparison`、`peer_survey_shallow`、`peer_conclusion_inconsistent`；适用 **M13 / M14**。

**结案写入** `$AUDIT_TMP/peer-challenges/<finding_id>-final.json`：

```json
{
  "finding_id": "F-001",
  "peer_rounds": 2,
  "peer_line_resolution": "accepted|withdrawn|downgraded",
  "peer_comparison_final": { },
  "matrix_rule_ids": ["M13"]
}
```

| `peer_line_resolution` | 主编排处置 |
|------------------------|------------|
| `withdrawn` | `findings-rejected`，**跳过 6b** |
| `accepted` / `downgraded` | 更新 `F.peer_comparison` → 进入 **6b** |

`round == 3` 仍争议 → `peer_line_resolution: inconclusive`，默认 **不** 进入 `fix_mark_should_fix`（除非 audit 线推翻，见 §5.2）。

### 3.4 Agent：`audit-challenger`（6b，≤5 轮 / finding）

| 项 | 内容 |
|----|------|
| 轮次 | **每条 finding 最多 3 轮** |
| 前置 Read | `peer-challenges/<finding_id>-final.json`（必须） |
| Write | `$AUDIT_TMP/challenges/<finding_id>-round-<N>.json`（现有） |

**与 peer 线的分工：**

| audit **会做** | audit **禁止**（除非本轮有新 `evidence_refs`） |
|----------------|-----------------------------------------------|
| 调用链、触发场景、§5.7 严重级、作者意图、后续已修、路径一致性 §5.8 | 重复问「兄弟分支是否已查」等 peer 线已 **accepted** 的议题 |
| 若深挖后发现 sibling **也应**有问题 → `peer_reopened_by_audit` + 新 path:line | 无新证据重申 M13/M14 已结案点 |
| 核对 `peer_comparison_final` 与触发/入口证据是否矛盾 | 把 5 轮全部用于等同路径 |

**新 `challenge_type`（仅 audit）：** `peer_reopened_by_audit`（须附 `new_evidence_refs[]` 与 `contradicts_peer_round`）。

## 4. 数据契约

### 4.1 `peer-comparisons.json`

（同 v1；见 §4.1 原 schema，`siblings` ≤8，`analogues` ≤5。）

### 4.2 `peer-challenges/<finding_id>-round-<N>.json`

```json
{
  "finding_id": "F-001",
  "round": 1,
  "challenger": "peer-parity-challenger",
  "challenge_types": ["peer_survey_shallow"],
  "severity_review": { "matrix_rule_id": "M13", "proposed_action": "require_more_peer_evidence" },
  "resolution": "revise|withdrawn|accepted|downgraded",
  "required_peer_evidence": { "full_function_read": true, "siblings_min": 2 }
}
```

### 4.3 `finding.peer_comparison`（6a″ 结束后 → 6b 输入）

```json
"peer_comparison": {
  "local_conclusion": "only_this_path_needs_fix",
  "repo_conclusion": "isolated",
  "peer_line_resolution": "accepted",
  "report_blurb_zh": "…",
  "table_rows": [ ]
}
```

`table_rows` 建议 ≤8 条；供 `report-writer` 转为**嵌套 bullet 列表**（**禁止**渲染为 markdown 表格，见主 spec **R15**）。

`findings-final` 中 P0–P2 成立项 **必须**含 `peer_comparison` 且 `peer_line_resolution == accepted`（或 audit 末轮显式确认 `not_applicable`）。

## 5. 降级矩阵与检查项

| ID | 主责 agent | 说明 |
|----|------------|------|
| **M13** | peer-parity-challenger（6a″） | 仅本路径有缺陷但 sibling 等价且无依据 `why_different` |
| **M14** | peer-parity-challenger（6a″） | 声称全库同类皆有问题但 B 抽样不支持 |
| M13/M14（复核） | audit-challenger（6b） | 仅当 `peer_reopened_by_audit` + 新证据 |

**audit 每轮检查项（追加）：**

- [ ] 已 Read `peer-challenges/*-final.json`？
- [ ] 本轮是否重复 peer 已 accepted 议题？
- [ ] 若质疑 peer，是否带 `new_evidence_refs`？

## 6. 终稿报告

`fix_mark_should_fix` 时在 **复现概率** 之后输出 **同类路径比较**（来自 `peer_comparison`，与 `peer-comparisons.json` / `peer-challenges` 一致；**列表表述，禁止表格**，R15）。

## 7. Token 与轮次预算

| 阶段 | 每条 finding 上限 |
|------|-------------------|
| 6a′ 对照 | 1 pass |
| 6a″ peer 质询 | **2 轮** |
| 6b audit 质询 | **3 轮** |
| 硬顶（可选 env） | `peer_round + audit_round ≤ 5`（默认 2+3） |

## 8. 实现清单

1. `plugins/audit/agents/peer-path-comparator.md`
2. `plugins/audit/agents/peer-parity-challenger.md` **（新）**
3. `plugins/audit/agents/audit-challenger.md` — Read peer-final、§3.4、`peer_reopened_by_audit`
4. `plugins/audit/skills/audit-merged-pr/SKILL.md` — 6a′ / 6a″ / 6b 顺序与轮次
5. `plugins/audit/agents/report-writer.md`
6. `scripts/verify-audit-plugin.sh`
7. 主 spec §4.7c–4.7d

## 9. 验收标准

1. 顺序：6a → 6a′ → **6a″** → 6b。
2. 每条进入 6b 的 finding 存在 `peer-challenges/<id>-final.json`。
3. peer 线 `withdrawn` 的 finding 无 `challenges/<id>-round-1.json`（未进 audit）。
4. audit 的 `challenges/` 可含 `peer_reopened_by_audit` 且带新证据。
5. 终稿含 **同类路径比较**。

## 10. 已确认决策

| 议题 | 决策 |
|------|------|
| 模式 | **2**：1 pass + peer ≤3 + audit ≤5 |
| peer 轮次 | **≤3 / finding**（`peer-parity-challenger`） |
| audit 与 peer | 交叉验证、不重复已结案；可 `peer_reopened_by_audit` |
| 对照 agent 轮次 | `peer-path-comparator` **仅 1 pass**，无 5 轮 |
| 比较范围 | C：先 A 后 B |
