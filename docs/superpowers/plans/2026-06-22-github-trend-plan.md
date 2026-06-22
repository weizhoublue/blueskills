# GitHub Trend Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `blueskills` 中新增 `news` 插件及 `github-trend` skill，实现 GitHub 趋势项目采集、MemPalace 去重、star 过滤、串行分析与 stdout 日报输出。

**Architecture:** 单 `SKILL.md` 主编排 + Task 子 Agent（采集 1 个、分析 N 个串行），对齐 `finance/global-market` 模式。网页操作优先 `agent-browser`，MemPalace 用于历史去重与记录。

**Tech Stack:** Claude Code plugin（`plugin.json` + `SKILL.md`）、agent-browser CLI、MemPalace MCP

**Spec:** [docs/superpowers/specs/2026-06-22-github-trend-design.md](../specs/2026-06-22-github-trend-design.md)

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `plugins/news/.claude-plugin/plugin.json` | Create | 插件元数据 |
| `plugins/news/skills/github-trend/SKILL.md` | Create | 完整编排指令 |
| `.claude-plugin/marketplace.json` | Modify | 注册 `news` 插件 |

---

### Task 1: 创建 news 插件 scaffold

**Files:**
- Create: `plugins/news/.claude-plugin/plugin.json`

- [ ] **Step 1: 创建目录**

```bash
mkdir -p plugins/news/.claude-plugin plugins/news/skills/github-trend
```

- [ ] **Step 2: 写入 plugin.json**

创建 `plugins/news/.claude-plugin/plugin.json`：

```json
{
  "name": "news",
  "displayName": "News",
  "version": "0.1.0",
  "description": "GitHub 趋势项目日报采集与分析；github-trend skill",
  "keywords": [
    "news",
    "github",
    "trending",
    "mempalace"
  ],
  "license": "MIT"
}
```

- [ ] **Step 3: 验证 JSON 合法**

```bash
python3 -m json.tool plugins/news/.claude-plugin/plugin.json > /dev/null && echo OK
```

Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add plugins/news/.claude-plugin/plugin.json
git commit -m "feat(news): add plugin scaffold for github-trend skill"
```

---

### Task 2: 编写 SKILL.md — YAML 头部、调用场景、全局变量

**Files:**
- Create: `plugins/news/skills/github-trend/SKILL.md`

- [ ] **Step 1: 创建 SKILL.md 头部与配置节**

写入 `plugins/news/skills/github-trend/SKILL.md` 开头部分：

```markdown
---
name: github-trend
description: 采集 OSS Insight 与 GitHub Trending 当日热门仓库，过滤已分析与低 star 项目，串行分析并输出日报。
---

# Skill: github-trend

**采集 GitHub 趋势项目，MemPalace 去重后串行分析，输出 stdout 日报**

## 调用场景

**适用**
- 用户手动调用（如 `/news:github-trend` 或「跑一下今日 GitHub 趋势」）时，生成当日趋势项目分析报告

**不适用**
- 用户未明确要求调用本 skill 时

## 配置与全局变量

`debug`: 默认为 `true`。

**启用条件**：用户如在运行指令中明确要求（如包含「关闭 debug」「debug=false」「关闭调试」等类似表述）时，将 `debug` 置为 `false`；用户说「开启 debug」「debug=true」时置为 `true`；否则保持默认值。

`TMP_DIR`: 主 Agent 初始化时根据本地真实时间生成 `/tmp/github_trend_<yymmddhhmmss>/`（如 `260622143000`）。创建失败时降级为 `./tmp/github_trend_<yymmddhhmmss>/`。

**仅在 `debug=true` 时**创建 `TMP_DIR` 并落盘中间产物；`debug=false` 时不创建目录、不写中间文件。

