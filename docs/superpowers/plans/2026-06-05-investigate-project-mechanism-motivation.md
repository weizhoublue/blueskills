# investigate-project 机制动机层（W1–W3 / key_mechanisms）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `project-overview.json` 与 `features/<slug>.json` 上增加 `key_mechanisms[]`（W1–W3），并由 `report-quality-challenger` 以 **major** 检出浅层机制表述；`report-writer` 渲染「关键机制与设计动机」子列表。

**Architecture:** 不改变 L1–L5 编号。scout/digger 写素材时填可选 `key_mechanisms[]`；质审 target **A+B** 输出 `mechanism_motivation_audit[]`；validate 仅在字段存在时校验最小长度。integrations / overview-md 本轮不强制 W。

**Tech Stack:** Claude Code sub-agent Markdown、`report-features/SKILL.md`、`validate-analysis-report.sh`（jq）。

**Reference:** [`docs/superpowers/specs/2026-06-05-investigate-project-mechanism-motivation-design.md`](../specs/2026-06-05-investigate-project-mechanism-motivation-design.md)

**Conventions:**

- 动机缺失 **major**，**不**新增 blocking（除既有 L2/L4 blocking）。
- `key_mechanisms` 缺失 → 视为 `[]`，不强制每条 problems_solved 都有。
- 插件正文中文；agent `name` 英文 kebab-case。

---

## 文件结构

| 路径 | Task |
|------|------|
| `agents/report-quality-challenger.md` | 1 |
| `agents/project-scout.md` | 2 |
| `agents/feature-digger.md` | 3 |
| `agents/report-writer.md` | 4 |
| `skills/report-features/SKILL.md` | 5 |
| `scripts/validate-analysis-report.sh` | 6 |

---

## Task 1: report-quality-challenger

**Files:** Modify `plugins/investigate-project/agents/report-quality-challenger.md`

- [ ] **Step 1:** 在「多层因果模型」后插入 **§ 机制动机 W1–W3（与 L 正交）** — W1/W2/W3 表 + 分工口诀（L3 vs W2）。

- [ ] **Step 2:** 在「质量清单」下新增 **§ mechanism_motivation（target: project-overview, features/<slug>）** — 反模式表（手段复述、缺 W1/W2/W3、at_a_glance 过浅、principle 无动机）→ `major`。

- [ ] **Step 3:** 扩展输出 schema — `mechanism_motivation_audit[]` 示例；`issues[].dimension` 增加 `mechanism_motivation`；M1–M3 骨架（指向 `key_mechanisms` 或 narrative）。

- [ ] **Step 4:** `checklist_scores` — `project-overview` 与 `features/<slug>` 增加 `mechanism_motivation_ok`。

- [ ] **Step 5:** 质询模板追加 14–16（机制 W2/W1/W3）。

- [ ] **Step 6:** `description` frontmatter 补一句「含机制动机 W1–W3 质审」。

- [ ] **Step 7:** 验证

```bash
rg -q 'mechanism_motivation|mechanism_motivation_audit|key_mechanisms' plugins/investigate-project/agents/report-quality-challenger.md
```

- [ ] **Step 8:** Commit

```bash
git add plugins/investigate-project/agents/report-quality-challenger.md
git commit -m "feat(investigate-project): add W-layer mechanism motivation to quality challenger"
```

---

## Task 2: project-scout

**Files:** Modify `plugins/investigate-project/agents/project-scout.md`

- [ ] **Step 1:** 在 `scenarios[]` / `problems_solved[]` JSON 示例各增加：

```json
"key_mechanisms": [{
  "name": "",
  "w1_role": "",
  "w2_why_not_alternative": "",
  "w3_when_breaks": "",
  "evidence_tier": "doc_declared",
  "refs": [],
  "uncertainty_note": ""
}]
```

- [ ] **Step 2:** 工作步骤 +1 — 对含多组件协作的条目填 1–2 条 `key_mechanisms`；复杂 problems_solved 建议含 W3。

- [ ] **Step 3:** 七项自检 → 八项，+「机制动机：关键机制 W1+W2」。

- [ ] **Step 4:** 回灌段 — `mechanism_motivation` issues 优先补 `key_mechanisms` 与 narrative。

- [ ] **Step 5:** 深/浅示例各补一句 `key_mechanisms`（可选，在现有深示例段落后）。

- [ ] **Step 6:** Commit

```bash
git add plugins/investigate-project/agents/project-scout.md
git commit -m "feat(investigate-project): key_mechanisms in project-scout output"
```

---

## Task 3: feature-digger

**Files:** Modify `plugins/investigate-project/agents/feature-digger.md`

- [ ] **Step 1:** `scenarios[]` / `problems_solved[]` 示例增加同 Task 2 的 `key_mechanisms` 块。

- [ ] **Step 2:** `principle` 写作说明 — `activation_flow` / `processing_stages` / `external_interactions` 每条 statement 须含 **动作 + 动机（W2 一句）**。

