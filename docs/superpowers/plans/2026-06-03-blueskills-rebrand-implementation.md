# blueskills Marketplace 重命名实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将仓库改造为可安装的 `weizhoublue/blueskills` marketplace，首个 plugin 为 `investigate-project`，入口 skill 为 `report-features`，并全仓替换旧标识。

**Architecture:** marketplace 根仅含 `marketplace.json`；plugin 位于 `plugins/investigate-project/`（`plugin.json` + `skills/report-features/SKILL.md` + `agents/`）。用户安装 `investigate-project@blueskills`，调用 `/investigate-project:report-features`。产物仍为 `<cwd>/analysis-report/`。

**Tech Stack:** Claude Code plugin/marketplace JSON、Skill/agent Markdown、bash/rg 校验。

**Spec:** [`docs/superpowers/specs/2026-06-03-blueskills-rebrand-design.md`](../specs/2026-06-03-blueskills-rebrand-design.md)

---

## 文件结构（目标）

| 路径 | 动作 |
| --- | --- |
| `.claude-plugin/marketplace.json` | 新建 |
| `plugins/investigate-project/.claude-plugin/plugin.json` | 新建 |
| `plugins/investigate-project/skills/report-features/SKILL.md` | 自 `skills/analyze-codebase/SKILL.md` 迁移+改 |
| `plugins/investigate-project/agents/*.md` | 自 `agents/` 迁移+改 |
| `skills/`、`agents/`（根） | 删除（迁移后） |
| `README.md` | 重写 |
| `docs/installation.md`、`docs/README.md` | 修改 |
| `docs/superpowers/specs/*.md`、`plans/*.md` | 全量替换旧名；主 spec 重命名 |
| `docs/superpowers/specs/2026-06-03-blueskills-plugin-design.md` | 自 `2026-06-02-code-analyzer-plugin-design.md` 重命名+更新 |

---

## Task 1: Marketplace 与 plugin 清单

**Files:**
- Create: `.claude-plugin/marketplace.json`
- Create: `plugins/investigate-project/.claude-plugin/plugin.json`

- [ ] **Step 1:** `mkdir -p .claude-plugin plugins/investigate-project/.claude-plugin`

- [ ] **Step 2:** 写入 `marketplace.json`（内容见 spec §4.1，`source`: `./plugins/investigate-project`）

- [ ] **Step 3:** 写入 `plugin.json`（`name`: `investigate-project`，`version`: `0.1.0`，见 spec §4.2）

- [ ] **Step 4:** 校验

```bash
python3 -c "import json; m=json.load(open('.claude-plugin/marketplace.json')); assert m['name']=='blueskills' and m['plugins'][0]['name']=='investigate-project'"
python3 -c "import json; p=json.load(open('plugins/investigate-project/.claude-plugin/plugin.json')); assert p['name']=='investigate-project'"
```

- [ ] **Step 5:** Commit

```bash
git add .claude-plugin/marketplace.json plugins/investigate-project/.claude-plugin/plugin.json
git commit -m "feat(marketplace): add blueskills catalog and investigate-project plugin manifest"
```

---

## Task 2: 迁移 agents 与 skill

**Files:**
- Move: `agents/` → `plugins/investigate-project/agents/`
- Move: `skills/analyze-codebase/` → `plugins/investigate-project/skills/report-features/`

- [ ] **Step 1:**

```bash
mkdir -p plugins/investigate-project/skills
git mv agents plugins/investigate-project/agents
git mv skills/analyze-codebase plugins/investigate-project/skills/report-features
rmdir skills 2>/dev/null || true
```

- [ ] **Step 2:** 编辑 `plugins/investigate-project/skills/report-features/SKILL.md`
  - 标题 `# report-features`
  - frontmatter `description` 提及 `report-features` / `investigate-project`
  - 防误写：检测 `plugins/investigate-project` 或 marketplace 克隆路径
  - 保留 `analysis-report` / `REPORT_ROOT` 全文

