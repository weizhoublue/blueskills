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

`debug`: 默认为 `true`。用户如在运行指令中明确要求（如包含「关闭 debug」「debug=false」「关闭调试」等类似表述）时，将 `debug` 置为 `false`；用户说「开启 debug」「debug=true」时置为 `true`；否则保持默认值。

`TMP_DIR`: 主 Agent 初始化时根据本地真实时间生成 `/tmp/github_trend_<yyyymmdd_hhmmss>/`（如 `20260622_143000`）。

**`TMP_DIR` 仅用于 `debug=true` 时保存中间产物**（`collect_result.md`、`analyze_result.md`、`mempalace_result.md` 及各项目详情文件。

---

## 工具使用规范

### agent-browser-cdp

**agent-browser-cdp CLI 进行网页访问，包括导航、快照、数据提取**

- **调用 agent-browser-cdp CLI 必须写全路径， 确认 agent-browser-cdp CLI 命令路径，它存在于 `/usr/sbin/agent-browser-cdp` 或 `/usr/local/bin/agent-browser-cdp`, 禁止该 CLI 是其他路径**
- **严格串行操作页面，避免并行同时操作多个页面，防止浏览器使用冲突**
- **串行操作时需注意, 每次关闭标签页清理状态，避免浏览器状态残留影响后续页面加载**
- **CLI 使用例子**
```
    # 清空 agent-browser-cdp 的 daemon 的状态，避免历史状态干扰新网页的访问
    /usr/sbin/agent-browser-cdp close
    # 打开一个新的 tab 并访问网页
    /usr/sbin/agent-browser-cdp open https://huggingface.co
    # 等待网页加载完毕
    /usr/sbin/agent-browser-cdp wait --load networkidle
    # 查看当前在操作哪个 tab
    /usr/sbin/agent-browser-cdp tab
    # 查看当前网页的内容快照
    /usr/sbin/agent-browser-cdp snapshot
    # 提取页面的 主要内容区的 文本 。 使用 <main>、<article> 或 <div id="content"> 标签
    /usr/sbin/agent-browser-cdp get text main
    # 关闭网页，确保网页浏览器的状态干净
    /usr/sbin/agent-browser-cdp tab close
```
- **关于 agent-browser-cdp CLI 的使用用法，他和 agent-browser CLI 的用法是一致的，可以参考  agent-browser CLI 的用法说明**
```bash
agent-browser skills get core             # start here — workflows, common patterns, troubleshooting
agent-browser skills get core --full      # include full command reference and templates
```
- **在后续整个任务执行过程中，禁止使用 agent-browser CLI，必须使用 agent-browser-cdp CLI 来完成**

### MemPalace MCP 使用

MemPalace 用于**读取**历史记录（去重）、记录已分析仓库。

**读写时机（强约束）**
- **读取**：仅第 1.2 步历史过滤时调用 `mempalace_search`
- **写入**：仅第 3 步、第 2 步全部分析完成之后、保存最终报告与 stdout 输出路径提示**之前**，由主 Agent 对**分析成功**的项目调用 `mempalace_diary_write`
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


---

## 执行流程

### 第 0 步：准备与初始化

1. **获取当前真实时间**：本地时区当前时间。
2. **检查工具**：确认 `agent-browser-cdp`存在于指定的路径，如果不存在，直接跳到第 4 步，输出一份失败的原因解释报告，并终止整个流程
3. **确认 MemPalace MCP 可用，刚启动时，该 mcp 需要启动时间，可尝试等待最多 1 min。如果不可用，直接跳到第 4 步，输出一份失败原因解释报告，并终止整个流程**
4. **创建目录**：
   - 无论 `debug` 是 `true` 还是 `false`，若用户未在提示词中指定保存路径，主 Agent 均需创建 `TMP_DIR` 目录。
   - 若 `debug=true`，主 Agent 必须创建 `TMP_DIR` 目录及 `TMP_DIR/analyze/` 子目录。

### 第 1 步：采集子 Agent

主 Agent 启动**一个**采集子 Agent，完成以下流程。

#### 1.1 趋势榜采集
- 使用 `/usr/sbin/agent-browser-cdp` 访问 `https://github.com/trending`。
- 提取 `https://github.com/<owner>/<repo>` 格式 URL，统一小写去重。

