# GitHub Trend Star Filter Relocation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `github-trend` skill 的 Star 过滤从采集阶段移至分析阶段门禁，并按剔除原因分类输出报告。

**Architecture:** 仅修改 `plugins/news/skills/github-trend/SKILL.md` 编排指令。删除 Step 1.3 批量 Star 过滤；分析子 Agent 访问仓库页后先读 Star，不满足则返回 `skipped_low_stars`；`excluded_urls` 改为 `{history_analyzed, star_insufficient}` 分类结构；最终报告分两节展示剔除项。

**Tech Stack:** Claude Code plugin SKILL.md、agent-browser CLI、MemPalace MCP

**Spec:** [docs/superpowers/specs/2026-06-23-github-trend-star-filter-design.md](../specs/2026-06-23-github-trend-star-filter-design.md)

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `plugins/news/skills/github-trend/SKILL.md` | Modify | 唯一实现目标：编排流程、报告格式、困难上报 stage |
| `docs/superpowers/specs/2026-06-23-github-trend-star-filter-design.md` | Reference | 设计依据（已完成） |

---

### Task 1: 更新困难上报规范（删除 `1.3_stars`）

**Files:**
- Modify: `plugins/news/skills/github-trend/SKILL.md:52-68`

- [ ] **Step 1: 修改 stage 枚举行**

将第 52 行 `stage` 说明中的：

```
如 `1.1_trending` `1.2_history` `1.3_stars` `2_analyze` `3_mempalace_write` `4_report`
```

改为：

```
如 `1.1_trending` `1.2_history` `2_analyze` `3_mempalace_write` `4_report`
```

- [ ] **Step 2: 修改困难块示例**

将第 67 行示例：

```
- [info] 1.3_stars | https://github.com/owner/repo | star 数从页面文本解析，未找到独立计数元素
```

改为：

```
- [warning] 2_analyze | https://github.com/owner/repo | star 数无法可靠解析，跳过详细分析
```

- [ ] **Step 3: 验证无残留 `1.3_stars`**

```bash
rg -n "1\.3_stars" plugins/news/skills/github-trend/SKILL.md
```

Expected: 无匹配（Task 1 完成后）；若 Task 5 尚未执行，可能仍有 Step 1.3 节标题，Task 5 后再跑一次本命令确认零匹配。

- [ ] **Step 4: Commit**

```bash
git add plugins/news/skills/github-trend/SKILL.md
git commit -m "refactor(news): remove 1.3_stars stage from github-trend difficulty reporting"
```

---

### Task 2: 清理 Step 0 计数器

**Files:**
- Modify: `plugins/news/skills/github-trend/SKILL.md:198`

- [ ] **Step 1: 修改计数器初始化行**

将第 198 行：

```
6. 记录各阶段计数器初始值：`merged_count`、`after_history_count`、`after_stars_count`、`analyzed_count`（供最终报告头部使用）。
```

改为：

```
6. 记录各阶段计数器初始值：`merged_count`、`after_history_count`（供采集摘要使用）。最终报告头部的「总共分析项目」「分析失败项目」在 Step 4 按 `analysis_status` 实时统计，不预初始化。
```

- [ ] **Step 2: 验证旧计数器已移除**

```bash
rg -n "after_stars_count|analyzed_count" plugins/news/skills/github-trend/SKILL.md
```

Expected: 仍有匹配（Step 1.3 / 1.4 尚未改）；Task 5 完成后应零匹配。

- [ ] **Step 3: Commit**

```bash
git add plugins/news/skills/github-trend/SKILL.md
git commit -m "refactor(news): simplify github-trend step 0 counters"
```

---

### Task 3: 重构 Step 1 采集阶段（删除 1.3，分类 excluded_urls）

**Files:**
- Modify: `plugins/news/skills/github-trend/SKILL.md:237-271`

- [ ] **Step 1: 删除整个 `#### 1.3 Star 数量过滤` 节**

删除第 237–247 行（含 `filtered_stars.json` 落盘说明）。

- [ ] **Step 2: 在 1.2 节后、`#### 1.4` 前插入 excluded_urls 维护说明**

在 `filtered_history.json` 落盘说明之后、原 1.4 之前插入：

