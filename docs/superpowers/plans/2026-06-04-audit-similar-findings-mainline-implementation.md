# similar-defect 发现项入主链 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 强制 `similar-defect-scout` 输出经 5b dedupe → 完整质询 → `findings-final` → `fix_mark_should_fix`，杜绝主编排将 similar 侧车为「后续改进」。

**Architecture:** 不新增 agent；在主编排 SKILL 增加 **Findings 主链不变式** + Shell `intake-manifest.json` 计数断言；收紧 dedupe / scout / edge / report-writer 契约；`verify-audit-plugin.sh` 静态验收。

**Tech Stack:** Claude Code plugin Markdown（`SKILL.md` + `agents/*.md`）、Bash `scripts/verify-audit-plugin.sh`、`rg`。

**Reference:** [`docs/superpowers/specs/2026-06-04-audit-similar-findings-mainline-design.md`](../specs/2026-06-04-audit-similar-findings-mainline-design.md)

**Conventions:** 正文中文；无 pytest；每 task 末尾跑 `./scripts/verify-audit-plugin.sh`；一 task 一 commit。

---

## 文件结构

| 路径 | 变更 |
|------|------|
| `plugins/audit/agents/finding-dedupe-normalizer.md` | similar 必读、K4 收紧 |
| `plugins/audit/agents/similar-defect-scout.md` | `must_enter_mainline`、schema、返回模板 |
| `plugins/audit/agents/edge-effect-analyst.md` | `config_family_asymmetry` |
| `plugins/audit/skills/audit-merged-pr/SKILL.md` | 不变式、manifest、断言、阶段 7 |
| `plugins/audit/agents/report-writer.md` | 禁止侧车、similar 报告要求 |
| `scripts/verify-audit-plugin.sh` | 新增 rg 检查 |
| `docs/superpowers/specs/2026-06-03-audit-pr-plugin-design.md` | §4.7 脚注（可选） |

---

## Task 1: finding-dedupe-normalizer — similar 必读 + K4

**Files:**
- Modify: `plugins/audit/agents/finding-dedupe-normalizer.md`

- [ ] **Step 1: 更新开篇与输入列表**

将第 10 行「及已并入的 `similar-unfixed`」改为明确必读：

```markdown
你是 **去重归一化员**（阶段 5b）。在阶段 6 质询之前，把 `business` / `language` / `security` / `edge-effects` / **`similar-unfixed`（若文件存在）** 中同一根因的多条 finding 合并为一条 canonical。
```

输入节将：

```markdown
- 若存在：`findings/similar-unfixed.json`
```

改为：

```markdown
- **若文件存在则必读**：`findings/similar-unfixed.json`（`items[]` 全部计入 `input_counts.similar_unfixed`；禁止忽略）
```

- [ ] **Step 2: 收紧 K4 表格**

在「### 必须保留分开」的 K4 行后追加：

```markdown
| K4b | **禁止**将 similar 批量的 `items` 标为 `out_of_scope` 或写入 `superseded` 且无 `superseded_by_dedupe_key` / `reason` |
| K4c | similar 默认 **单独** canonical；仅当 D1–D4 明确同锚点（同 path 且 line ±20）才可合并进 PR 内 finding |
```

- [ ] **Step 3: 增加 canonical 字段说明**

在「### 选 canonical」第 4 点「合并写入」列表后追加：

```markdown
- similar 来源 canonical 保留 `dimension: similar-unfixed`、`problem_type: 3`；可选 `similar_defect_meta`（见 spec `2026-06-04-audit-similar-findings-mainline-design.md` §3.3）
```

- [ ] **Step 4: 约束节增加计数**

在「## 约束」追加：

```markdown
- 若 `intake-manifest.json` 中 `similar_unfixed > 0` 但 `input_counts.similar_unfixed == 0` → 返回主线程 `error: similar_not_in_dedupe`
- `stats.in` 必须等于各源 items 之和（含 similar）
```

- [ ] **Step 5: 验证**

```bash
./scripts/verify-audit-plugin.sh
rg -n '若文件存在则必读|K4b|similar_not_in_dedupe' plugins/audit/agents/finding-dedupe-normalizer.md
```

