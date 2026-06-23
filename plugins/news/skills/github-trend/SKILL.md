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

### 第 2 步：项目分析子 Agent

主 Agent 提取 `collect_result.md` 中 `## 待分析项目` 的 URL 列表。启动**一个**分析子 Agent，传入该列表，串行执行以下分析流程：

1. 使用 `/usr/sbin/agent-browser` 访问 `https://github.com/<owner>/<repo>`。
2. **Star 门禁**：获取 Star 数。
   - 若 Star < 5000，归类到 `## 剔除 star 不足项目`。
   - 若 Star ≥ 5000，从 README 等公开页面提取信息，生成项目 analysis 报告正文。
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
