---
name: github-trend
description: 采集 GitHub Trending 当日热门仓库，输出日报。
---

# github-trend

**采集 GitHub 趋势项目，输出日报**

## 调用场景

**适用**
- 用户明确要求使用本 skill 生成 github 当日趋势项目分析报告

**不适用**
- 用户未明确要求调用本 skill 时

## 配置与全局变量

`debug`: 默认为 `true`。

`TMP_DIR`: 主 Agent 初始化时根据本地真实时间生成 `/tmp/github_trend_<yyyymmdd_hhmmss>/`（如 `20260622_143000`）。

**仅在 `debug=true` 时**创建 `TMP_DIR` 并落盘中间 Markdown 产物；`debug=false` 时不创建目录、不写中间文件。

---

## 困难与统计上报规范

各子 Agent 在执行过程中遇到阻碍、降级、歧义或部分失败时，必须记录并在输出结果的“困难与统计”章节上报，禁止静默吞掉。

### 困难与统计段落格式
子 Agent 在生成的 Markdown 报告末尾追加 `## <采集/分析/写入>困难与统计` 章节，由模型自由发挥编写遇到的困难描述（如超时、解析失败、降级等）以及调用统计信息（如浏览器或 MemPalace 调用次数、耗时等）。

---

## 工具使用规范

### agent-browser 

**agent-browser CLI 进行网页访问，包括导航、快照、数据提取**

- **禁止运行安装命令 `npm i -g agent-browser`**
- **agent-browser CLI 调用命令，必须写全路径 `/usr/sbin/agent-browser`**
- **严格串行操作页面，避免并行同时操作多个页面，防止浏览器使用冲突**
- **CLI 使用例子**
```
    # 清空 agent-browser 的 daemon 的状态，避免历史状态干扰新网页的访问
    agent-browser close
    # 打开一个新的 tab 并访问网页
    agent-browser open https://huggingface.co
    # 等待网页加载完毕
    agent-browser wait --load networkidle
    # 查看当前在操作哪个 tab
    agent-browser tab
    # 查看当前网页的内容快照
    agent-browser snapshot
    # 提确页面的 主要内容区的 文本 。 使用 <main>、<article> 或 <div id="content"> 标签
    agent-browser get text main
    # 关闭网页，确保网页浏览器的状态干净
    agent-browser tab close
```
- **运行如下命令，可加载 CLI 的使用说明**
```bash
agent-browser skills get core             # start here — workflows, common patterns, troubleshooting
agent-browser skills get core --full      # include full command reference and templates
```

### MemPalace MCP 使用

MemPalace 用于**读取**历史记录（去重）与在**全部分析完成后、输出报告前**记录已分析仓库。

**读写时机（强约束）**
- **读取**：仅第 1.2 步历史过滤时调用 `mempalace_search`
- **写入**：仅第 3 步、第 2 步全部分析完成之后、stdout 报告输出**之前**，由主 Agent 对**分析成功**的项目调用 `mempalace_diary_write`
- **禁止**在采集阶段或分析完成前写入 MemPalace（避免 skill 未跑完即标记为已分析，导致下次被误过滤）

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

2. **写入已分析记录**（仅第 3 步，且该项目第 2 步分析成功时）：
   ```
   mempalace_diary_write(
     agent_name="claude",
     wing="github-trending",
     topic="analyzed-repos",
     entry="[YYYY.MM.DD.HH.MM.SS] https://github.com/<owner>/<repo>"
   )
   ```
   时间戳使用本地真实时间，禁止用模型截止时间。**分析失败的项目禁止写入。**

MemPalace 不可用时：第 1 步无法去重则终止；第 3 步无法写入则上报困难，仍继续第 4 步输出报告（报告中说明 MemPalace 写入失败）。

---

## 执行流程

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

### 第 2 步：串行项目分析

启动一个独立的 Agent， 其对 `final_urls` 中的项目**逐个、串行**进行分析

每个分析子 Agent 结束时，主 Agent 须标记该项目 `analysis_status` 为以下三者之一：

- **success**：子 Agent 正常输出分析内容（含「未能从公开页面确认」等部分信息，但未标注「分析失败」）
- **failed**：子 Agent 输出含「分析失败」或中途无法完成分析（Star 已 ≥ 5000 但后续步骤失败）
- **skipped_low_stars**：Star < 5000 或无法可靠解析；子 Agent 返回极简结果，主 Agent 将 URL 追加到 `excluded_urls.star_insufficient`，**不拼接**项目报告块，**不计入** success/failed

每个分析子 Agent prompt 必须包含：目标 URL、`TMP_DIR`、`debug`、报告格式、语言要求（技术名词英文、说明中文）、禁止克隆代码、困难与统计上报规范。

**每个项目的分析流程**