Expected: verify 通过（Task 6 完成后全绿）；rg 命中三关键词

- [ ] **Step 6: Commit**

```bash
git add plugins/audit/agents/finding-dedupe-normalizer.md
git commit -m "feat(audit): require similar-unfixed in dedupe normalizer"
```

---

## Task 2: similar-defect-scout — 主链标记与 schema

**Files:**
- Modify: `plugins/audit/agents/similar-defect-scout.md`

- [ ] **Step 1: 扩展「任务」节**

在「## 任务」第 3 点后追加第 4–6 点：

```markdown
4. 每条 finding 使用与四维相同的 §6.4 schema（`code_refs`, `trigger`, `path_consistency` 或 `config_consistency`, `upstream_guards_considered` 等）。
5. 每条 finding **必须**含：
   - `must_enter_mainline: true`
   - `pr_fix_pattern_ref`（本 PR 已Demonstrated 的修复点 path:line）
   - `unfixed_evidence_refs[]`（未修位置 path:line 列表）
6. 初判 `severity`：与 PR 内同 pattern、同后果的平行遗漏 **不低于** PR 内同级（通常 P1；主路径 P0）。
```

- [ ] **Step 2: 新增「主链策略」小节**

```markdown
## 主链策略（HARD-GATE）

- 输出仅供阶段 5b dedupe 并入 `canonical_items`；**禁止**在返回主线程建议「后续 PR / 范围外处理」。
- 主编排将对 `items.length` 与 dedupe `input_counts.similar_unfixed` 做一致性断言。
```

- [ ] **Step 3: 更新返回主线程模板**

将返回块改为：

```markdown
## 返回主线程（≤8 行）

\`\`\`
- agent: similar-defect-scout
- items: N
- mainline_policy: all_items_must_reach_dedupe
- output: <AUDIT_TMP>/findings/similar-unfixed.json
\`\`\`
```

- [ ] **Step 4: 验证**

```bash
rg -n 'must_enter_mainline|mainline_policy|pr_fix_pattern_ref' plugins/audit/agents/similar-defect-scout.md
```

Expected: 各至少 1 处命中

- [ ] **Step 5: Commit**

```bash
git add plugins/audit/agents/similar-defect-scout.md
git commit -m "feat(audit): similar-scout must_enter_mainline and full schema"
```

---

## Task 3: edge-effect-analyst — config_family_asymmetry

**Files:**
- Modify: `plugins/audit/agents/edge-effect-analyst.md`

- [ ] **Step 1: 在「## §配置边缘效应」下追加 §4**

在「### 3. 默认值的隐式传播」之后、「### 配置类 finding 写法」之前插入：

```markdown
### 4. 同路径 / 同族配置对称性（config family symmetry）

- 当 PR 修改某**配置族**中一项（如 prefill 下 `cuda` 分支），须 Grep 同文件或同 chart 内**平行 key/分支**（`gpu`, `amd`, `xpu`, `tpu` 等命名模式）。
- 检查：本 PR 应用的修复（默认值、guard、字段补齐）是否在平行分支**同等存在**。
- bugfix PR 且仅修一族、平行分支未同等修复 → **edge finding**。
- `config_consistency.pattern`: `config_family_asymmetry`（可与 `similar-defect-scout` 重叠；5b dedupe 按 D2/D4 或 K4 处理）。
- 证据：`related_paths[]` 列出所有平行分支 path:line。
```

- [ ] **Step 2: 更新 pattern 枚举**

在 `config_consistency.pattern` 的扩展语义行（约第 61 行）将：

```markdown
`config_cross_file_mismatch` | `config_semantic_drift` | `implicit_default_propagation`
```

改为：

```markdown
`config_cross_file_mismatch` | `config_semantic_drift` | `implicit_default_propagation` | `config_family_asymmetry`
```

同处 JSON 示例的 `"pattern":` 行同步加入 `config_family_asymmetry`。

- [ ] **Step 3: 验证**