```markdown
主 Agent / 采集子 Agent 须初始化并维护分类剔除列表 `excluded_urls`：

```json
{
  "history_analyzed": [],
  "star_insufficient": []
}
```

- Step 1.2 的 `removed` URL 填入 `excluded_urls.history_analyzed`（去重、保持首次出现顺序）
- `star_insufficient` 在采集阶段保持空数组，由 Step 2 主 Agent 在收到 `skipped_low_stars` 时追加
- **不含**第 2 步 `failed` 或 `skipped_low_stars` 之外的分析失败项

`debug=true` 时可写入 `TMP_DIR/collect/excluded_urls.json` 快照（随 Step 2 追加更新）。
```

- [ ] **Step 3: 重写 `#### 1.4 输出最终候选者列表`**

将第 251–271 行替换为：

```markdown
#### 1.4 输出最终候选者列表

  ```markdown
  ## 采集结果

  - merged_count: X
  - after_history_count: Y
  - final_urls:
    - https://github.com/owner1/repo1
    - https://github.com/owner2/repo2
  - excluded_urls:
    - history_analyzed:
      - https://github.com/owner3/repo3
    - star_insufficient: （空，待 Step 2 填充）

  ## 执行困难

  （按困难上报规范填写；无则写「无」）
  ```

若 `after_history_count` 为 0，主 Agent 跳至第 4 步输出「今日无新项目」并结束（仍须输出「剔除已分析项目」「剔除 star 不足项目」与「执行困难汇总」；**跳过第 3 步 MemPalace 写入**）。
```

- [ ] **Step 4: 验证 Step 1 结构**

```bash
rg -n "#### 1\.[0-9]" plugins/news/skills/github-trend/SKILL.md
```

Expected: 仅 `1.1`、`1.2`、`1.4`（无 `1.3`）

```bash
rg -n "filtered_stars|after_stars_count" plugins/news/skills/github-trend/SKILL.md
```

Expected: 无匹配

- [ ] **Step 5: Commit**

```bash
git add plugins/news/skills/github-trend/SKILL.md
git commit -m "refactor(news): remove collect-phase star filter from github-trend"
```

---

### Task 4: 重构 Step 2 分析阶段（Star 门禁 + skipped_low_stars）

**Files:**
- Modify: `plugins/news/skills/github-trend/SKILL.md:273-329`

- [ ] **Step 1: 扩展 analysis_status 说明**

将第 277–279 行：

```markdown
每个分析子 Agent 结束时，主 Agent 须标记该项目为 `analysis_status: success` 或 `analysis_status: failed`：
- **success**：子 Agent 正常输出分析内容（含「未能从公开页面确认」等部分信息，但未标注「分析失败」）
- **failed**：子 Agent 输出含「分析失败」或中途无法完成分析
```

改为：

```markdown
每个分析子 Agent 结束时，主 Agent 须标记该项目 `analysis_status` 为以下三者之一：

- **success**：子 Agent 正常输出分析内容（含「未能从公开页面确认」等部分信息，但未标注「分析失败」）
- **failed**：子 Agent 输出含「分析失败」或中途无法完成分析（Star 已 ≥ 5000 但后续步骤失败）
- **skipped_low_stars**：Star < 5000 或无法可靠解析；子 Agent 返回极简结果，主 Agent 将 URL 追加到 `excluded_urls.star_insufficient`，**不拼接**项目报告块，**不计入** success/failed
```

- [ ] **Step 2: 重写分析子 Agent 执行指令**

将 `#### 分析子 Agent 执行指令` 下第 285–306 行替换为：

```markdown
#### 分析子 Agent 执行指令

1. /usr/sbin/agent-browser 访问 `https://github.com/<owner>/<repo>`
2. **Star 门禁**：读取 star 数
   - star ≥ 5000 → 继续步骤 3
   - star < 5000 或无法可靠解析 → 返回 `skipped_low_stars`（见下方格式），**禁止**继续 README 深挖；无法解析时上报 `[warning]` 困难（stage: `2_analyze`）