主 Agent 必须将 `TMP_DIR`、`debug` 告知所有子 Agent。
```

- [ ] **Step 2: 验证文件存在且 frontmatter 正确**

```bash
head -5 plugins/news/skills/github-trend/SKILL.md
```

Expected: 包含 `name: github-trend` 和 `debug` 默认值说明

- [ ] **Step 3: Commit**

```bash
git add plugins/news/skills/github-trend/SKILL.md
git commit -m "feat(news): add github-trend skill header and config"
```

---

### Task 3: 编写 SKILL.md — 工具规范（agent-browser + MemPalace + 降级）

**Files:**
- Modify: `plugins/news/skills/github-trend/SKILL.md`

- [ ] **Step 1: 追加工具使用规范节**

在 `SKILL.md` 末尾追加：

```markdown
---

## 工具使用规范

### agent-browser 优先原则

所有网页访问（OSS Insight、GitHub Trending、各仓库页）必须遵循：

1. 先执行 `agent-browser skills get core` 加载工作流
2. 使用 agent-browser CLI 进行导航、快照、数据提取
3. agent-browser 失败时，按顺序降级：
   - Tavily extract skill
   - Exa web fetch MCP
   - Firecrawl scrape MCP

**禁止**在未尝试 agent-browser 的情况下直接使用其他搜索/抓取工具。

启动前检查：

```bash
agent-browser --version
```

不可用则终止，提示：`npm i -g agent-browser && agent-browser install`

### MemPalace MCP 使用

MemPalace 用于历史去重与记录已分析仓库。

固定参数：
- `agent_name`: `"claude"`
- `wing`: `"github-trending"`
- `room`: `"diary"`
- `topic`: `"analyzed-repos"`（统一 topic，禁止按仓库拆分 topic）

常见操作：

1. **搜索历史记录**（去重用）：
   ```
   mempalace_search(query="<owner>/<repo>", wing="github-trending", room="diary")
   ```
   命中则视为已分析，从候选名单移除。

2. **写入已分析记录**：
   ```
   mempalace_diary_write(
     agent_name="claude",
     wing="github-trending",
     topic="analyzed-repos",
     entry="[YYYY.MM.DD.HH.MM.SS] https://github.com/<owner>/<repo>"
   )
   ```
   时间戳使用本地真实时间，禁止用模型截止时间。

MemPalace 不可用时终止流程（无法完成去重与记录）。

### Debug 日志格式

当 `debug=true` 时，子 Agent 在每次操作后更新对应 debug JSON 文件：

```json
{
  "logs": [
    {
      "timestamp": "YYYY-MM-DDTHH:mm:ssZ",
      "action": "browser_navigate | browser_extract | memory_read | memory_write | file_write",
      "query": "完整参数或 URL",
      "result": "返回结果前 100 字",
      "length": 1234
    }
  ],
  "stats": {
    "browser_calls": 0,
    "memory_reads": 0,
    "memory_writes": 0,
    "file_writes": 0
  }
}
```

采集子 Agent 写 `TMP_DIR/debug/collect.json`；每个分析子 Agent 写 `TMP_DIR/debug/analyze_<owner>__<repo>.json`。
```

- [ ] **Step 2: 验证节标题存在**

```bash
rg -n "agent-browser 优先原则|MemPalace MCP 使用|Debug 日志格式" plugins/news/skills/github-trend/SKILL.md
```

Expected: 3 行匹配

- [ ] **Step 3: Commit**

```bash
git add plugins/news/skills/github-trend/SKILL.md
git commit -m "feat(news): add tool usage rules to github-trend skill"
```

---

### Task 4: 编写 SKILL.md — 第 0 步初始化 + 临时目录结构

**Files:**
- Modify: `plugins/news/skills/github-trend/SKILL.md`

- [ ] **Step 1: 追加执行流程第 0 步**

```markdown
---

## 执行流程

### 第 0 步：准备与初始化

1. **获取当前真实时间**：本地时区当前时间（禁止模型截止时间、禁止凭记忆猜测）。
2. **检查 agent-browser**：`agent-browser --version`；失败则终止。
3. **检查 MemPalace MCP**：确认工具可用；失败则终止。
4. **解析 debug 开关**：按用户指令或默认值 `true`。
5. **创建 TMP_DIR**（仅 `debug=true`）：
   ```
   TMP_DIR/
   ├── collect/
   ├── analyze/
   └── debug/
   ```
   创建失败时降级 `./tmp/github_trend_<yymmddhhmmss>/`。
