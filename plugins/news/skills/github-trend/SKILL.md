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

`TMP_DIR`: 主 Agent 初始化时根据本地真实时间生成 `/tmp/github_trend_<yyyymmdd_hhmmss>/`（如 `20260622_143000`）， 该目录禁止在当前目录下生成，必须在 `/tmp/` 目录路径下生成

`HISTORY_FILE`: 历史记录文件路径。默认为**当前工作目录**下的 `./history.txt`（相对路径，禁止凭 skill 名称 `github-trend` 推断目录名）。用户如在提示词中指定历史文件路径（如「历史文件用 `./my-history.txt`」「history 文件 `/path/to/history.txt`」），则使用用户指定路径。

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

### history 文件使用

`HISTORY_FILE` 用于**读取**历史记录（去重）、**追加**已分析仓库 URL。

**读写时机（强约束）**
- **读取**：仅第 1.2 步历史过滤时，对每个 URL 执行 `grep -Fixq -- "$url" "$HISTORY_FILE"`
- **写入**：仅第 3 步、第 2 步全部分析完成之后、保存最终报告与 stdout 输出**之前**，由主 Agent 对**分析成功**的项目执行 `echo "$url" >> "$HISTORY_FILE"`
- **禁止**在采集阶段或分析完成前写入 history 文件（避免 skill 未跑完即标记为已分析，导致下次被误过滤）

**文件编辑约束（强约束）**
- **仅允许追加**：对 `HISTORY_FILE` 的唯一合法写操作是 `echo "$url" >> "$HISTORY_FILE"`，在文件末尾追加新行
- **禁止任何其他形式的编辑**，包括但不限于：
  - 删除、清空、截断文件内容
  - 覆盖写入（`>`、`tee` 无追加模式等）
  - 原地修改（`sed -i`、`awk -i`、编辑器保存等）
  - 重排、去重、合并 history 文件中已有行
- **禁止**在本 skill 流程内创建空文件替代已有 history（Step 0 仅校验文件存在，不创建、不重建）
- 读取仅允许 `grep` 等只读命令，**禁止**读取后写回同一文件

**grep 参数说明**
- `-F`：固定字符串匹配，URL 中的 `.` `/` `-` 等按字面量处理，**不会**被当成正则
- `-i`：大小写不敏感。GitHub 的 owner/repo 路径访问时不区分大小写（如 `CoplayDev` 与 `coplaydev` 为同一仓库），去重查询必须加 `-i`，否则易漏判
- `-x`：整行精确匹配，避免 `unity-mcp` 误命中其他含相同子串的行
- `--`：防止 URL 以 `-` 开头时被 grep 误解析为选项

**文件格式**
- 每行一个 URL：`https://github.com/<owner>/<repo>`，写入时保留页面/报告中的原始大小写
- 禁止空行、注释或其他格式
- 查询时用 `grep -Fixq`（大小写不敏感整行匹配）；写入时用 `echo >>` 追加原始 URL 字符串，禁止自行转换大小写

**常见操作**

1. **查询是否已分析**（去重用，Step 1.2）：
   ```bash
   grep -Fixq -- "https://github.com/CoplayDev/unity-mcp" "$HISTORY_FILE"
   ```
   若 history 中已有 `https://github.com/coplaydev/unity-mcp`，仍应命中（退出码 `0`）。
   - 退出码 `0`：命中，归入「剔除已分析项目」
   - 退出码 `1`：未命中，归入「待分析项目」
   - 其他退出码：grep 异常，记入采集困难与统计，该 URL 暂归入待分析
   - **`-q` 静默无输出属正常**：必须检查 `$?` 判断命中与否，**禁止**因终端无输出而判定未命中

2. **追加已分析记录**（仅 Step 3，且该项目 Step 2 分析成功时；**仅允许追加，禁止其他任何写操作**）：
   ```bash
   echo "https://github.com/owner/repo" >> "$HISTORY_FILE"
   ```
   **分析失败的项目禁止写入。Star 不足的项目禁止写入。**


---

## 执行流程

### 第 0 步：准备与初始化

1. **获取当前真实时间**：本地时区当前时间。
2. **确定 CWD 与 `HISTORY_FILE`（强约束）**：
   - 执行 `pwd`，将输出原样记为 `CWD`（**必须读取命令输出**，禁止凭记忆或 skill 名称拼路径）
   - **禁止**根据 skill 名 `github-trend` 推断工作目录（实际目录可能是 `github-trending` 等任意名称）
   - 默认 `HISTORY_FILE=./history.txt`（相对 CWD）；用户提示词指定路径时使用用户路径
   - 校验：`test -f "$HISTORY_FILE"` 或 `grep -c . "$HISTORY_FILE"`；失败则终止流程，**禁止创建该文件**
3. **检查工具**：确认 `agent-browser-cdp`存在于指定的路径；如果不存在，直接跳到第 4 步，输出失败原因解释报告，并终止整个流程
4. **创建目录**：
   - 主 Agent 创建 `TMP_DIR` 目录及 `TMP_DIR/success/`、`TMP_DIR/failed/`、`TMP_DIR/skipped/` 子目录。

### 第 1 步：采集项目

#### 1.1 趋势榜采集
- 使用 `/usr/sbin/agent-browser-cdp` 访问 `https://github.com/trending`。
- 提取 `https://github.com/<owner>/<repo>` 格式 URL，按页面原始字符串去重。

#### 1.2 history 历史过滤

