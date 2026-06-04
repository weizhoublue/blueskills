# 设计增量：similar-defect-scout 发现项强制入主链

- 日期：2026-06-04
- 状态：待实现
- 父文档：[`2026-06-03-audit-pr-plugin-design.md`](./2026-06-03-audit-pr-plugin-design.md)
- 关联：[`2026-06-03-audit-finding-dedupe-design.md`](./2026-06-03-audit-finding-dedupe-design.md)、[`2026-06-03-audit-peer-path-comparison-design.md`](./2026-06-03-audit-peer-path-comparison-design.md)

## 1. 背景与问题

复盘一次 audit 运行时发现：

| 阶段 | 实际 | 问题 |
|------|------|------|
| 5 `similar-defect-scout` | 找到 12 个同类未修文件（含 gpu/amd/xpu/tpu prefill） | 发现能力正常 |
| 6 合并 | 仅将四维 findings 纳入 `all-merged.json` | similar 未进 dedupe / 质询主链 |
| 7 结论 | 将 similar 归为「范围外 / 后续改进」 | 违背终稿仅读 `findings-final`；真实缺陷被过滤 |

**根因归类：**

1. **编排契约不硬**：spec 已写 similar 可选进 5b dedupe，但 SKILL 未强制；主编排将 similar 当作侧车信息。
2. **终稿逻辑错误**：未经 peer/audit 质询即降级为「与 PR 无关」。
3. **edge-effect 覆盖缺口**（次要）：同族配置平行分支（cuda 修了、gpu 未修）未作为对称性检查项显式列出；应由 similar-scout 兜底，且兜底项必须入主链。

**产品决策（已确认）：** 选项 **A** — `similar-defect-scout` 发现项与 PR 内 finding **同等**进入 5b dedupe → 6a/6a′/6a″/6b 质询 → `findings-final` → `fix_mark_should_fix`。

## 2. Findings 主链不变式（主编排 HARD-GATE）

写入 `plugins/audit/skills/audit-merged-pr/SKILL.md`：

1. **单一入口**：阶段 6 的 `all-merged.json` **仅**来自 `dedupe-result.json` 的 `canonical_items[]`；禁止「四维 merged + similar 侧车」。
2. **similar 必入 dedupe**：若 `findings/similar-unfixed.json` 存在且 `items.length > 0`，则 5b 的 `input_counts.similar_unfixed` 必须等于该长度；为 0 或与 manifest 不一致 → stderr + **退出码 1**（`similar findings not fed to dedupe`）。
3. **similar 必出质询**：每条 similar item 在 5b 后必须出现在 `canonical_items`（K4 独立 canonical）或 `superseded-by-dedupe`（含 `superseded_by_dedupe_key` 与 `reason`）；禁止 silent drop。
4. **质询同等**：similar 来源 canonical 走完整 6a → 6a′ → 6a″ → 6b；`source_agent` 为 `similar-defect-scout`，辩护走 `finding-defense-mode`。
5. **终稿单一来源**：阶段 7 与 `report-writer` **仅**读 `findings-final.json`；**禁止**引用 `similar-unfixed.json` 写结论或「后续任务」。
6. **fix_mark**：survivor 含 `dimension=similar-unfixed` 或 `problem_type=3` 且 severity∈{P0,P1,P2} 且质询成立 → 与 PR 内 defect 相同参与 `fix_mark_should_fix`。

### 2.1 intake-manifest.json（5b 前，Shell 写入）

路径：`$AUDIT_TMP/findings/intake-manifest.json`

```json
{
  "version": 1,
  "sources": {
    "business": 0,
    "language": 0,
    "security": 0,
    "edge": 0,
    "similar_unfixed": 0
  },
  "policy": "all_sources_must_reach_dedupe_and_challenge_or_superseded"
}
```

5b 完成后主编排校验：

- `dedupe-result.input_counts.*` 与 manifest 各源一致；
- `dedupe-result.stats.in === sum(sources)`；
- 失败则不进入阶段 6 质询循环。

## 3. Dedupe（阶段 5b）

### 3.1 输入契约

`finding-dedupe-normalizer.md`：

- `similar-unfixed.json`：由「可选」改为 **若文件存在则必读**。
- `input_counts.similar_unfixed` 必填；与 manifest 不一致时在返回主线程标注 `error: count_mismatch`。

### 3.2 K4 收紧（与选项 A 对齐）

| 规则 | 行为 |
|------|------|
| K4 保留 | `problem_type=3` 且锚点不在本 PR effective 内 → **默认不合并**进 PR 内 finding |
| 新增禁止 | 整批 similar 标 `out_of_scope`；superseded 无 `superseded_by_dedupe_key` / `reason`；`stats.in` 未计入 similar |

每条 similar **默认**单独成为 `canonical_items` 一项（除非 D1–D4 明确同锚点：path 相同且 line ±20）。

### 3.3 Canonical 字段