3. 从 README、About、仓库描述等**公开页面信息**提取，输出如下单项目的中文报告：

  ```markdown
  ## <owner>/<repo>

  **仓库地址**: https://github.com/<owner>/<repo>
  **github star 数量**

  ### 适用场景
  详细说明它项目适用的实际问题场景，描述必须大于 100 字

  ### 要解决的问题
  详细说明其要解决的技术问题，且必须大于 100 字

  ### 功能
  详细说明该项目的各个功能，每个功能文字至少大于 50 字

  ### 执行困难
  （按困难上报规范填写；无则写「无」）
  ```
```

- [ ] **Step 3: 在「分析失败时」块之前插入 skipped_low_stars 返回格式**

```markdown
Star 不足或无法解析时（`analysis_status: skipped_low_stars`）：

  ```markdown
  ## 执行结果

  - analysis_status: skipped_low_stars
  - url: https://github.com/<owner>/<repo>
  - stars: 1234（无法解析时写「未知」）

  ## 执行困难

  （无法解析 star 时上报 [warning]；无则写「无」）
  ```

主 Agent 收到 `skipped_low_stars` 后：追加 URL 至 `excluded_urls.star_insufficient`；不拼接正文；继续下一 URL。
```

- [ ] **Step 4: 更新主 Agent 收集说明（第 329 行附近）**

将：

```
主 Agent 收集每个子 Agent 的 markdown 输出及 `analysis_status`，按 `final_urls` 顺序排列，供第 4 步拼接；同时收集各「执行困难」块供汇总；并保留采集阶段的 `excluded_urls` 供第 4 步报告使用。
```

改为：

```
主 Agent 收集每个子 Agent 的 markdown 输出及 `analysis_status`，按 `final_urls` 顺序排列，供第 4 步拼接（**跳过** `skipped_low_stars` 项目，不纳入正文）；同时收集各「执行困难」块供汇总；维护分类 `excluded_urls`（`history_analyzed` 来自 Step 1，`star_insufficient` 来自本步 `skipped_low_stars`）供第 4 步报告使用。`debug=true` 时可在每次追加后更新 `TMP_DIR/collect/excluded_urls.json`。
```

- [ ] **Step 5: 验证 Step 2 关键词**

```bash
rg -n "skipped_low_stars|Star 门禁" plugins/news/skills/github-trend/SKILL.md
```

Expected: 至少 4 行匹配

- [ ] **Step 6: Commit**

```bash
git add plugins/news/skills/github-trend/SKILL.md
git commit -m "feat(news): add star gate to github-trend analyze sub-agent"
```

---

### Task 5: 更新 Step 3 MemPalace 写入约束

**Files:**
- Modify: `plugins/news/skills/github-trend/SKILL.md:335`

- [ ] **Step 1: 明确禁止写入 skipped 项目**

将第 335 行：

```
对第 2 步中 `analysis_status: success` 的每个 URL 调用 `mempalace_diary_write`（格式见 MemPalace 章节）。**禁止**写入 `failed` 项目。
```

改为：

```
对第 2 步中 `analysis_status: success` 的每个 URL 调用 `mempalace_diary_write`（格式见 MemPalace 章节）。**禁止**写入 `failed` 或 `skipped_low_stars` 项目。
```

- [ ] **Step 2: Commit**

```bash
git add plugins/news/skills/github-trend/SKILL.md
git commit -m "docs(news): clarify mempalace skip rules for skipped_low_stars"
```

---

### Task 6: 重构 Step 4 报告格式（分类剔除节）

**Files:**
- Modify: `plugins/news/skills/github-trend/SKILL.md:348-369`

- [ ] **Step 1: 更新第 4 步拼接说明**

将第 348 行：

```
主 Agent 将所有子 Agent 的项目 markdown **原样拼接**（禁止改写、禁止总结），输出到 **stdout**。分析失败的项目在报告中单独标注失败；`success` 项目计入「总共分析项目」计数。
```

改为：

```
主 Agent 将 `success` 与 `failed` 子 Agent 的项目 markdown **原样拼接**（禁止改写、禁止总结），输出到 **stdout**；`skipped_low_stars` 项目不拼接。`success` 计入「总共分析项目」；`failed` 计入「分析失败项目」；`skipped_low_stars` 不计入上述两项。
```

- [ ] **Step 2: 替换剔除报告节**

将报告中 `## 剔除分析项目` 整节（第 362–369 行）替换为：

