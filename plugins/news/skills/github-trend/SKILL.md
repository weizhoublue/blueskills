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

**启用条件**：用户如在运行指令中明确要求（如包含「关闭 debug」「debug=false」「关闭调试」等类似表述）时，将 `debug` 置为 `false`；用户说「开启 debug」「debug=true」时置为 `true`；否则保持默认值。

`TMP_DIR`: 主 Agent 初始化时根据本地真实时间生成 `/tmp/github_trend_<yyyymmdd_hhmmss>/`（如 `20260622_143000`）

**仅在 `debug=true` 时**创建 `TMP_DIR` 并落盘中间产物；`debug=false` 时不创建目录、不写中间文件。

主 Agent 必须将 `TMP_DIR`、`debug`、困难上报规范告知所有子 Agent。

---

## 困难上报规范

各子 Agent 在执行过程中遇到阻碍、降级、歧义或部分失败时，**必须**记录并上报，禁止静默吞掉。

### 应上报的情形（举例）

- 页面加载失败、超时、需登录、反爬拦截
- agent-browser 失败后降级到其他工具
- URL / star 数 / README 内容无法可靠解析
- MemPalace 搜索结果不确定（疑似误命中或漏命中）
- 公开信息不足导致分析只能部分完成
- 任意步骤重试后才成功

### 单条困难记录格式

每条困难包含：

| 字段 | 说明 |
|------|------|
| `severity` | `info`（提示）\| `warning`（受阻但已绕过）\| `error`（导致该步骤/项目失败） |
| `stage` | 如 `1.1_trending` `1.2_history` `2_analyze` `3_mempalace_write` `4_report` |
| `url` | 相关仓库 URL；与具体仓库无关时留空 |
| `message` | 遇到了什么困难（一句话，中文） |
| `action_taken` | 采取了什么措施（如「降级 Tavily」「跳过该项目」「重试 2 次后成功」） |

### 子 Agent 输出中的困难块

每个子 Agent 返回主 Agent 时，除正常结果外，**必须**附带：

```markdown
## 执行困难

（无困难时写：无）

- [warning] 1.1_trending | https://github.com/owner/repo | OSS Insight 首屏未渲染完成，等待 5s 后重试成功
- [warning] 2_analyze | https://github.com/owner/repo | star 数无法可靠解析，跳过详细分析
```

### 落盘（`debug=true` 时）

- 采集子 Agent：`TMP_DIR/difficulties/collect.json` → `{"difficulties": [...]}`
- 分析子 Agent：`TMP_DIR/difficulties/analyze_<owner>__<repo>.json` → 同上
- 同时追加到对应 `TMP_DIR/debug/*.json` 的 `difficulties` 数组（与 `logs` 并列）

debug JSON 扩展字段：

```json
{
  "logs": [],
  "difficulties": [
    {
      "timestamp": "YYYY-MM-DDTHH:mm:ssZ",
      "severity": "warning",
      "stage": "1.1_trending",
      "url": "",
      "message": "...",
      "action_taken": "..."
    }
  ],
  "stats": { }
}
```

主 Agent 汇总所有子 Agent 的困难块，写入最终 stdout 报告的 **「执行困难汇总」** 节（见第 4 步）。
**无论 `debug` 是否开启，该节都必须输出**（无困难时写「本次执行未上报困难」）。

---

## 工具使用规范

### agent-browser 

**agent-browser CLI 进行网页访问，包括导航、快照、数据提取**