6. 记录各阶段计数器初始值：`merged_count`、`after_history_count`、`after_stars_count`、`analyzed_count`（供最终报告头部使用）。
```

- [ ] **Step 2: 验证**

```bash
rg -n "第 0 步" plugins/news/skills/github-trend/SKILL.md
```

- [ ] **Step 3: Commit**

```bash
git add plugins/news/skills/github-trend/SKILL.md
git commit -m "feat(news): add step 0 initialization to github-trend skill"
```

---

### Task 5: 编写 SKILL.md — 第 1 步采集子 Agent

**Files:**
- Modify: `plugins/news/skills/github-trend/SKILL.md`

- [ ] **Step 1: 追加第 1 步完整指令**

```markdown
### 第 1 步：采集子 Agent

主 Agent 启动**一个**采集子 Agent（Task），完成 1.1–1.4 全流程。子 Agent prompt 必须包含：`TMP_DIR`、`debug`、MemPalace 参数、agent-browser 优先原则、debug JSON 格式。

#### 1.1 趋势榜采集

| 来源 | URL | 数量 |
|------|-----|------|
| OSS Insight | `https://ossinsight.io/trending?period=past_24_hours` | 前 20 |
| GitHub Trending | `https://github.com/trending` | 默认页全部（约 25） |

- 使用 agent-browser 访问页面，提取 `https://github.com/<owner>/<repo>` 格式 URL
- 规范化：去掉尾部 `/`、query、fragment；统一小写 owner/repo 用于去重
- 合并两源列表，按 `owner/repo` 去重
- 单源失败时继续另一源；**两源均失败则终止**
- `debug=true` 时写入：
  - `TMP_DIR/collect/ossinsight_urls.json` → `{"urls": [...], "count": N}`
  - `TMP_DIR/collect/github_trending_urls.json` → 同上
  - `TMP_DIR/collect/merged_urls.json` → `{"urls": [...], "count": N}`

#### 1.2 MemPalace 历史过滤

对每个 merged URL 调用：
```
mempalace_search(query="<owner>/<repo>", wing="github-trending", room="diary")
```

- 有命中 → 移除（已分析过）
- 无命中 → 保留
- `debug=true` 时写入 `TMP_DIR/collect/filtered_history.json`：
  ```json
  {"kept": [...], "removed": [...], "kept_count": Y, "removed_count": Z}
  ```

#### 1.3 Star 数量过滤

对 kept 列表中每个 URL，agent-browser 访问仓库页，读取 star 数。

- star < 5000 → 剔除
- star ≥ 5000 → 保留
- 无法读取 star 时：记录到 `removed` 并注明原因，不终止整体流程
- `debug=true` 时写入 `TMP_DIR/collect/filtered_stars.json`：
  ```json
  {"kept": [{"url": "...", "stars": 12345}], "removed": [{"url": "...", "stars": 100, "reason": "below_threshold"}], "kept_count": Z}
  ```

#### 1.4 写入 MemPalace

对最终 kept 列表每个 URL：
```
mempalace_diary_write(
  agent_name="claude",
  wing="github-trending",
  topic="analyzed-repos",
  entry="[YYYY.MM.DD.HH.MM.SS] https://github.com/<owner>/<repo>"
)
```

#### 采集子 Agent 输出（返回主 Agent）

```markdown
## 采集结果

- merged_count: X
- after_history_count: Y
- after_stars_count: Z
- final_urls:
  - https://github.com/owner1/repo1
  - https://github.com/owner2/repo2
```

若 `after_stars_count` 为 0，主 Agent 跳至第 3 步输出「今日无新项目」并结束。
```

- [ ] **Step 2: 验证四小节标题**

```bash
rg -n "1\.[1-4]" plugins/news/skills/github-trend/SKILL.md
```

Expected: 匹配 1.1、1.2、1.3、1.4

- [ ] **Step 3: Commit**

```bash
git add plugins/news/skills/github-trend/SKILL.md
git commit -m "feat(news): add collection sub-agent steps to github-trend skill"
```

---

### Task 6: 编写 SKILL.md — 第 2 步分析子 Agent

**Files:**
- Modify: `plugins/news/skills/github-trend/SKILL.md`

- [ ] **Step 1: 追加第 2 步**

```markdown
### 第 2 步：串行项目分析

