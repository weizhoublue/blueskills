# 设计文档：audit-code 报告质量与四节终稿结构

- 日期：2026-06-04
- 状态：已审阅（2026-06-04）
- 范围：`plugins/audit-code`（skill `review`、agents、verify 脚本）
- 前置：头脑风暴确认（Gateway API PR #46296 试跑反馈）

## 1. 问题陈述

对 `audit-code:review` 的试跑（如 PR #46296）暴露终稿与 gate 质量问题：

1. **P0 误用**：将「影响三种 Route、两个 controller」等**改动面描述**标为 P0，未说明生产上如何坏。
2. **定位不足**：finding 缺少 `path:line`、函数/符号名，读者无法对应代码。
3. **噪音 finding**：函数过长、缺日志、缺单测、缺文档注释等不应作为审查结论。
4. **含糊风险**：如「slices.Contains 替换 reflect.DeepEqual 可能有边界」无输入/输出实例。
5. **结构臃肿**：含「做得好的地方」、摘要过短、章节过多。
6. **叙事不足**：未交代修改前问题、修改后达成、方案原理。

## 2. 目标

1. 终稿为**固定四节** Markdown（见 §5）。
2. **§1** 由 `change-context` 结构化叙事驱动，非 finding。
3. **§2 / §3** 仅含可核实缺陷；每条含位置、符号、场景、后果、可达性、建议。
4. Merger **拒收** meta-scope、噪音、含糊 scenario；DRY **封顶 P3**。
5. 保持 `REVIEW_RESULT` 语义：仅 **P0–P2** 驱动 `mark_should_fix`；**P3 可见但不驱动**（§2/§3 内 `#### P3`）。

## 3. 非目标

- 不引入 v2 质询（`REVIEW_ENABLE_CHALLENGE`）。
- 不改变「只读、不跑测试、stdout only」约束。
- 不替代 `audit` 插件。

## 4. 方案选择

采用**全链路方案**（change-context schema → analyst 约束 → merger gate → report-writer 模板），避免只改 writer 导致误报仍进入 `merged.json`。

## 5. 终稿结构（report-writer 硬性模板）

顶层：

```markdown
## Code Review 报告

## 1. 修改意图分析

- **审查范围**：…
- **修改前问题**：…
- **修改后达成**：…
- **方案原理**：…

## 2. 发现的 PR 自身缺陷

（`issue_origin=pr_introduced`；按 P0 → P1 → P2 → P3 排序；无则写「无。」）

#### P1 — 标题
- **位置**：`path:line` · `symbol`
- **相关**：`path:line` · `symbol`（来自 `related_symbols[]`，可无）
- **场景**：前置 → 触发 → 错误结果
- **生产后果**：…
- **可达性**：…
- **建议**：…

## 3. 发现的仓库中的残留缺陷（非本 PR 造成）

（`issue_origin=residual_existing`；格式同 §2；无则「无。」）

## 4. 结论

REVIEW_RESULT=mark_ignore|mark_should_fix
```

**硬性规则：**

- **禁止**「做得好的地方」「验证说明」独立节（验证一句可并入 §1 末尾，可选）。
- **§4** 仅一行 `REVIEW_RESULT=...`（R16）；禁止其它文字。
- **R15（全报告硬性）**：**禁止使用 Markdown 表格**表达任何内容——包括但不限于：
  - GitHub 风格 pipe 表（`| 列 | 列 |`、`|---|---|`）
  - HTML `<table>` / `<tr>` / `<td>`
  - 用表格呈现 finding 列表、严重度统计、路径对照、维度对比等  
  **一律改用** `###` / `####` 标题 + 嵌套无序列表（`- **标签**：值`）。`peer_path`、`related_symbols`、P0–P2 计数均用列表，不用表。
- **P3** 与 P0–P2 **同列表**，标题 `#### P3 — …`；不驱动 `REVIEW_RESULT`。

## 6. change-context：`pr_narrative`

`change-context-analyst` 在 `change-context.json` 增加：

```json
"pr_narrative": {
  "before_problem": "修改前存在的问题（1–4 句，可 cite path:line）",
  "after_fix": "本 PR 实现的行为（1–4 句）",
  "design_approach": "实现思路/原理（1–4 句）"
}
```

- 信息不足时写 `unknown` 并列入 `open_questions[]`，禁止编造。
- `feature_positioning`、`modules` 保留；**改动面、子系统范围**只出现在 §1 叙事，**不得**作为 finding。

## 7. Finding schema 扩展

在现有 schema（§10 of `2026-06-04-review-plugin-design.md`）上扩展：

