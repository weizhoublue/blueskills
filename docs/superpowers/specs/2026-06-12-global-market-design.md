# Design Spec: Global Market Skill Development with Debug Capability

## 1. 目标 (Goals)
根据 [read.md](file:///Users/weizhoulan/Documents/git/blueskills/plugins/finance/skills/global-market/read.md) 的需求，开发 [SKILL.md](file:///Users/weizhoulan/Documents/git/blueskills/plugins/finance/skills/global-market/SKILL.md) 全球市场分析工具的 Claude Code 插件。同时，新增全局 debug 变量及相应的调试文件落盘和统计机制。

## 2. 核心功能设计 (Core Design)

### 2.1 基础分析流
按照 [read.md](file:///Users/weizhoulan/Documents/git/blueskills/plugins/finance/skills/global-market/read.md) 执行流程开发，包括：
1. 解析用户周期并生成统一时间范围。
2. 调度 9 个子 Agent 对不同主题（就业、CPI、PCE、FOMC、美债、纳斯达克、黄金、能源、科技巨头）进行事实采集。
3. 主 Agent 整合子 Agent 输出（使用 caveman-cn 格式压缩表达）。
4. 清理 MemPalace 过期数据（删除 4 个月前的历史记录）。

### 2.2 全局 Debug 机制
- **变量定义**：在 SKILL.md 中定义全局变量 `debug`，默认关闭 (`false`)。当用户指令中包含 `开启 debug` 或显式指定时，置为 `true`。
- **动态临时目录**：主 Agent 初始化时根据当前时间生成唯一的时效性目录 `/tmp/global_market_<yymmddhhmmss>/`。
- **子 Agent 落盘行为**：
  - 当 `debug` 开启时，子 Agent 进行的每一次联网搜索（Tavily, Exa, Firecrawl 等）和本地记忆读写（MemPalace），都必须将搜索关键词/读写条件和结果以 JSON 格式追加写入文件 `/tmp/global_market_<yymmddhhmmss>/debug_<subagent>.json`。
  - 单个 JSON 文件结构示例如下：
    ```json
    {
      "logs": [
        {
          "timestamp": "2026-06-12T11:20:00Z",
          "action": "web_search",
          "query": "US CPI May 2026",
          "result": "Headline CPI YoY 3.1%, Core CPI YoY 3.4%..."
        },
        {
          "timestamp": "2026-06-12T11:20:15Z",
          "action": "memory_read",
          "query": "topic: CPI, wing: financial, last_n: 30",
          "result": "..."
        }
      ],
      "stats": {
        "web_searches": 1,
        "memory_reads": 1,
        "memory_writes": 0
      }
    }
    ```

### 2.3 数据汇总与呈现
- 整合报告阶段，主 Agent 扫描并读取 `/tmp/global_market_<yymmddhhmmss>/` 目录下的所有 `debug_<subagent>.json` 文件。
- 提取并累加所有文件的 `stats` 计数值。
- 在报告的最末尾输出如下格式的数据汇总：
  ```markdown
  ### 调试统计信息
  - 进行联网搜索 of 次数：X
  - 通过本地的记忆存储搜索 of 次数：Y
  - 对于本地记忆写入 of 次数：Z
  ```

## 3. 单元职责划分 (Component Responsibilities)

| 模块 | 职责 | 依赖工具 |
|------|------|----------|
| 主 Agent | 解析周期、分发任务、汇总报告、读取临时文件累加次数、输出调试统计。 | 文件读写工具、caveman-cn 压缩能力 |
| 子 Agent | 各主题信息采集。如果 debug 开启，负责在每次操作时调用文件写入工具输出 debug 文件。 | 联网搜索工具（Tavily/Exa/Firecrawl）、MemPalace MCP、文件写入工具 |
| 清理 Agent | 清理 4 个月前的过期 MemPalace 数据。 | MemPalace MCP |

## 4. 异常处理 (Error Handling)
- **临时目录创建失败**：若因权限等问题无法创建 `/tmp/` 子目录，则降级写入当前 workspace 的 `./tmp/global_market_<yymmddhhmmss>/`。
- **文件读取失败/缺失**：若某个子 Agent 没有写入日志，汇总时主 Agent 忽略该子 Agent 的统计而不会抛错中断流程。