- [ ] **Step 3:** 深度要求 — Disaggregated、Gateway+EPP、连接复用等主题建议 `key_mechanisms` ≥1。

- [ ] **Step 4:** 回灌 — 与 scout 相同，针对 `features/<slug>` quality-review issues。

- [ ] **Step 5:** Commit

```bash
git add plugins/investigate-project/agents/feature-digger.md
git commit -m "feat(investigate-project): key_mechanisms and principle W2 in feature-digger"
```

---

## Task 4: report-writer

**Files:** Modify `plugins/investigate-project/agents/report-writer.md`

- [ ] **Step 1:** 在 **NarrativeBlock 渲染规则** 增加：

```markdown
若 `key_mechanisms[]` 非空且长度 > 0，在 `### <title>` 下、证据行之后增加：

**关键机制与设计动机**
- **<name>**
  - **角色（W1）：** <w1_role>
  - **动机（W2）：** <w2_why_not_alternative>
  - **失灵或边界（W3）：** <w3_when_breaks>（若为空则省略该行）

禁止 markdown 表格；无 `key_mechanisms` 时不造此块。
```

- [ ] **Step 2:** 红线 — 禁止从 narrative 外补造 W 内容；仅渲染 JSON 已有字段。

- [ ] **Step 3:** Commit

```bash
git add plugins/investigate-project/agents/report-writer.md
git commit -m "feat(investigate-project): render key_mechanisms in overview.md"
```

---

## Task 5: report-features SKILL

**Files:** Modify `plugins/investigate-project/skills/report-features/SKILL.md`

- [ ] **Step 1:** 全局红线 R16 后增加 **R17（机制动机）** 一条：

```markdown
- **R17（机制动机）**：`scenarios` / `problems_solved` 对叙事中的关键机制须可回答 W1–W3；可选 `key_mechanisms[]`。质审按 `report-quality-challenger` 的 `mechanism_motivation`（major）。禁止「用于保持连接」类同义反复代替 W2。本轮不强制 integrations W。
```

（若已有 R17 编号则顺延为 R18，三处一致：SKILL、scout、digger 引用。）

- [ ] **Step 2:** 阶段 1 / 阶段 4 预检 bullet 增加 — 「若存在 `key_mechanisms`，每项 w1+w2 非空（validate 可选）」。

- [ ] **Step 3:** Commit

```bash
git add plugins/investigate-project/skills/report-features/SKILL.md
git commit -m "feat(investigate-project): R17 mechanism motivation in report-features SKILL"
```

---

## Task 6: validate-analysis-report.sh

**Files:** Modify `plugins/investigate-project/scripts/validate-analysis-report.sh`

- [ ] **Step 1:** 在 project-overview jq 块内、`ok_ps` 检查后追加：

```bash
km_ok=$(jq '[.scenarios[], .problems_solved[]] | .key_mechanisms // [] | .[] | (.name | length > 0) and ((.w1_role | length) >= 10) and ((.w2_why_not_alternative | length) >= 10)] | if length == 0 then true else all end' "$PO" 2>/dev/null || echo true)
[[ "$km_ok" == "true" ]] || err "某条 key_mechanisms 项缺 name/w1/w2 最小长度"
```

- [ ] **Step 2:** 对 `features/*.json` 抽样（若 glob 存在）同样 jq（可选 1 个文件或 all）：

```bash
for fj in "$ROOT"/features/*.json; do
  [[ -f "$fj" ]] || continue
  km_ok=$(jq '[.scenarios[], .problems_solved[]] | .key_mechanisms // [] | .[] | (.name | length > 0) and ((.w1_role | length) >= 10) and ((.w2_why_not_alternative | length) >= 10)] | if length == 0 then true else all end' "$fj" 2>/dev/null || echo true)
  [[ "$km_ok" == "true" ]] || err "$(basename "$fj") key_mechanisms 项不完整"
done
```

- [ ] **Step 3:** 运行（用临时最小 JSON 或跳过若无可测 REPORT_ROOT）— 至少脚本 `bash -n`：

```bash
bash -n plugins/investigate-project/scripts/validate-analysis-report.sh
```

- [ ] **Step 4:** Commit

```bash
git add plugins/investigate-project/scripts/validate-analysis-report.sh
git commit -m "test(investigate-project): validate key_mechanisms when present"
```

---

## Plan self-review

| Spec § | Task |
|--------|------|
| W vs L | 1, 2, 3 |
| key_mechanisms schema | 2, 3 |
| challenger audit | 1 |
| writer render | 4 |
| validate | 6 |
| A+B only | 5 明确 integrations 不强制 |
| major not blocking | 1 |

---

## Execution handoff

计划路径：`docs/superpowers/plans/2026-06-05-investigate-project-mechanism-motivation.md`

1. **Subagent-Driven** — 每 Task 子 agent + 评审  
2. **Inline** — 本会话 Task 1→6 直接改并提交  

回复 **1**、**2** 或 **「直接实现」**。