- **在未尝试 agent-browser 的情况下，禁止直接使用其他搜索/抓取工具**
- **禁止运行安装命令 npm i -g agent-browser**
- **agent-browser CLI 调用命令，必须写全路径 `/usr/sbin/agent-browser`**
- **Before running any agent-browser command, load the actual workflow content from the CLI**
```bash
agent-browser skills get core             # start here — workflows, common patterns, troubleshooting
agent-browser skills get core --full      # include full command reference and templates
agent-browser skills list                 # Load a specialized skill when the task falls outside browser web pages
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

MemPalace 不可用时：第 1 步无法去重则终止；第 3 步无法写入则上报 `[error]` 困难，仍继续第 4 步输出报告（报告中注明 MemPalace 写入失败）。

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

- 采集子 Agent 写 `TMP_DIR/debug/collect.json` 与 `TMP_DIR/difficulties/collect.json`；
- 每个分析子 Agent 写 `TMP_DIR/debug/analyze_<owner>__<repo>.json` 与 `TMP_DIR/difficulties/analyze_<owner>__<repo>.json`。

---

## 执行流程

### 第 0 步：准备与初始化

1. **获取当前真实时间**：本地时区当前时间（禁止模型截止时间、禁止凭记忆猜测）。
2. **检查 agent-browser**：`/usr/sbin/agent-browser --version`；失败则终止。
3. **检查 MemPalace MCP**：确认工具可用；失败则终止。
4. **解析 debug 开关**：按用户指令或默认值 `true`。
5. **创建 TMP_DIR**（仅 `debug=true`）：
   ```
   TMP_DIR/
   ├── collect/
   ├── analyze/
   ├── difficulties/
   └── debug/
   ```
   创建失败时降级 `./tmp/github_trend_<yymmddhhmmss>/`。
6. 记录各阶段计数器初始值：`merged_count`、`after_history_count`（供采集摘要使用）。最终报告头部的「总共分析项目」「分析失败项目」在 Step 4 按 `analysis_status` 实时统计，不预初始化。

### 第 1 步：采集子 Agent

主 Agent 启动**一个**采集子 Agent（Task），完成如下流程。子 Agent prompt 必须包含：`TMP_DIR`、`debug`、MemPalace **只读**参数、agent-browser 优先原则、debug JSON 格式、困难上报规范。

#### 1.1 趋势榜采集

| 来源 | URL | 采集上限 | 说明 |
|------|-----|------|----|
| OSS Insight | `https://ossinsight.io/trending?period=past_24_hours` | 20 | 该页面展示了过去 24 小时内的热门 github 项目 |
| GitHub Trending | `https://github.com/trending` | 20 | 该页面展示了 GitHub 当天的热门项目 |

- 使用 /usr/sbin/agent-browser 访问页面，提取 `https://github.com/<owner>/<repo>` 格式 URL
- 规范化：去掉尾部 `/`、query、fragment；统一小写 owner/repo 用于去重
- 合并两源列表，按 `owner/repo` 去重
- 单源失败时继续另一源，并上报 `[error]` 困难；**两源均失败则终止**
- 使用降级工具（非 agent-browser）时，必须上报 `[warning]` 困难
- **禁止安装 npm i -g agent-browser**
- `debug=true` 时写入：
  - `TMP_DIR/collect/ossinsight_urls.json` → `{"urls": [...], "count": N}`
  - `TMP_DIR/collect/github_trending_urls.json` → 同上
  - `TMP_DIR/collect/merged_urls.json` → `{"urls": [...], "count": N}`

#### 1.2 MemPalace 历史过滤

对上一步采集到的 github URL 进行去重查询：

```
mempalace_search(query="<owner>/<repo>", wing="github-trending", room="diary")
```

- 有命中 → 移除（已分析过）
- 无命中 → 保留
- `debug=true` 时写入 `TMP_DIR/collect/filtered_history.json`：
  ```json
  {"kept": [...], "removed": ["https://github.com/owner/repo", ...], "kept_count": Y, "removed_count": Z}
  ```

主 Agent / 采集子 Agent 须初始化并维护分类剔除列表 `excluded_urls`：

```json
{
  "history_analyzed": [],
  "star_insufficient": []
}
```

- Step 1.2 的 `removed` URL 填入 `excluded_urls.history_analyzed`（去重、保持首次出现顺序）
- `star_insufficient` 在采集阶段保持空数组，由 Step 2 主 Agent 在收到 `skipped_low_stars` 时追加
- **不含**第 2 步 `failed` 项目

`debug=true` 时可写入 `TMP_DIR/collect/excluded_urls.json` 快照（随 Step 2 追加更新）。

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

### 第 2 步：串行项目分析

主 Agent 对 `final_urls` **逐个、串行**启动分析子 Agent（**禁止并行**）。

每个分析子 Agent 结束时，主 Agent 须标记该项目 `analysis_status` 为以下三者之一：

- **success**：子 Agent 正常输出分析内容（含「未能从公开页面确认」等部分信息，但未标注「分析失败」）
- **failed**：子 Agent 输出含「分析失败」或中途无法完成分析（Star 已 ≥ 5000 但后续步骤失败）
- **skipped_low_stars**：Star < 5000 或无法可靠解析；子 Agent 返回极简结果，主 Agent 将 URL 追加到 `excluded_urls.star_insufficient`，**不拼接**项目报告块，**不计入** success/failed

每个分析子 Agent prompt 必须包含：目标 URL、`TMP_DIR`、`debug`、报告格式、语言要求（技术名词英文、说明中文）、禁止克隆代码、困难上报规范。

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