```json
"location": {
  "file": "pkg/foo.go",
  "line": 42,
  "symbol": "pruneRouteParentStatuses"
},
"related_symbols": [
  { "file": "pkg/foo.go", "line": 200, "symbol": "setHTTPRouteStatuses" }
],
"finding_category": "correctness|performance|security|architecture|dry_duplicate|...",
"trigger": {
  "description": "…",
  "failure_mode": "须含可核对的生产后果与具体输入/字段取值",
  "scenario": {
    "precondition": "…",
    "trigger": "…",
    "bad_outcome": "…"
  }
}
```

- `location.file` + `location.line`：**必填**。
- `location.symbol`：**强烈建议**；无法定位时写 `unknown` 并降 `confidence`。
- `trigger.scenario` 三段：**必填**（merger 否则 `vague_no_scenario`）。

## 8. Merger 新增 Gate

| 条件 | `reject_reason` |
|------|-----------------|
| 标题/描述为改动面、资源类型数量、controller 名称枚举，且无具体 `failure_mode` | `meta_scope_not_a_defect` |
| `finding_category` ∈ 噪音黑名单 | `out_of_scope_style` |
| 缺 `location.file` 或 `location.line` | `gate_failed` |
| 缺 `trigger.scenario` 任一段或 `failure_mode` 无具体输入输出 | `vague_no_scenario` |
| `finding_category == dry_duplicate` 或标题匹配重复代码 | **severity 强制 P3**（保留在 merged，不拒收） |
| `reachable_in_prod: false` 且原 P0/P1 | 降至 P2 或 `unreachable_in_prod`（沿用） |

**噪音黑名单**（analyst 不得上报，merger 兜底拒收）：

- 函数过长 / 超过行数上限
- 缺少日志
- 缺少单元测试
- 缺少文档注释

## 9. Analyst 指令变更摘要

| Agent | 变更 |
|-------|------|
| `change-context-analyst` | 输出 `pr_narrative` |
| `correctness` / `security` / `performance` / `impact` | 新 schema；scenario 必填；禁噪音 |
| `architecture` | DRY 仅用 `finding_category: dry_duplicate`，**最高 P3**；禁 meta-scope |
| `readability` | 禁行数/注释/日志/测试类 finding |
| `residual-defect-scout` | 同 schema；仅 `residual_existing` |
| `finding-merger` | §8 规则 |
| `report-writer` | §5 四节模板 |
| `skills/review/SKILL.md` | 同步终稿结构与 gate 说明 |

## 10. P0–P3 语义（重申）

| 等级 | 含义 |
|------|------|
| P0 | 生产主路径崩溃/死锁/核心不可用 |
| P1 | 核心功能错误、数据错丢、可利用且影响生产的安全问题 |
| P2 | 边缘路径或特殊配置；有 workaround |
| P3 | 不影响正确性的改进项（含 **dry_duplicate**） |

**禁止**将「本 PR 触及核心模块 / N 种资源类型」标为 P0–P2。

## 11. 验收标准

1. 对 bugfix 类 PR 试跑：§1 含 before/after/design 三段；无 meta-scope P0。
2. 每条 §2/§3 finding 含 `path:line`、symbol（或 `unknown`）、scenario 三段。
3. 噪音类不出现在 `merged.json`（或仅在 `rejected.json`）。
4. 终稿无「做得好的地方」；§4 仅 `REVIEW_RESULT` 一行。
5. DRY 类仅为 P3，出现在 §2 或 §3 的 `#### P3` 下。
6. 终稿全文**无任何** Markdown/HTML 表格（人工或脚本抽检 + verify 脚本 rg）。
7. `./scripts/verify-audit-code-plugin.sh` 通过更新后的 rg 检查（含「禁止表格」关键词与反模式检测，见实施计划）。

## 11.1 report-writer 实施要点（R15）

`report-writer.md` 须在「硬性」小节**重复**上述 R15，并给出**反例 / 正例**各一段，避免模型默认用表排 finding：

反例（禁止）：

```markdown
| 等级 | 文件 | 问题 |
| P1 | foo.go | … |
```

正例（允许）：

```markdown
#### P1 — …
- **位置**：`foo.go:42` · `bar`
```

## 12. Spec 自检（2026-06-04）

- [x] 无 TBD / TODO
- [x] 与既有 `REVIEW_RESULT`、R15/R16 一致
- [x] P3 可见但不驱动结论（用户选 A）
- [x] 四节结构与用户指定一致
- [x] 范围限于 audit-code 插件，可单份 implementation plan 实施