主 Agent 对 `final_urls` **逐个、串行**启动分析子 Agent（**禁止并行**）。

每个分析子 Agent prompt 必须包含：目标 URL、`TMP_DIR`、`debug`、报告格式、语言要求（技术名词英文、说明中文）、禁止克隆代码。

#### 分析子 Agent 执行指令

1. agent-browser 访问 `https://github.com/<owner>/<repo>`
2. 从 README、About、仓库描述等**公开页面信息**提取：
   - 该项目要解决的问题
   - 该项目的功能
3. **禁止**克隆仓库、浏览源码目录、读 commit 历史
4. 信息不足时写「未能从公开页面确认」，禁止编造

#### 单项目报告格式（子 Agent 输出）

```markdown
## <owner>/<repo>

- **仓库地址**: https://github.com/<owner>/<repo>
- **要解决的问题**: （中文说明，技术名词保留英文）
- **功能**: （中文说明，列举核心功能点）
```

分析失败时：

```markdown
## <owner>/<repo>

- **仓库地址**: https://github.com/<owner>/<repo>
- **要解决的问题**: 分析失败：<错误原因>
- **功能**: 分析失败
```

#### 落盘（仅 debug=true）

- `TMP_DIR/analyze/<owner>__<repo>.md` — 写入上述 markdown
- `TMP_DIR/debug/analyze_<owner>__<repo>.json` — 操作日志

主 Agent 收集每个子 Agent 的 markdown 输出，按 `final_urls` 顺序排列，供第 3 步拼接。
```

- [ ] **Step 2: 验证**

```bash
rg -n "串行项目分析|禁止并行" plugins/news/skills/github-trend/SKILL.md
```

- [ ] **Step 3: Commit**

```bash
git add plugins/news/skills/github-trend/SKILL.md
git commit -m "feat(news): add serial analysis sub-agent steps to github-trend skill"
```

---

### Task 7: 编写 SKILL.md — 第 3 步整合 + 异常处理 + 执行原则

**Files:**
- Modify: `plugins/news/skills/github-trend/SKILL.md`

- [ ] **Step 1: 追加第 3 步、异常处理、执行原则**

```markdown
### 第 3 步：整合报告（stdout only）

主 Agent 将所有分析子 Agent 的 markdown **原样拼接**（禁止改写、禁止总结），输出到 **stdout**。

**禁止**将最终汇总报告写入文件。

#### 最终报告格式

```markdown
# GitHub Trending 日报

生成时间: YYYY.MM.DD HH:MM:SS（本地时区）
数据来源: OSS Insight (past 24h, top 20) + GitHub Trending (默认页)
候选项目数: X → 历史过滤后: Y → star 过滤后: Z → 本次分析: N

---

（按顺序拼接各项目分析 markdown，禁止改写）

---

### 调试统计信息
```

`debug=true` 时在报告末尾追加：

```markdown
### 调试统计信息

- 采集阶段 browser 调用次数: X
- 分析阶段 browser 调用次数: Y
- MemPalace 读取次数: Z
- MemPalace 写入次数: W
- 中间产物路径: <TMP_DIR>
```

主 Agent 读取 `TMP_DIR/debug/*.json`，累加各文件 `stats`。缺失文件则跳过，不中断。

#### 空结果报告

历史或 star 过滤后无候选时：

```markdown
# GitHub Trending 日报

生成时间: YYYY.MM.DD HH:MM:SS（本地时区）

今日无新项目（所有候选均已分析过或 star 不足 5000）。
```

---

## 异常处理

| 场景 | 处理 |
|------|------|
| agent-browser 不可用 | 终止，提示安装命令 |
| MemPalace 不可用 | 终止 |
| 单源采集失败 | 继续另一源 |
| 两源均失败 | 终止 |
| 过滤后名单为空 | 输出「今日无新项目」，正常结束 |
| 单项目分析失败 | 记录错误，继续下一个 |
| TMP_DIR 创建失败 | 降级 `./tmp/...` |
| debug JSON 缺失 | 统计时忽略 |