#### 1.2 MemPalace 历史过滤
调用 `mempalace_search` 对 URL 进行历史去重，并把已被分析过（去重命中）的 URL 记录在 `collect_result.md` 的 `## 剔除已分析项目` 中，未命中的记录在 `## 待分析项目` 中。

**必须严格完成本步骤，不允许跳过。如果 MemPalace MCP不可用，直接跳到第 4 步，输出一份失败原因解释报告，并终止整个流程**

#### 1.3 输出最终候选者列表
子 Agent 格式化并返回 `collect_result.md` 的文本内容（若 `debug=true`，主 Agent 将该文本写入 `TMP_DIR/collect_result.md`）：

    ```markdown
    ## 待分析项目
    - https://github.com/owner1/repo1
    - https://github.com/owner2/repo2

    ## 剔除已分析项目
    - https://github.com/owner3/repo3

    ## 采集困难与统计
    在本步骤执行过程中，反应出遇到了什么执行困难和不合理的地方
    ```


### 第 2 步：项目分析

主 Agent 提取 `collect_result.md` 中 `## 待分析项目` 的 URL 列表。启动**一个**分析子 Agent，在 Prompt 中传入该列表、以及 `debug` 状态与 `TMP_DIR` 路径，由该子 Agent 串行执行以下分析流程：

1. 使用 `/usr/sbin/agent-browser-cdp` 访问 `https://github.com/<owner>/<repo>`。
2. **Star 门禁**：获取 Star 数。
   - 若 Star < 5000，归类到 `## 剔除 star 不足项目`。
   - 若 Star ≥ 5000，从 README 等公开页面提取信息，生成符合下方模板的项目分析报告正文。
   - 若处理异常或解析失败，归类到 `## 分析失败项目`。
3. **单项目报告落盘**（仅 `debug=true`）：将分析成功的项目报告内容单独写入 `TMP_DIR/analyze/<owner>__<repo>.md`。

分析子 Agent 运行结束后返回 `analyze_result.md` 文本内容（若 `debug=true`，主 Agent 将该文本写入 `TMP_DIR/analyze_result.md`）：

    ```markdown
    ## 分析报告

    ### owner1/repo1
    **仓库地址**: https://github.com/owner1/repo1
    **github star 数量**: 12000

    **软件类别**
    用一句话说明软件的类别：如 ai agent 、 rag、知识库、搜索引擎、工具库、插件、框架等

    **适用场景**
    （详细描述，> 100 字, < 200 字）

    **要解决的问题**
    （详细描述，> 100 字, < 200 字）

    **功能**
    （各个功能说明，每项 > 50 字， 每项 < 100 字 ）

    ## 分析失败项目
    - https://github.com/owner2/repo2 ， 分析失败的原因

    ## 剔除 star 不足项目
    - https://github.com/owner3/repo3 ， star 只有 xx 个，不满足 xxx 数量要求

    ## 分析困难与统计
    在本步骤执行过程中，反应出遇到了什么执行困难和不合理的地方
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

**必须严格完成本步骤，不允许跳过。如果 MemPalace MCP不可用，则在第 4 步报告中体现出 MemPalace 写入失败**

### 第 4 步：整合报告并输出

主 Agent 将收集到的 Markdown 报告合并, 如没有明确要求，则直接打印到 stdout 即可

报告格式如下：

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
    （来自 collect_result.md 的已分析项目，无则写 - 无）

    ## 剔除 star 不足项目
    （来自 analyze_result.md 的 star 不足项目，无则写 - 无）

    ## 执行困难与调试统计
    如遇 MemPalace 操作失败、CLI 操作失败等事件
    按顺序拼接 collect_result.md、analyze_result.md、mempalace_result.md 中的困难与统计内容
    
    ```

## 执行原则

- 网页操作优先使用 `agent-browser-cdp`
- 采集和分析子 Agent 各仅启动一个，串行处理
- 数据同步与传递完全基于 Markdown 协议
- 事实描述基于页面可见信息，不足时明确标注，禁止编造
- 遇到困难必须在“困难与统计”中上报
- **agent-browser-cdp CLI 调用命令，必须写全路径， 它只存在于`/usr/sbin/agent-browser-cdp` 或 `/usr/local/bin/agent-browser-cdp`**
- **禁止使用 agent-browser  CLI  来完成任务，必须使用 agent-browser-cdp CLI 来完成任务**
