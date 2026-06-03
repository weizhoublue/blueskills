# 设计增量：阶段 5b finding 去重（dedupe-normalizer）

- 日期：2026-06-03
- 状态：已实现
- 父文档：[`2026-06-03-audit-pr-plugin-design.md`](./2026-06-03-audit-pr-plugin-design.md)

## 问题

四维 analyst 常对**同一根因**从不同视角各报一条（business eligibility / language yield guard / edge 兄弟路径），导致阶段 6 重复质询、token 膨胀。

## 方案

**阶段 5b**（在阶段 6 之前）：

1. 主编排 Shell（可选）：按 defect 锚点 path+line 桶生成 `dedupe-hints.json`
2. 委派 **`finding-dedupe-normalizer`** → `dedupe-result.json` + `superseded-by-dedupe.json`
3. 阶段 6 仅对 `canonical_items[]` 分配 `finding_id` 并进入 6a/6a′/6a″/6b

## 合并规则摘要

- D1–D4：同锚点 / 同 symbol+pattern / 同函数窗口 / 同根因多视角 → **合并**
- K1–K4：跨模块、独立安全链、problem_type=3 独立锚点 → **分开**

## canonical 字段

- `contributing_agents[]`、`dimensions[]`、`merged_from[]`、`dedupe_key`
- `source_agent`：组内 canonical 主责（辩护用）

## 验收

- 同一 `dedupe_key` 在 `all-merged` 仅出现一次
- `superseded-by-dedupe` 不进质询循环