分析失败时（`analysis_status: failed`）：

  ```markdown
  ## <owner>/<repo>

  - **仓库地址**: https://github.com/<owner>/<repo>
  - **github star 数量**
  - **分析失败**：说明分析失败的原因（如仓库页面无法访问、工具调用失败等）
  ```

执行原则：
- **禁止**克隆仓库、浏览源码目录、读 commit 历史
- **上报困难** agent-browser 降级、页面异常、重试时，按困难上报规范记录
- **严格优先使用 agent-browser 获取信息**
- **禁止安装 npm i -g agent-browser**

**落盘（仅 debug=true**
- `TMP_DIR/analyze/<owner>__<repo>.md` — 写入上述 markdown（含「执行困难」块）
- `TMP_DIR/debug/analyze_<owner>__<repo>.json` — 操作日志（含 `difficulties`）
- `TMP_DIR/difficulties/analyze_<owner>__<repo>.json` — 困难记录

主 Agent 收集每个子 Agent 的 markdown 输出及 `analysis_status`，按 `final_urls` 顺序排列，供第 4 步拼接（**跳过** `skipped_low_stars` 项目，不纳入正文）；同时收集各「执行困难」块供汇总；维护分类 `excluded_urls`（`history_analyzed` 来自 Step 1，`star_insufficient` 来自本步 `skipped_low_stars`）供第 4 步报告使用。`debug=true` 时可在每次追加后更新 `TMP_DIR/collect/excluded_urls.json`。

### 第 3 步：写入 MemPalace（分析完成之后、输出报告之前）

由主 Agent 执行（不委派子 Agent）。

对第 2 步中 `analysis_status: success` 的每个 URL 调用 `mempalace_diary_write`（格式见 MemPalace 章节）。**禁止**写入 `failed` 或 `skipped_low_stars` 项目。

- 逐个写入；单条失败时上报 `[warning]` 困难并继续下一条
- `debug=true` 时写入 `TMP_DIR/collect/mempalace_written.json`：
  ```json
  {"written": [...], "skipped_failed": [...], "write_errors": [...]}
  ```
- 记录写入摘要（成功 N 条、跳过 M 条失败项目、写入错误 K 条），供第 4 步报告「执行困难汇总」引用

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

  ## 执行困难汇总

  主 Agent 合并采集子 Agent 与各分析子 Agent 上报的全部困难，按 severity 排序（error → warning → info），去重后列出：

  - [severity] stage | url | message | action_taken

  无困难时写：本次执行未上报困难。

  （若第 3 步有 MemPalace 写入，在此节末尾追加写入摘要：成功 N 条、跳过 M 条、错误 K 条）

  ## 调试统计信息（`debug=true` 时在报告末尾追加）
  主 Agent 读取 `TMP_DIR/debug/*.json`，累加各文件 `stats`。缺失文件则跳过，不中断。

    - 采集阶段 browser 调用次数: X
    - 分析阶段 browser 调用次数: Y
    - MemPalace 读取次数: Z
    - MemPalace 写入次数: W
    - 中间产物路径: <TMP_DIR>

  ```

## 异常处理

| 场景 | 处理 |
|------|------|
| agent-browser 不可用 | 终止，提示安装命令 |
| MemPalace 不可用（第 1 步） | 终止（无法历史去重） |
| MemPalace 不可用（第 3 步） | 上报困难，跳过写入，继续第 4 步输出报告 |
| 单源采集失败 | 继续另一源 |
| 两源均失败 | 终止 |
| 历史过滤后名单为空（`after_history_count == 0`） | 第 4 步输出「今日无新项目」，正常结束；跳过第 3 步；仍输出分类剔除节 |
| 单项目分析失败 | 记录错误，继续下一个；**不写入 MemPalace** |
| 第 3 步单条 MemPalace 写入失败 | 上报困难，继续下一条 |
| TMP_DIR 创建失败 | 降级 `./tmp/...` |
| debug JSON 缺失 | 统计时忽略 |

---

## 执行原则

- 优先获取本地真实时间
- 网页操作 agent-browser 优先
- 分析子 Agent 必须串行
- 最终报告仅 stdout，中间产物仅 debug 模式落盘
- 事实描述基于页面可见信息，不足时明确标注，禁止编造
- 遇到困难必须上报，禁止静默降级或静默跳过
- MemPalace 写入在第 3 步（分析完成之后、报告输出之前），且仅写入分析成功的项目
- **禁止安装 npm i -g agent-browser**
- **agent-browser CLI 调用命令，必须写全路径 `/usr/sbin/agent-browser`**
- Star 过滤在 Step 2 分析门禁执行，采集阶段禁止批量访问仓库页读 Star