- `dimension`: `similar-unfixed`（推荐，便于追溯）
- `problem_type`: `3`；`problem_type_label`: `仓库同类缺陷`
- `source_agent`: `similar-defect-scout`
- 可选 `similar_defect_meta`:

```json
"similar_defect_meta": {
  "pr_fix_pattern_ref": "path:line",
  "unfixed_locations": ["path:line"],
  "relationship": "same_config_family|same_symbol_pattern|same_guard_missing"
}
```

## 4. Agent 增量

### 4.1 similar-defect-scout

- 每条 finding 满足 §6.4 完整 schema（与四维相同）。
- 强制：`must_enter_mainline: true`
- 强制：`pr_fix_pattern_ref`、`unfixed_evidence_refs[]`
- 初判 severity：与 PR 内同 pattern 缺陷同后果时，**不低于** PR 内同级 severity（平行配置遗漏通常 P1，主路径 P0）。
- 返回主线程增加：`mainline_policy: all_items_must_reach_dedupe`
- **禁止**在返回主线程写「建议后续 PR 处理」。

### 4.2 edge-effect-analyst

新增 **§配置边缘效应 — 4. 同路径 / 同族配置对称性**（`config_family_asymmetry`）：

- PR 修改配置族中一项时，Grep 同文件/chart 平行分支（gpu/amd/xpu/tpu 等）。
- bugfix 且仅修一族、平行分支未同等修复 → edge finding。
- 与 similar-scout 重叠时由 5b dedupe D2/D4 合并或 K4 并存。

### 4.3 质询无豁免

- **6a subsequent-fix**：similar 同样适用；仅 `already_fixed` / `fix_in_progress`（high/medium）可剔除。
- **6a′/6a″**：须做 B 类 analogue 抽样；禁止仅以「不在本 PR diff」撤回（须矩阵 M2/M14 等）。
- **6b**：与 PR 内 finding 相同 withdrawn 标准。

## 5. 阶段 7 与 report-writer

### 5.1 fix_mark

| 场景 | 结果 |
|------|------|
| 仅 similar survivors（四维均 withdrawn） | `fix_mark_should_fix` |
| similar 全部 withdrawn，无其它 survivor | `fix_mark_ignore` |
| 引用 similar-unfixed 写 ignore | **禁止** |

### 5.2 report-writer

- 仅读 `findings-final.json`；禁止读 `similar-unfixed`、`all-merged` 未质询项。
- `仓库同类缺陷` survivor：须写清 PR 已修模式 + 未修位置；须含 `peer_comparison`（R15：列表表述，禁止表格）。

## 6. 验收

### 6.1 `scripts/verify-audit-plugin.sh`

- dedupe 文档含 similar 必读 / `similar_unfixed` 计数
- SKILL 含主链不变式 / intake-manifest / 失败退出文案
- similar-scout 含 `must_enter_mainline`
- edge 含 `config_family_asymmetry`
- SKILL/report 含禁止侧车读 similar 终稿

### 6.2 失败模式表

| ID | 检测 | 处置 |
|----|------|------|
| F1 | manifest.similar>0 但 dedupe input_counts.similar_unfixed==0 | 退出码 1 |
| F2 | dedupe stats.in < sum(manifest) | 退出码 1 |
| F3 | 阶段 7 引用 similar-unfixed 写结论 | 编排违规 |
| F4 | 报告「后续改进」无 finding_id | report-writer 禁止 |
| F5 | edge 未扫配置族 | similar 兜底；F1–F2 保证进主链 |
| F6 | superseded 无 key/reason | dedupe 约束 + 主编排校验 |

## 7. 改动文件清单

| 文件 | 变更 |
|------|------|
| `plugins/audit/skills/audit-merged-pr/SKILL.md` | 不变式、manifest、断言、阶段 7 |
| `plugins/audit/agents/finding-dedupe-normalizer.md` | similar 必读、K4 |
| `plugins/audit/agents/similar-defect-scout.md` | schema、must_enter_mainline |
| `plugins/audit/agents/edge-effect-analyst.md` | config_family_asymmetry |
| `plugins/audit/agents/report-writer.md` | 禁止侧车、similar 报告要求 |
| `scripts/verify-audit-plugin.sh` | 静态 rg |
| `docs/superpowers/specs/2026-06-03-audit-pr-plugin-design.md` | §4.7 脚注指向本文（可选） |

## 8. 非目标

- 不新增独立 intake-gate agent。
- 不改变 P3 不进 `findings-final`。
- 不将 similar-scout 并入 edge（会漏 PR 外锚点）。
- 首期不做 fixture 集成测试（仅静态 verify）。

## 9. 验收标准（实现完成时）

1. bugfix PR 产生 `similar-unfixed.json` 且 items>0 时，dedupe `input_counts.similar_unfixed` 匹配。
2. 每条 similar 进入 `canonical_items` 或可追溯 `superseded-by-dedupe`。
3. 成立 similar survivor 出现在 stdout 报告与 `fix_mark_should_fix`。
4. `verify-audit-plugin.sh` 通过。
5. 主编排无法在未经质询时将 similar 写为「后续改进」。