```bash
rg -n 'config_family_asymmetry' plugins/audit/agents/edge-effect-analyst.md
```

Expected: ≥2 处命中

- [ ] **Step 4: Commit**

```bash
git add plugins/audit/agents/edge-effect-analyst.md
git commit -m "feat(audit): edge analyst config family symmetry checks"
```

---

## Task 4: audit-merged-pr SKILL — 主链不变式与 manifest

**Files:**
- Modify: `plugins/audit/skills/audit-merged-pr/SKILL.md`

- [ ] **Step 1: 在「阶段 4」之后插入「Findings 主链不变式」**

（放在阶段 4 表格与阶段 5 之间）

```markdown
### Findings 主链不变式（HARD-GATE）

1. 阶段 6 的 `all-merged.json` **仅**来自 `dedupe-result.json` 的 `canonical_items[]`。
2. 若 `findings/similar-unfixed.json` 存在且 `items.length > 0`，则 5b 必须将其全部计入 dedupe；`input_counts.similar_unfixed` 与 manifest 一致，否则 stderr `similar findings not fed to dedupe` 且**退出码 1**。
3. 每条 similar item 须在 `canonical_items` 或 `superseded-by-dedupe`（含 key + reason）中可追溯；禁止 silent drop。
4. similar 来源 canonical 走与四维相同的 6a → 6a′ → 6a″ → 6b。
5. 阶段 7 / report-writer **仅**读 `findings-final.json`；**禁止**读 `similar-unfixed.json` 写结论或「后续改进」。
6. `problem_type=3` 且质询成立的 P0–P2 survivor **必须**参与 `fix_mark_should_fix`（含「仅 similar 成立」场景）。
```

- [ ] **Step 2: 在阶段 5 与 5b 之间插入 manifest 步骤**

```markdown
### 阶段 5a：findings intake manifest（Shell only）

```text
读取 findings/business.json, language.json, security.json, edge-effects.json,
      及若存在的 similar-unfixed.json
统计各 items.length → 写入 $AUDIT_TMP/findings/intake-manifest.json
schema: { version:1, sources:{ business, language, security, edge, similar_unfixed },
          policy:"all_sources_must_reach_dedupe_and_challenge_or_superseded" }
```
```

- [ ] **Step 3: 更新阶段 5b 委派说明**

将「委派时附：四维 `findings/*.json` 路径」改为：

```markdown
委派时附：四维 + **若存在的** `findings/similar-unfixed.json`、`findings/intake-manifest.json`；规则见 `finding-dedupe-normalizer.md`。
```

5b 完成后追加：

```markdown
4. **断言**（主编排 Shell 或 jq）：
   - `dedupe-result.input_counts.*` 与 manifest.sources 一致
   - `dedupe-result.stats.in == sum(manifest.sources)`
   - 若 `manifest.sources.similar_unfixed > 0` 且 `input_counts.similar_unfixed == 0` → 退出码 1
   - 失败则不进入阶段 6
```

- [ ] **Step 4: 更新阶段 7 fix_mark 要点**

在 `**fix_mark_should_fix**` 行后追加：

```markdown
- 含 `dimension=similar-unfixed` 或 `problem_type=3` 的 P0–P2 survivor 与 PR 内 defect 同等计入。
- **禁止**因「不在本 PR diff」对未质询的 similar 使用 fix_mark_ignore。
```

- [ ] **Step 5: 验证**

```bash
rg -n 'Findings 主链不变式|intake-manifest|similar findings not fed' plugins/audit/skills/audit-merged-pr/SKILL.md
```

Expected: 均命中

- [ ] **Step 6: Commit**

```bash
git add plugins/audit/skills/audit-merged-pr/SKILL.md
git commit -m "feat(audit): mainline invariants and intake manifest in SKILL"
```

---

## Task 5: report-writer — 禁止侧车 + similar 报告

**Files:**
- Modify: `plugins/audit/agents/report-writer.md`

- [ ] **Step 1: 在「输入」或 AUDIT_TMP 节增加禁止项**