---

## 执行原则

- 优先获取本地真实时间
- 网页操作 agent-browser 优先
- 分析子 Agent 必须串行
- 最终报告仅 stdout，中间产物仅 debug 模式落盘
- 事实描述基于页面可见信息，不足时明确标注，禁止编造
```

- [ ] **Step 2: 验证 SKILL.md 完整性**

```bash
wc -l plugins/news/skills/github-trend/SKILL.md
rg -c "第 [0-3] 步" plugins/news/skills/github-trend/SKILL.md
```

Expected: 文件 ≥ 200 行；匹配 4 个步骤标题

- [ ] **Step 3: Commit**

```bash
git add plugins/news/skills/github-trend/SKILL.md
git commit -m "feat(news): complete github-trend skill orchestration flow"
```

---

### Task 8: 注册 marketplace 插件

**Files:**
- Modify: `.claude-plugin/marketplace.json`

- [ ] **Step 1: 在 plugins 数组末尾添加 news 条目**

在 `.claude-plugin/marketplace.json` 的 `plugins` 数组中，`finance` 条目之后添加：

```json
    {
      "name": "news",
      "source": "./plugins/news",
      "description": "GitHub trending project daily digest and analysis (github-trend skill)."
    }
```

完整 `plugins` 数组应包含 `coding`、`productivity`、`finance`、`news` 四项。

- [ ] **Step 2: 验证 JSON**

```bash
python3 -m json.tool .claude-plugin/marketplace.json > /dev/null && rg '"news"' .claude-plugin/marketplace.json
```

Expected: `OK` 且匹配 news 条目

- [ ] **Step 3: Commit**

```bash
git add .claude-plugin/marketplace.json
git commit -m "feat(news): register news plugin in marketplace"
```

---

### Task 9: 结构验证与 smoke check

**Files:**
- Verify: 全部新增/修改文件

- [ ] **Step 1: 目录结构检查**

```bash
find plugins/news -type f | sort
```

Expected:

```
plugins/news/.claude-plugin/plugin.json
plugins/news/skills/github-trend/SKILL.md
```

- [ ] **Step 2: marketplace 引用路径存在**

```bash
test -d plugins/news && test -f plugins/news/skills/github-trend/SKILL.md && echo "marketplace source OK"
```

Expected: `marketplace source OK`

- [ ] **Step 3: SKILL.md 关键约束抽查**

```bash
rg "禁止并行|agent-browser|analyzed-repos|5000|stdout" plugins/news/skills/github-trend/SKILL.md
```

Expected: 每项至少 1 处匹配

- [ ] **Step 4: 最终 commit（若有遗漏文件）**

```bash
git status
```

Expected: working tree clean（除未提交的 README.md 外）

---

## Spec Coverage Checklist

| Spec 要求 | 对应 Task |
|-----------|-----------|
| news 插件 + github-trend skill | Task 1, 2 |
| 手动触发 | Task 2 调用场景 |
| OSS Insight top 20 + GitHub Trending 默认页 | Task 5 §1.1 |
| MemPalace 历史过滤 topic=analyzed-repos | Task 3, Task 5 §1.2 |
| star ≥ 5000 过滤 | Task 5 §1.3 |
| MemPalace 写入 | Task 5 §1.4 |
| 串行分析子 Agent | Task 6 |
| 三项分析报告格式 | Task 6 |
| stdout 最终报告 | Task 7 |
| debug 默认 true + JSON 日志 + 统计 | Task 3, Task 7 |
| TMP_DIR 中间产物 | Task 4, Task 5, Task 6 |
| agent-browser 优先 | Task 3 |
| 混合语言报告 | Task 6 |
| marketplace 注册 | Task 8 |
| 异常处理 | Task 7 |

---

## Execution Notes

- 本计划**无自动化单元测试**（交付物为 SKILL 指令文档）；Task 9 为结构 smoke check。
- 完整端到端验证需用户本地具备 agent-browser + MemPalace MCP，手动调用 `/news:github-trend`。
- `README.md` 为需求来源，不在本计划范围内修改（除非用户另行要求）。
