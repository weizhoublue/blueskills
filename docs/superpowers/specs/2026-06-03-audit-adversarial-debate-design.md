# 设计增量：质询双文书辩驳（方案 B）

- 日期：2026-06-03
- 状态：已实现
- 父文档：[`2026-06-03-audit-pr-plugin-design.md`](./2026-06-03-audit-pr-plugin-design.md)
- 关联：[`2026-06-03-audit-peer-path-comparison-design.md`](./2026-06-03-audit-peer-path-comparison-design.md)

## 1. 目标

质询方（challenger）与提出方（proposer / `source_agent`）为**平等辩驳**关系：每轮先有 challenge，再有 rebuttal；challenger **终裁**但须阅读并回应 rebuttal，不得在未处理 `counterclaims` 时 `withdrawn`。

## 2. 编排（每轮）

```text
round N:
  1. challenger → challenges/ 或 peer-challenges/  （resolution: needs_rebuttal | pending | 终裁）
  2. 若 needs_rebuttal → proposer → rebuttals/audit/ 或 rebuttals/peer/
  3. round N+1 challenger 必读上轮 rebuttal；终裁须填 debate_summary
```

适用：`peer-parity-challenger`（≤3）、`audit-challenger`（≤5）。

## 3. 目录

```text
$AUDIT_TMP/rebuttals/peer/<finding_id>-round-<N>.json
$AUDIT_TMP/rebuttals/audit/<finding_id>-round-<N>.json
```

## 4. rebuttal schema（摘要）

- `responses[]`：逐条回应 challenge，`stance`: defend | partial_concede | concede
- `counterclaims[]`：反驳质询逻辑（≤3），须 `evidence_refs`
- `stance_summary`: defend | partial_concede | proposer_withdraws

## 5. challenger 终裁约束

- `withdrawn` / `accepted` / `downgraded` **仅当** 当轮对应 rebuttal 已存在
- `debate_summary.unanswered_counterclaims` 必须为空
- 终裁 `rationale` 须引用 challenger 与 proposer 要点

## 6. 验收

1. 每轮 `needs_rebuttal` 后有对应 `rebuttals/` 文件
2. 无 rebuttal 的 `withdrawn` 不得出现（`proposer_withdraws` 除外）