```markdown
## 禁止（HARD-GATE）

- **禁止**读取 `findings/similar-unfixed.json`、`findings/all-merged.json` 未质询项写报告。
- **禁止**使用「后续改进 / 范围外 / 不在本 PR」描述未经 `findings-final` 质询成立的 similar 项。
```

- [ ] **Step 2: 增加 similar survivor 写法**

在报告结构说明中（「问题描述」附近）追加：

```markdown
- 对 `problem_type_label == 仓库同类缺陷` 的 survivor：须写清本 PR 已修模式（`pr_fix_pattern_ref` / `peer_comparison`）与未修位置（`unfixed_evidence_refs` 或 `similar_defect_meta`）；须含 **同类路径比较**（`peer_comparison`，列表表述，R15 禁止表格）。
```

- [ ] **Step 3: 验证**

```bash
rg -n '禁止.*similar-unfixed|仓库同类缺陷' plugins/audit/agents/report-writer.md
```

Expected: 均命中

- [ ] **Step 4: Commit**

```bash
git add plugins/audit/agents/report-writer.md
git commit -m "feat(audit): report-writer similar findings and no sidecar reads"
```

---

## Task 6: verify-audit-plugin.sh — 静态验收

**Files:**
- Modify: `scripts/verify-audit-plugin.sh`

- [ ] **Step 1: 在文件末尾 `echo "OK"` 之前追加**

```bash
rg -q '若文件存在则必读' plugins/audit/agents/finding-dedupe-normalizer.md
rg -q 'must_enter_mainline' plugins/audit/agents/similar-defect-scout.md
rg -q 'mainline_policy' plugins/audit/agents/similar-defect-scout.md
rg -q 'config_family_asymmetry' plugins/audit/agents/edge-effect-analyst.md
rg -q 'Findings 主链不变式' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'intake-manifest' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q 'similar findings not fed' plugins/audit/skills/audit-merged-pr/SKILL.md
rg -q '禁止.*similar-unfixed' plugins/audit/agents/report-writer.md
rg -q 'similar-unfixed' plugins/audit/skills/audit-merged-pr/SKILL.md
```

- [ ] **Step 2: 运行全量校验**

```bash
./scripts/verify-audit-plugin.sh
```

Expected: `OK: audit plugin structure`

- [ ] **Step 3: Commit**

```bash
git add scripts/verify-audit-plugin.sh
git commit -m "chore(audit): verify similar-defect mainline integration"
```

---

## Task 7（可选）: 父 spec 脚注

**Files:**
- Modify: `docs/superpowers/specs/2026-06-03-audit-pr-plugin-design.md`

- [ ] **Step 1: 在 §4.7 阶段 5 末尾追加**

```markdown
> **2026-06-04 增量：** similar 输出强制入主链，见 [`2026-06-04-audit-similar-findings-mainline-design.md`](./2026-06-04-audit-similar-findings-mainline-design.md)。
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-06-03-audit-pr-plugin-design.md
git commit -m "docs(audit): link similar-findings mainline spec from parent"
```

---

## 计划自检（对照 spec §1–§9）

| Spec 要求 | Task |
|-----------|------|
| 主链不变式 §2 | Task 4 |
| intake-manifest §2.1 | Task 4 |
| dedupe 必读 + K4 §3 | Task 1 |
| similar-scout §4.1 | Task 2 |
| edge symmetry §4.2 | Task 3 |
| 质询无豁免 §4.3 | Task 4（SKILL 不变式第 4 点） |
| fix_mark / report §5 | Task 4, 5 |
| verify §6 | Task 6 |
| 非目标 §8 | 未引入新 agent / P3 变更 |

---

## 完成标准

1. `./scripts/verify-audit-plugin.sh` 通过。
2. 人工 spot-check：SKILL 阶段 5b 委派列表含 `similar-unfixed.json`；阶段 7 无「读 similar 写结论」表述。
3. 设计 spec [`2026-06-04-audit-similar-findings-mainline-design.md`](../specs/2026-06-04-audit-similar-findings-mainline-design.md) §9 五条验收在文档层面可满足（运行时行为依赖主编排遵守 SKILL）。
