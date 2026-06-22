# Design Spec: GitHub Trend Daily Report Skill

## 1. 目标

在 `blueskills` 仓库中新增 `news` 插件及其下的 `github-trend` skill。用户手动调用后，自动采集当日 GitHub 趋势项目，过滤已分析项目和低 star 项目，串行分析剩余仓库，并将汇总报告输出到 stdout。

需求来源：[README.md](../../../README.md)

## 2. 已确认的产品决策

| 决策项 | 选择 |
|--------|------|
| 触发方式 | 用户手动调用（如 `/news:github-trend` 或自然语言） |
| 最终报告输出 | 仅 stdout，不写最终汇总文件 |
| 中间产物 | `debug=true` 时落盘到临时目录，便于调试追溯 |
| GitHub Trending 范围 | 仅默认页（约 25 个仓库） |
| Debug 机制 | 对齐 `global-market`：默认 `debug=true`，用户可关闭；开启时记录 JSON 日志并在报告末尾附统计 |
| MemPalace topic | 统一 `analyzed-repos`，通过 `mempalace_search` 按 URL/repo 名去重 |
| 分析深度 | 轻量：仅 GitHub 仓库页公开信息，不克隆代码 |
| 报告语言 | 混合：技术名词保留英文，说明性文字用中文 |

## 3. 方案选择

采用**方案 A：单 SKILL 编排**，与 `finance/global-market` 一致。主 Agent 通过 Task 调度子 Agent，不引入辅助脚本或拆分 skill。

## 4. 插件结构

```
plugins/news/
├── .claude-plugin/plugin.json
└── skills/github-trend/
    └── SKILL.md

.claude-plugin/marketplace.json   # 注册 news 插件
```

- 插件名：`news`
- Skill 名：`github-trend`（kebab-case）
- 调用示例：`/news:github-trend`

### plugin.json 要点

```json
{
  "name": "news",
  "displayName": "News",
  "version": "0.1.0",
  "description": "GitHub 趋势项目日报采集与分析；github-trend skill",
  "keywords": ["news", "github", "trending", "mempalace"],
  "license": "MIT"
}
```

## 5. 全局变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `debug` | `true` | 用户指令含「关闭 debug」「debug=false」等时置 `false` |
| `TMP_DIR` | `/tmp/github_trend_<yymmddhhmmss>/` | 主 Agent 初始化时生成；创建失败时降级为 `./tmp/github_trend_<yymmddhhmmss>/` |

主 Agent 必须在初始化时获取本地真实时间（禁止用模型截止时间），并将 `TMP_DIR` 路径告知所有子 Agent。

## 6. 临时目录结构

仅在 `debug=true` 时创建并写入：

```
TMP_DIR/
├── collect/
│   ├── ossinsight_urls.json       # OSS Insight 原始 URL 列表
│   ├── github_trending_urls.json  # GitHub Trending 原始 URL 列表
│   ├── merged_urls.json           # 两源合并去重后
│   ├── filtered_history.json      # MemPalace 历史过滤后
│   └── filtered_stars.json        # star ≥ 5000 后的最终候选名单
├── analyze/
│   └── <owner>__<repo>.md         # 每个项目的分析报告
└── debug/
    ├── collect.json               # 采集子 Agent 操作日志
    └── analyze_<owner>__<repo>.json  # 各分析子 Agent 操作日志
```

### debug JSON 格式

对齐 `global-market`，每个 debug 文件结构：

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

`debug=false` 时：不创建 `TMP_DIR`，不落盘中间产物和 debug JSON。

## 7. 执行流程

### 第 0 步：准备与初始化

1. 获取本地时区当前真实时间。
2. 检查 **agent-browser** CLI 可用（`agent-browser --version`）；不可用则终止并提示安装。
3. 检查 **MemPalace MCP** 可用；不可用则终止（无法完成历史去重与记录）。
4. 解析 `debug` 开关。
5. 若 `debug=true`，创建 `TMP_DIR` 并记录路径。

### 第 1 步：采集子 Agent

由一个独立子 Agent 完成采集与过滤全流程。

#### 1.1 趋势榜采集

使用 **agent-browser**（优先）访问以下页面并提取 `https://github.com/<owner>/<repo>` 格式的 URL：

| 来源 | URL | 数量 |
|------|-----|------|
| OSS Insight | `https://ossinsight.io/trending?period=past_24_hours` | 前 20 |
| GitHub Trending | `https://github.com/trending` | 默认页全部（约 25） |

- 两源 URL 合并后按 `owner/repo` 去重。
- `debug=true` 时分别写入 `collect/ossinsight_urls.json`、`collect/github_trending_urls.json`、`collect/merged_urls.json`。

**工具降级顺序**（agent-browser 失败时）：

1. Tavily extract skill
2. Exa web fetch MCP
3. Firecrawl scrape MCP

#### 1.2 MemPalace 历史过滤

对每个候选 URL，调用：

