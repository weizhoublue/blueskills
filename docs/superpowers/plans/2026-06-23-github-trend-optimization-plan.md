# GitHub Trend 技能优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 优化 github-trend 技能说明文档，实现基于 Markdown 流转的协议并简化为单子 Agent 串行分析流程。

**Architecture:** 修改 `SKILL.md`，将主 Agent 与子 Agent 之间的通信和临时文件从 JSON 重构为 Markdown 协议。在 Step 2 采用单分析子 Agent 进行串行分析。

**Tech Stack:** Markdown

## 全局约束
- 必须使用 `/usr/sbin/agent-browser` 路径调用浏览器，禁止安装。
- 禁止修改 Git 配置中的 user.name 或 user.email。
- 提交代码时必须使用带有 `-s` 和 `-S` 的 `git commit`。

---

### Task 1: 重构配置、困难与工具规范

**Files:**
- Modify: `plugins/news/skills/github-trend/SKILL.md:18-195`

**Interfaces:**
- Consumes: None
- Produces: 简化的配置与自由格式困难规范

- [ ] **Step 1: 修改 SKILL.md 中的配置、困难与工具规范**
  修改 `SKILL.md` 中有关 JSON 文件落盘、Debug 格式的规范，改用 Markdown 流转描述。将困难和统计修改为自由格式。

  ```markdown
  ## 配置与全局变量
  
  `debug`: 默认为 `true`。
  
  `TMP_DIR`: 主 Agent 初始化时根据本地真实时间生成 `/tmp/github_trend_<yyyymmdd_hhmmss>/`（如 `20260622_143000`）。
  
  **仅在 `debug=true` 时**创建 `TMP_DIR` 并落盘中间 Markdown 产物；`debug=false` 时不创建目录、不写中间文件。
  
  ---
  
  ## 困难与统计上报规范
  
  各子 Agent 在执行过程中遇到阻碍、降级、歧义或部分失败时，必须记录并在输出结果的“困难与统计”章节上报，禁止静默吞掉。
  
  ### 困难与统计段落格式
  子 Agent 在生成的 Markdown 报告末尾追加 `## <采集/分析/写入>困难与统计` 章节，由模型自由发挥编写遇到的困难描述（如超时、解析失败、降级等）以及调用统计信息（如浏览器或 MemPalace 调用次数、耗时等）。
  ```

- [ ] **Step 2: 验证文件内容**
  确认修改后对应的 JSON 说明已被彻底移除。

- [ ] **Step 3: 提交代码**
  运行：
  ```bash
  git add plugins/news/skills/github-trend/SKILL.md
  git commit -s -S -m "docs(github-trend): simplify config and difficulties specs in SKILL.md"
  ```

---

### Task 2: 重构 Step 0 与 Step 1（采集阶段）

**Files:**
- Modify: `plugins/news/skills/github-trend/SKILL.md:197-283`

**Interfaces:**
- Consumes: Task 1 中的基础配置规范
- Produces: 采集子 Agent 输出 `collect_result.md` 协议规范

- [ ] **Step 1: 重构 Step 0 准备与 Step 1 采集的文档段落**
  修改 `SKILL.md` 中的“执行流程”之“第 0 步”与“第 1 步”，明确主 Agent 启动单个采集子 Agent，并规定返回的 `collect_result.md` Markdown 格式。

  ```markdown
  ### 第 0 步：准备与初始化
  
  1. **获取当前真实时间**：本地时区当前时间。
  2. **检查工具**：确认 `/usr/sbin/agent-browser` 与 MemPalace MCP 可用。
  3. **创建目录**（仅 `debug=true`）：创建 `TMP_DIR` 目录及 `TMP_DIR/analyze/` 子目录。
  
  ### 第 1 步：采集子 Agent
  
  主 Agent 启动**一个**采集子 Agent，完成以下流程。
  
  #### 1.1 趋势榜采集
  - 使用 `/usr/sbin/agent-browser` 访问 `https://github.com/trending`。
  - 提取 `https://github.com/<owner>/<repo>` 格式 URL，统一小写去重。
  
  #### 1.2 MemPalace 历史过滤
  - 调用 `mempalace_search` 对 URL 进行历史去重，命中的项目放入已分析列表。
  
  #### 1.3 输出最终候选者列表
  子 Agent 格式化并返回 `collect_result.md` 的文本内容（若 `debug=true`，主 Agent 将该文本写入 `TMP_DIR/collect_result.md`）：
  
  ```markdown
  ## 待分析项目
  - https://github.com/owner1/repo1
  - https://github.com/owner2/repo2
  
  ## 剔除已分析项目
  - https://github.com/owner3/repo3
  
  ## 采集困难与统计
  （由采集子 Agent 自由发挥编写）
  ```
  ```

- [ ] **Step 2: 验证文件内容**
  确认新写入的 Step 0 和 Step 1 说明符合设计规范。

- [ ] **Step 3: 提交代码**
  运行：
  ```bash
  git add plugins/news/skills/github-trend/SKILL.md
  git commit -s -S -m "docs(github-trend): rewrite Step 0 and Step 1 to use markdown protocol"
  ```

---

### Task 3: 重构 Step 2（分析阶段）与 Step 3（存储阶段）

**Files:**
- Modify: `plugins/news/skills/github-trend/SKILL.md:284-377`

**Interfaces:**
- Consumes: Task 2 中的 `collect_result.md` 待分析项目列表
- Produces: 单子 Agent 串行分析及 `analyze_result.md` 协议规范

- [ ] **Step 1: 重构 Step 2 分析与 Step 3 存储的文档段落**
  修改 `SKILL.md`，规定只启动**一个**分析子 Agent，串行对所有项目进行分析、门禁拦截与单项目 `.md` 报告落盘，并规定 `analyze_result.md` 的 Markdown 格式。

  ```markdown
  ### 第 2 步：项目分析子 Agent
  
  主 Agent 提取 `collect_result.md` 中 `## 待分析项目` 的 URL 列表。启动**一个**分析子 Agent，传入该列表，串行执行以下分析流程：
  
  1. 使用 `/usr/sbin/agent-browser` 访问 `https://github.com/<owner>/<repo>`。
  2. **Star 门禁**：获取 Star 数。
     - 若 Star < 5000，归类到 `## 剔除 star 不足项目`。
     - 若 Star ≥ 5000，从 README 等公开页面提取信息，生成项目分析报告正文。
     - 若处理异常或解析失败，归类到 `## 分析失败项目`。
  3. **单项目报告落盘**（仅 `debug=true`）：将分析成功的项目报告内容单独写入 `TMP_DIR/analyze/<owner>__<repo>.md`。
  
  分析子 Agent 运行结束后返回 `analyze_result.md` 文本内容（若 `debug=true`，主 Agent 将该文本写入 `TMP_DIR/analyze_result.md`）：
  
  ```markdown
  ## 分析报告
  
  ### owner1/repo1
  **仓库地址**: https://github.com/owner1/repo1
  **github star 数量**: 12000
  
  #### 适用场景
  （详细描述，> 100 字）
  
  #### 要解决的问题
  （详细描述，> 100 字）
  
  #### 功能
  （各个功能说明，每项 > 50 字）
  
  ## 分析失败项目
  
  ### owner2/repo2
  - **仓库地址**: https://github.com/owner2/repo2
  - **分析失败**: 页面加载超时
  
  ## 剔除 star 不足项目
  - https://github.com/owner3/repo3
  
  ## 分析困难与统计
  （由分析子 Agent 自由发挥编写）
  ```
  
  ### 第 3 步：写入 MemPalace
  
  由主 Agent 执行（不委派子 Agent）。
  1. 主 Agent 提取 `analyze_result.md` 中 `## 分析报告` 下的成功项目列表。
  2. 串行调用 `mempalace_diary_write` 写入已分析记录。
  3. 生成并返回 `mempalace_result.md` 文本。若 `debug=true`，落盘至 `TMP_DIR/mempalace_result.md`。
  
  ```markdown
  ## 写入摘要
  成功写入 MemPalace 的项目：
  - https://github.com/owner1/repo1
  
  ## 写入困难与统计
  （由主 Agent 自由发挥编写）
  ```
  ```

- [ ] **Step 2: 验证文件内容**
  确认分析阶段及 MemPalace 写入说明正确写入。

- [ ] **Step 3: 提交代码**
  运行：
  ```bash
  git add plugins/news/skills/github-trend/SKILL.md
  git commit -s -S -m "docs(github-trend): rewrite Step 2 and Step 3 to use markdown protocol"
  ```

---

### Task 4: 重构 Step 4（整合输出）与异常处理/执行原则

**Files:**
- Modify: `plugins/news/skills/github-trend/SKILL.md:378-457`

**Interfaces:**
- Consumes: Task 2 和 Task 3 的所有 Markdown 文本
- Produces: 最终的 `SKILL.md` 完整文档

- [ ] **Step 1: 重构 Step 4 报告与异常/原则章节**
  修改 `SKILL.md`，规定最终报告的拼接规则（剔除已分析项目、剔除 star 不足项目、困难与统计自由段落拼接），并更新异常处理表格与执行原则。

  ```markdown
  ### 第 4 步：整合报告并输出
  
  主 Agent 将收集到的 Markdown 报告合并，输出到 stdout。格式如下：
  
  ```markdown
  # GitHub Trending 日报
  
  生成时间: YYYY.MM.DD（本地时区）
  总共分析项目：xx 个
  分析失败项目：yy 个
  
  ## 分析报告
  （直接包含从 analyze_result.md 提取的分析成功的项目段落）
  
  ## 分析失败项目
  （直接包含从 analyze_result.md 提取的分析失败项目段落，无则写无）
  
  ## 剔除已分析项目
  （来自 collect_result.md 的已分析项目，无则写无）
  
  ## 剔除 star 不足项目
  （来自 analyze_result.md 的 star 不足项目，无则写无）
  
  ## 执行困难与调试统计
  （按顺序拼接 collect_result.md、analyze_result.md、mempalace_result.md 中的困难与统计内容）
  ```
  
  ## 异常处理
  
  | 场景 | 处理 |
  |------|------|
  | agent-browser 不可用 | 终止，提示安装 |
  | MemPalace 不可用（第 1 步） | 终止（无法历史去重） |
  | MemPalace 不可用（第 3 步） | 记录困难，跳过写入，继续 Step 4 输出报告 |
  | 待分析项目列表为空 | 直接在 Step 4 输出今日无新项目报告，跳过 Step 2/3 |
  | 分析子 Agent 异常中断 | 拼接已完成部分的报告，未完成的项目记录为分析失败 |
  
  ## 执行原则
  
  - 网页操作优先使用 `/usr/sbin/agent-browser`
  - 采集和分析子 Agent 各仅启动一个，串行处理
  - 数据同步与传递完全基于 Markdown 协议
  - 事实描述基于页面可见信息，不足时明确标注，禁止编造
  - 遇到困难必须在“困难与统计”中上报
  - **禁止安装 npm i -g agent-browser**
  - **agent-browser CLI 调用命令，必须写全路径 `/usr/sbin/agent-browser`**
  ```

- [ ] **Step 2: 验证文件内容**
  确认 `SKILL.md` 剩余章节修改正确。

- [ ] **Step 3: 提交代码**
  运行：
  ```bash
  git add plugins/news/skills/github-trend/SKILL.md
  git commit -s -S -m "docs(github-trend): rewrite Step 4, exception handling, and principles"
  ```

---

### Task 5: 最终校验与格式化

**Files:**
- Modify: `plugins/news/skills/github-trend/SKILL.md`

**Interfaces:**
- Consumes: None
- Produces: 完整且合规的 `SKILL.md` 技能文档

- [ ] **Step 1: 对 SKILL.md 进行最终拼写和段落完整性自检**
  检查是否有任何遗漏的 JSON 遗留内容，保证无 “TBD”、“TODO” 或不一致的描述。

- [ ] **Step 2: 提交代码**
  运行：
  ```bash
  git add plugins/news/skills/github-trend/SKILL.md
  git commit -s -S -m "docs(github-trend): complete github-trend skill optimization"
  ```