1. /usr/sbin/agent-browser 访问 `https://github.com/<owner>/<repo>`
2. **Star 门禁**：读取 star 数
   - star ≥ 5000 → 继续步骤 3
   - star < 5000 或无法可靠解析 → 返回 `skipped_low_stars`（见下方格式），**禁止**继续 README 深挖；无法解析时记录困难与统计（stage: `2_analyze`）
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

  ## 分析困难与统计
  （按困难与统计上报规范填写；无则写「无」）
  ```

Star 不足或无法解析时（`analysis_status: skipped_low_stars`）：

  ```markdown
  ## 执行结果

  - analysis_status: skipped_low_stars
  - url: https://github.com/<owner>/<repo>
  - stars: 1234（无法解析时写「未知」）

  ## 分析困难与统计

  （无法解析 star 时记录困难与统计；无则写「无」）
  ```

主 Agent 收到 `skipped_low_stars` 后：追加 URL 至 `excluded_urls.star_insufficient`；不拼接正文；继续下一 URL。

分析失败时（`analysis_status: failed`）：

  ```markdown
  ## <owner>/<repo>

  - **仓库地址**: https://github.com/<owner>/<repo>
  - **github star 数量**
  - **分析失败**：说明分析失败的原因（如仓库页面无法访问、工具调用失败等）
  ```

执行原则：
- **禁止**克隆仓库、浏览源码目录、读 commit 历史
- **记录困难与统计** agent-browser 降级、页面异常、重试时，按困难与统计上报规范记录
- **严格优先使用 agent-browser 获取信息**
- **禁止安装 npm i -g agent-browser**
- **禁止使用模型的自身知识编造内容，所有事实必须基于网页获取**

**落盘（仅 debug=true）**
- `TMP_DIR/analyze/<owner>__<repo>.md` — 写入上述 markdown（含「分析困难与统计」块）

主 Agent 收集每个子 Agent 的 markdown 输出及 `analysis_status`，按 `final_urls` 顺序排列，供第 4 步拼接（**跳过** `skipped_low_stars` 项目，不纳入正文）；同时收集各「困难与统计」块供汇总；维护分类 `excluded_urls`（`history_analyzed` 来自 Step 1，`star_insufficient` 来自本步 `skipped_low_stars`）供第 4 步报告使用。`debug=true` 时可在每次追加后更新排除列表 Markdown。

### 第 3 步：写入 MemPalace（分析完成之后、输出报告之前）

由主 Agent 执行（不委派子 Agent）。

对第 2 步中 `analysis_status: success` 的每个 URL 调用 `mempalace_diary_write`（格式见 MemPalace 章节）。**禁止**写入 `failed` 或 `skipped_low_stars` 项目。

- 逐个写入；单条失败时记录困难与统计并继续下一条
- `debug=true` 时在 `TMP_DIR/collect/` 下落盘写入记录的 Markdown 文件。
- 由主 Agent 在最终报告的「困难与统计汇总」章节输出写入摘要（成功 N 条、跳过 M 条失败项目、写入错误 K 条）并记录在「写入困难与统计」中。

若本次无任何 `success` 项目（全失败或无候选），跳过本步。

### 第 4 步：整合报告并输出 

主 Agent 将 `success` 与 `failed` 子 Agent 的项目 markdown **原样拼接**（禁止改写、禁止总结），输出到 **stdout**；`skipped_low_stars` 项目不拼接。`success` 计入「总共分析项目」；`failed` 计入「分析失败项目」；`skipped_low_stars` 不计入上述两项。
最终输出中文报告，格式使用如下 markdown 格式

  ```markdown
  # GitHub Trending 日报

  生成时间: YYYY.MM.DD（本地时区）
  总共分析项目：xx 个
  分析失败项目：yy 个

  ## https://github.com/<owner>/<repo>

  该项目的分析报告

  ## 剔除已分析项目

  列出 `excluded_urls.history_analyzed` 中的 URL（MemPalace 历史命中）。**仅 URL 列表**，禁止附加说明。无则写：无

  - https://github.com/<owner>/<repo>

  ## 剔除 star 不足项目

  列出 `excluded_urls.star_insufficient` 中的 URL（Star < 5000 或无法解析）。**仅 URL 列表**，禁止附加说明。无则写：无

  - https://github.com/<owner>/<repo>

  ## 困难与统计汇总

  主 Agent 原样汇总采集、分析、写入各阶段子 Agent 上报的 `## <采集/分析/写入>困难与统计` 章节内容。
  无困难与统计时写：本次执行未上报困难与统计。

  （若第 3 步有 MemPalace 写入，在此节末尾追加写入摘要：成功 N 条、跳过 M 条、错误 K 条）

  在 `debug=true` 时在报告末尾追加：
  - 中间产物路径: <TMP_DIR>

  ```

## 异常处理

| 场景 | 处理 |
|------|------|
| agent-browser 不可用 | 终止，提示安装命令 |
| MemPalace 不可用（第 1 步） | 终止（无法历史去重） |
| MemPalace 不可用（第 3 步） | 记录困难并跳过写入，继续第 4 步输出报告 |
| 单源采集失败 | 继续另一源 |
| 两源均失败 | 终止 |
| 历史过滤后名单为空（`after_history_count == 0`） | 第 4 步输出「今日无新项目」，正常结束；跳过第 3 步；仍输出分类剔除节 |
| 单项目分析失败 | 记录错误，继续下一个；**不写入 MemPalace** |
| 第 3 步单条 MemPalace 写入失败 | 记录困难，继续下一条 |
| TMP_DIR 创建失败 | 降级 `./tmp/...` |

---

## 执行原则

- 优先获取本地真实时间
- 网页操作 agent-browser 优先
- 分析子 Agent 必须串行
- 最终报告仅 stdout，中间产物仅 debug 模式落盘
- 事实描述基于页面可见信息，不足时明确标注，禁止编造
- 遇到困难与统计必须记录上报，禁止静默降级或静默跳过
- MemPalace 写入在第 3 步（分析完成之后、报告输出之前），且仅写入分析成功的项目
- **禁止安装 npm i -g agent-browser**
- **agent-browser CLI 调用命令，必须写全路径 `/usr/sbin/agent-browser`**
- Star 过滤在 Step 2 分析门禁执行，采集阶段禁止批量访问仓库页读 Star
- **禁止使用模型的自身知识编造内容，所有事实必须基于网页获取**