对每个采集 URL（已去重）串行执行 `grep -Fixq -- "$url" "$HISTORY_FILE"`，**以退出码 `$?` 判断**（`-q` 无终端输出）。
- 命中（退出码 0）的 URL 记入 `剔除已分析项目`；
- 未命中（退出码 1）的记入 `待分析项目`；
- grep 异常（其他退出码）记入 `采集困难与统计`，该 URL 暂归入待分析。

最终，把如上结论写入 `TMP_DIR/collect_result.md`，格式如下

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

主 Agent 提取 `collect_result.md` 中 `## 待分析项目` 的 URL 列表。 对每个成员项目，顺序完成如下分析步骤：

1. 使用 `/usr/sbin/agent-browser-cdp` 访问 `https://github.com/<owner>/<repo>`。

2. 获取项目页面中的 Star 数，进行如下区别实施：

   2.1 若 Star < 5000
    生成符合下方模板的项目分析报告正文，写入 `TMP_DIR/skipped/<owner>__<repo>.md`

    ```markdown
    ### owner/repo
    **仓库地址**: https://github.com/owner1/repo1
    **github star 数量**: xxx
    **star 不足，不予分析**
    ```

   2.2 若 Star ≥ 5000
    从该项目的 README 等公开页面提取信息，生成符合下方模板的项目分析报告正文，写入 `TMP_DIR/success/<owner>__<repo>.md`。

    ```markdown
    ### owner/repo
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

    ## 分析困难与统计
    在本步骤执行过程中，反应出遇到了什么执行困难和不合理的地方
    ```

   2.3 若页面访问、Star 获取或 README 解析失败
    将失败原因写入 `TMP_DIR/failed/<owner>__<repo>.md`，归类为分析失败项目。

    ```markdown
    ### owner/repo
    **仓库地址**: https://github.com/owner1/repo1
    **分析失败**: 失败原因
    ```


### 第 3 步：写入 history

第 2 步全部分析完成后，由主 Agent 执行：

1. 从 `TMP_DIR/success/<owner>__<repo>.md` 中提取分析成功项目的原始 URL。
2. 对每个成功项目的 URL 串行执行 `echo "$url" >> "$HISTORY_FILE"`。
3. 若写入失败，在第 4 步报告的“执行困难与统计”中记录失败原因，但不终止流程。

Star 不足或分析失败的项目禁止写入 history。禁止对 `HISTORY_FILE` 执行除追加以外的任何写操作。

### 第 4 步：整合报告并输出

主 Agent 分别收集 `TMP_DIR/success/`、`TMP_DIR/failed/`、`TMP_DIR/skipped/` 下的报告并合

**如没有明确要求，最终报告内容必须输出在你的回复文本中**

报告格式如下：

    ```markdown
    # GitHub Trending 日报

    生成时间: YYYY.MM.DD（本地时区）
    总共分析项目：xx 个
    分析失败项目：yy 个

    ## owner1/repo1
    来自 `TMP_DIR/success/<owner>__<repo>.md` 中成功分析的项目的完整报告内容

    ## owner2/repo2
    来自 `TMP_DIR/success/<owner>__<repo>.md` 中成功分析的项目的完整报告内容

    ## 所有分析失败项目
    来自 `TMP_DIR/failed/<owner>__<repo>.md` 中分析失败项目，输出如下列表：
    - owner/repo，分析失败原因

    ## 所有 star 不足项目
    来自 `TMP_DIR/skipped/<owner>__<repo>.md` 中因 star 不足跳过的项目，输出如下列表：
    - owner/repo， star 数量 xx 不足，忽略分析
    - owner/repo， star 数量 xx 不足，忽略分析

    ## 所有跳过的已分析项目
    来自 `TMP_DIR/collect_result.md` 中 `## 剔除已分析项目`，输出如下列表：
    - owner/repo， ，已经被分析过，忽略分析
    - owner/repo， ，已经被分析过，忽略分析

    ## 执行困难与统计
    如遇 history 文件操作失败、CLI 操作失败等事件

    ```

## 执行原则

- 主 Agent 串行完成采集、过滤、分析、history 写入和报告整合
- 成功、失败、跳过项目分别存放在 `TMP_DIR/success/`、`TMP_DIR/failed/`、`TMP_DIR/skipped/` 下
- 事实描述基于页面可见信息，不足时明确标注，禁止编造
- 遇到困难必须在“困难与统计”中上报
- **agent-browser-cdp CLI 调用命令，必须写全路径， 它只存在于`/usr/sbin/agent-browser-cdp` 或 `/usr/local/bin/agent-browser-cdp`**
- **禁止使用 agent-browser  CLI  来完成任务，必须使用 agent-browser-cdp CLI 来完成任务**
- 历史去重与记录**仅通过 `HISTORY_FILE` 完成**，禁止使用 MCP 或其他外部存储替代
- **`HISTORY_FILE` 仅允许末尾追加（`echo >>`），禁止删除、清空、覆盖、原地修改 history 文件中已有内容**
- `grep -Fixq` 用于只读去重查询（固定字符串 + 整行 + 大小写不敏感）；`echo >>` 用于追加写入；禁止用其他任何方式修改 history 文件
- URL 写入保留原始大小写；去重查询时以 `-i` 大小写不敏感匹配，与 GitHub URL 行为一致
- **路径禁止臆造**：`CWD`、`HISTORY_FILE` 必须来自 `pwd` 输出或用户指定；禁止用 skill 名 `github-trend` 拼目录名
- **所有 shell 路径命令**：优先使用 `./history.txt`、`"$HISTORY_FILE"` 等变量，禁止硬编码类似 `.../github-trend/...` 的猜测路径
- **`HISTORY_FILE` 不存在时禁止创建**，终止流程并宣告任务失败
- **如没有明确要求，最终报告内容必须输出在你的回复文本中**