- [ ] **Step 3:** 编辑 `plugins/investigate-project/agents/report-writer.md` 页脚与 improvement-log 行（`investigate-project` 插件、`report-features` skill）

- [ ] **Step 4:** 其余 agent 若含 `code-analyzer` / `analyze-codebase` 先不改（Task 3 统一替换）

- [ ] **Step 5:** Commit

```bash
git add -A plugins/investigate-project/
git commit -m "refactor(plugin): move agents and report-features skill under investigate-project"
```

---

## Task 3: 全仓标识替换

**Files:** 所有 `*.md`、`*.json`（含 `docs/superpowers/**`）

- [ ] **Step 1:** 按 spec §5 **顺序** 执行替换（建议 `rg -l` 列出文件后分批）：
  1. `/code-analyzer:analyze-codebase` → `/investigate-project:report-features`
  2. `code-analyzer@analyze-code` → `investigate-project@blueskills`
  3. `analyze-codebase` → `report-features`（注意勿误改已正确的 `investigate-project` 目录名）
  4. `weizhoublue/analyze-code` → `weizhoublue/blueskills`
  5. 剩余 `code-analyzer`：安装/斜杠/页脚 → `investigate-project`；marketplace/repo → `blueskills`
  6. `analyze-code` → `blueskills`（repo/marketplace 语境）

- [ ] **Step 2:** 架构图目录树改为 `blueskills/` + `plugins/investigate-project/` 结构

- [ ] **Step 3:** 残留检查

```bash
rg -n 'analyze-codebase|code-analyzer@analyze-code|/code-analyzer:|blueskills@blueskills|/blueskills:' --glob '!*.git' || echo OK
rg -n 'weizhoublue/analyze-code' --glob '!*.git' || echo OK
```

- [ ] **Step 4:** Commit

```bash
git add -A
git commit -m "chore: rename identifiers to blueskills marketplace and investigate-project plugin"
```

---

## Task 4: 主 spec 重命名与 README

**Files:**
- Rename: `docs/superpowers/specs/2026-06-02-code-analyzer-plugin-design.md` → `2026-06-03-blueskills-plugin-design.md`
- Modify: `README.md`, `docs/README.md`, `docs/installation.md`
- Modify: 所有指向旧 spec 文件名的链接

- [ ] **Step 1:** `git mv` 主 spec 文件；更新标题与 §2 架构树（三层命名）

- [ ] **Step 2:** 重写根 `README.md`：marketplace 说明、安装三行命令、调用 `/investigate-project:report-features`、产物树、`docs/installation.md` 链接

- [ ] **Step 3:** 更新 `docs/installation.md` 命名表（marketplace / plugin / skill 三列）、迁移表、示例命令；删除「根目录 plugin.json」描述

- [ ] **Step 4:** Commit

```bash
git add README.md docs/ docs/superpowers/specs/
git commit -m "docs: align README and installation with blueskills marketplace layout"
```

---

## Task 5: 端到端验收

**Files:** 无（只读检查）

- [ ] **Step 1:** 运行 spec §8.1 结构脚本（全部通过）

- [ ] **Step 2:** 若本机有 Claude Code CLI：`claude plugin validate .`（在仓库根）

- [ ] **Step 3:** 手动 smoke test（文档记录于 PR/会话）：
  - `/plugin marketplace add weizhoublue/blueskills`（或本地路径）
  - `/plugin install investigate-project@blueskills`
  - `/investigate-project:report-features`

- [ ] **Step 4:** 确认 `plugins/investigate-project/skills/report-features/SKILL.md` 阶段 0 仍写 `analysis-report`

---

## 执行方式

Plan 已保存。可选：

1. **Subagent-Driven（本会话）** — 按 Task 1→5 逐 task 执行并 review  
2. **Parallel Session** — 新会话使用 executing-plans，批量执行并设置检查点  

请告知采用哪种方式开始实施。