```
mempalace_search(query="<owner>/<repo>", wing="github-trending", room="diary")
```

- 若命中历史记录（该项目曾分析过），从候选名单移除。
- `debug=true` 时写入 `collect/filtered_history.json`。

MemPalace 固定参数：

- `agent_name`: `"claude"`
- `wing`: `"github-trending"`
- `room`: `"diary"`
- `topic`: `"analyzed-repos"`

#### 1.3 Star 数量过滤

对剩余每个 URL，使用 agent-browser 访问 GitHub 仓库页，读取 star 数。

- star < 5000：剔除。
- star ≥ 5000：保留。
- `debug=true` 时写入 `collect/filtered_stars.json`。

#### 1.4 写入 MemPalace

对最终候选名单中的每个 URL，调用：

```
mempalace_diary_write(
  agent_name="claude",
  wing="github-trending",
  topic="analyzed-repos",
  entry="[YYYY.MM.DD.HH.MM.SS] https://github.com/<owner>/<repo>"
)
```

写入时间戳使用本地真实时间。

子 Agent 输出：最终候选 URL 列表（供主 Agent 调度第 2 步）。

### 第 2 步：串行项目分析

主 Agent 对第 1 步输出的每个 URL **串行**启动独立子 Agent（禁止并行，避免浏览器会话冲突）。

每个分析子 Agent：

1. 使用 agent-browser 访问 `https://github.com/<owner>/<repo>`。
2. 从 README、About、仓库描述等公开信息提取：
   - 该项目要解决的问题
   - 该项目的功能
3. 禁止克隆代码或深入源码目录。
4. 输出固定格式 markdown（见第 8 节）。
5. `debug=true` 时落盘到 `analyze/<owner>__<repo>.md` 和 `debug/analyze_<owner>__<repo>.json`。

单个项目分析失败时：在该项目 md 中记录错误原因，继续下一个项目。

### 第 3 步：整合报告

主 Agent 将所有子 Agent 的分析 markdown **原样拼接**（禁止改写或总结），输出到 **stdout**。

## 8. 报告格式

### 单项目分析（子 Agent 输出）

```markdown
## <owner>/<repo>

- **仓库地址**: https://github.com/<owner>/<repo>
- **要解决的问题**: （中文说明，技术名词保留英文）
- **功能**: （中文说明，列举核心功能点）
```

### 最终 stdout 报告（主 Agent 输出）

```markdown
# GitHub Trending 日报

生成时间: YYYY.MM.DD HH:MM:SS（本地时区）
数据来源: OSS Insight (past 24h, top 20) + GitHub Trending (默认页)
候选项目数: X → 历史过滤后: Y → star 过滤后: Z → 本次分析: N

---

（按顺序拼接各项目 analyze/*.md 内容，禁止改写）

---

### 调试统计信息

（仅 debug=true 时输出）
- 采集阶段 agent-browser 调用次数: X
- 分析阶段 agent-browser 调用次数: Y
- MemPalace 读取次数: Z
- MemPalace 写入次数: W
- 中间产物路径: /tmp/github_trend_<ts>/
```

主 Agent 在 `debug=true` 时读取 `debug/` 下所有 JSON 文件的 `stats` 并累加。

## 9. 单元职责

| 模块 | 职责 | 依赖 |
|------|------|------|
| 主 Agent | 初始化、调度采集/分析子 Agent、拼接 stdout 报告、汇总 debug 统计 | agent-browser、MemPalace、文件读写 |
| 采集子 Agent | 双源采集、合并去重、历史过滤、star 过滤、MemPalace 写入 | agent-browser、MemPalace |
| 分析子 Agent（×N，串行） | 访问仓库页、生成单项分析报告 | agent-browser |

## 10. 异常处理

| 场景 | 处理 |
|------|------|
| agent-browser 不可用 | 终止流程，提示 `npm i -g agent-browser && agent-browser install` |
| MemPalace 不可用 | 终止流程（无法去重/记录） |
| 单个源采集失败 | 继续使用另一源；两源均失败则终止 |
| 历史过滤后名单为空 | stdout 输出「今日无新项目」，正常结束 |
| star 过滤后名单为空 | 同上 |
| 单个项目分析失败 | 记录错误，继续下一个；最终报告保留失败项标注 |
| TMP_DIR 创建失败 | 降级到 `./tmp/github_trend_<ts>/` |
| debug JSON 缺失 | 汇总统计时忽略该文件，不中断流程 |

## 11. 不在范围内

- 定时自动执行（cron / hook）
- 克隆仓库或源码级分析
- GitHub Trending 多语言 tab 遍历
- 最终报告落盘
- MemPalace 历史记录自动清理（本 skill 只写不删）

## 12. 实现交付物

1. `plugins/news/.claude-plugin/plugin.json`
2. `plugins/news/skills/github-trend/SKILL.md`（完整编排指令）
3. `.claude-plugin/marketplace.json` 注册 `news` 插件