```markdown
  ## 剔除已分析项目

  列出 `excluded_urls.history_analyzed` 中的 URL（MemPalace 历史命中）。**仅 URL 列表**，禁止附加说明。无则写：无

  - https://github.com/<owner>/<repo>

  ## 剔除 star 不足项目

  列出 `excluded_urls.star_insufficient` 中的 URL（Star < 5000 或无法解析）。**仅 URL 列表**，禁止附加说明。无则写：无

  - https://github.com/<owner>/<repo>
```

- [ ] **Step 3: 验证旧剔除节已移除**

```bash
rg -n "剔除分析项目|禁止.*附加原因" plugins/news/skills/github-trend/SKILL.md
```

Expected: 无匹配

```bash
rg -n "剔除已分析项目|剔除 star 不足项目" plugins/news/skills/github-trend/SKILL.md
```

Expected: 至少 2 行匹配

- [ ] **Step 4: Commit**

```bash
git add plugins/news/skills/github-trend/SKILL.md
git commit -m "feat(news): categorize excluded repos in github-trend report"
```

---

### Task 7: 更新异常处理表与执行原则

**Files:**
- Modify: `plugins/news/skills/github-trend/SKILL.md:392-418`

- [ ] **Step 1: 修改异常处理表「过滤后名单为空」行**

将：

```
| 过滤后名单为空 | 第 4 步输出「今日无新项目」，正常结束；跳过第 3 步 |
```

改为：

```
| 历史过滤后名单为空（`after_history_count == 0`） | 第 4 步输出「今日无新项目」，正常结束；跳过第 3 步；仍输出分类剔除节 |
```

- [ ] **Step 2: 在执行原则末尾追加一条**

在 `- **agent-browser CLI 调用命令，必须写全路径 `/usr/sbin/agent-browser`**` 之后追加：

```
- Star 过滤在 Step 2 分析门禁执行，采集阶段禁止批量访问仓库页读 Star
```

- [ ] **Step 3: Commit**

```bash
git add plugins/news/skills/github-trend/SKILL.md
git commit -m "docs(news): update github-trend exception handling for star filter move"
```

---

### Task 8: 全量验收（对照 spec §10）

**Files:**
- Verify: `plugins/news/skills/github-trend/SKILL.md`

- [ ] **Step 1: 运行验收 grep 清单**

```bash
cd /Users/weizhoulan/Documents/git/blueskills

echo "=== 应不存在 ==="
rg -n "1\.3_stars|#### 1\.3|filtered_stars|after_stars_count|analyzed_count|剔除分析项目" plugins/news/skills/github-trend/SKILL.md && exit 1 || echo "OK: 旧术语已清除"

echo "=== 应存在 ==="
rg -n "skipped_low_stars|history_analyzed|star_insufficient|Star 门禁|剔除已分析项目|剔除 star 不足项目|after_history_count == 0" plugins/news/skills/github-trend/SKILL.md
```

Expected: 第一段输出 `OK: 旧术语已清除`；第二段至少 7 行匹配

- [ ] **Step 2: 人工对照 spec 验收标准**

逐项确认 spec §10 五条验收标准在 SKILL.md 中有对应指令（无需自动化测试，本 skill 为编排文档）。

- [ ] **Step 3: 最终 Commit（若 Step 1–7 已分批提交则跳过）**

```bash
git status
```

Expected: `nothing to commit, working tree clean`

---

## Spec Coverage Checklist

| Spec § | 要求 | Task |
|--------|------|------|
| §4 | 移除 after_stars_count、analyzed_count | Task 2, 3 |
| §5.1 | 删除 Step 1.3 | Task 3 |
| §5.2 | excluded_urls 分类结构 | Task 3, 4 |
| §5.4 | after_history_count == 0 提前终止 | Task 3 |
| §5.5 | 删除 filtered_stars.json | Task 3 |
| §6 | Star 门禁 + skipped_low_stars | Task 4 |
| §6.4 | 删除 1.3_stars stage | Task 1 |
| §7 | 分类剔除报告节 | Task 6 |
| §8 | 异常处理、执行原则 | Task 7 |
| §10 | 验收标准 | Task 8 |
