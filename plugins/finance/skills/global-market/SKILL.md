---
name: global-market
description: 采集指定周期内影响美股、黄金、美债、能源等资产的信息，形成资产配置参考报告。
---

# Skill: global-market

**采集指定周期内影响美股、纳斯达克、黄金、美债、能源等资产的信息，形成资产配置参考报告**

## 调用场景

**适用**
- 进行美股、黄金、美债等全球资产配置分析时，采集近期市场信息形成参考报告

## 配置与全局变量

- `debug`: 默认为 `false`。
  - **启用条件**：用户在运行指令中明确要求（如包含“开启 debug”、“debug=true”或类似表述）时，将 `debug` 置为 `true`。

---

## 工具使用规范

### MemPalace MCP 使用

MemPalace MCP 用于存储、查询和清理关键结论。

固定参数为：
- `agent_name`: "claude"
- `wing`: "financial"
- `room`: "diary"

MemPalace MCP 提供了多个 tool, 常见操作方法：

1. **读取最近记录**：
   mempalace_diary_read(agent_name="claude", wing="financial", last_n=30)

2. **搜索历史记录**：
   mempalace_search(query="...", wing="financial", room="diary")

3. **写入记录**（仅写入重要结论，不写完整报告）：
   mempalace_diary_write(agent_name="claude", wing="financial", topic="...", entry="[记录生成日期: YYYY.MM.DD] <时间> <核心事实>；<影响判断>；<后续关注点>; <时效区间，如：2026.06.04 至 2026.06.11>")

4. **清理记录**：
   mempalace_list_drawers(wing="financial", limit=100, offset=0)
   mempalace_delete_drawer(drawer_id="xxx")

### 联网搜索工具

**所有联网搜索的行为，尤其是 subagent 的执行中，必须严格遵循如下调用优先级，当一个工具不可用时，再尝试使用低优先级的工具**
1. Tavily skill
2. exa mcp
3. firecrawl mcp
4. 其他可用联网搜索工具

---

## 执行流程

### 第 0 步：准备与初始化

1. **获取当前真实时间**：获取本地时区的当前真实时间（禁止使用模型截止时间，禁止凭记忆猜测)
2. **确认本地工具可用**：检查 MemPalace MCP 及至少一个联网搜索工具。若不可用则终止流程。
3. **创建 Debug 临时目录**：
   - 若 `debug` 为 `true`，根据当前本地时间生成唯一的时间戳标识 `<yymmddhhmmss>`（如 `260612112200`）。
   - 调试目录为 `/tmp/global_market_<yymmddhhmmss>/`。
   - 主 Agent 必须负责在初始化时告知后续调度的所有子 Agent 该目录路径。

### 第 1 步：解析分析周期

根据用户输入生成本次分析周期。所有搜索请求必须带有明确的时间范围，不要只搜索“最新”。
- `event_start` = ``analysis_now` - 7 天
- `event_end` = `analysis_now`

常见周期映射：
- 最近一周 / 最近 7 天：analysis_now 往前 7 天
- 最近两周 / 最近 14 天：analysis_now 往前 14 天
- 最近一个月 / 最近 30 天：analysis_now 往前 30 天
- 本周：本周一 00:00 到 analysis_now
- 本月：本月 1 日 00:00 到 analysis_now
- 明确日期范围：使用用户指定开始和结束日期

### 第 2 步：各主题事实采集（子 Agent 调度）

使用独立的子 Agent 分别采集如下所有主题的信息，**禁止融入任何主观判断**。

每个子 Agent 的通用执行指令：
1. 优先读取 MemPalace 中的最近记录以获取上下文（属于 `memory_read`），尝试获取已记录信息。
2. 若记录时效不足或缺失，执行联网搜索补充信息（属于 `web_search`）。
3. 提取最新关键结论，写入 MemPalace（属于 `memory_write`）。
4. **Debug 日志落盘与计数**（当 `debug` 为 `true` 时）：
   - 子 Agent 在执行任一操作（网络搜索、本地记忆读取、本地记忆写入）后，必须将其以 JSON 格式追加/更新到调试文件 `/tmp/global_market_<yymmddhhmmss>/debug_<subagent>.json` 中。
   - 子 Agent 内部维护累计计数器，在每次操作后，更新 JSON 中的 `stats` 计数。
   - 单个日志 JSON 格式必须为：
     ```json
     {
       "logs": [
         {
           "timestamp": "YYYY-MM-DDTHH:mm:ssZ",
           "action": "web_search | memory_read | memory_write",
           "query": "动作参数或搜索关键词",
           "result": "返回结果摘要"
         }
       ],
       "stats": {
         "web_searches": 0,
         "memory_reads": 0,
         "memory_writes": 0
       }
     }
     ```
5. 输出指定的主题 markdown 报告。

#### 主题列表与报告要求：
1. **美国就业形势报告 Employment Situation** 
  MemPalace topic: `EmploymentSituation`
  报告内容：
    - 最近已发布报告解读：发布时间、对纳债金影响（非主观判断）
    - 下一次报告（发布时间、市场预判）

2. **美国通胀数据 CPI** 
  MemPalace topic: `CPI`
  报告内容：
    - 最近已发布解读：发布时间、对纳债金影响（非主观判断）
    - 下一次报告（发布时间、市场预判）

3. **美国个人消费支出价格指数 PCE** 
  MemPalace topic: `PCE`
  报告内容：
    - 最近已发布解读：发布时间、对纳债金影响（非主观判断）
    - 下一次报告（发布时间、市场预判）

4. **美联储降息会议 FOMC** 
  MemPalace topic: `FOMC`
  报告内容：
    - 最近一次解读：发布时间、对纳债金影响（非主观判断）
    - 下一次会议（时间、市场预判）

5. **美债收益率** 
  MemPalace topic: `TreasuryYield`
  报告内容：
    - event_start 至 event_end 期间，10年期与2年期美债走势事实
    - 市场对于根因的分析（非主观判断）
    - 市场对于短期内的买入/卖出投资建议（非主观判断）
    - 市场对纳债金影响判断（非主观判断）

6. **纳斯达克指数** 
  MemPalace topic: `NasdaqTrend`
  报告内容：
    - event_start 至 event_end 期间，指数走势说明
    - 涨跌幅前3行业
    - 市场对于根因的分析（非主观判断）
    - 市场对于短期内的买入/卖出投资建议（非主观判断）

7. **黄金** 
  MemPalace topic: `Gold`
  报告内容：
    - event_start 至 event_end 期间，走势事实
    - 市场对于根因的分析（非主观判断）
    - 市场对于短期内的买入/卖出投资建议（非主观判断）

8. **全球能源** 
  MemPalace topic: `Energy`
  分析范围：原油、天然气、煤矿
  报告内容：
    - event_start 至 event_end 期间，每个能源的走势事实
    - 市场对于根因的分析（非主观判断）
    - 市场对于短期内的买入/卖出投资建议（非主观判断）

9. **美股大型科技公司** 
  MemPalace topic: `TechEarnings`
  分析公司范围：Nvidia, Microsoft, Apple, Amazon, Meta, Alphabet, Tesla, Broadcom, AMD
  报告内容：
    - 每个公司的上次财报时间、市场反应（非主观判断）
    - 每个公司的下次财报日期、市场预判（非主观判断）
    - 市场对于每个公司短期内的买入/卖出投资建议（非主观判断）

### 第 4 步：整合报告

整合所有子 Agent 输出为一份完整的 markdown 格式的报告，禁止对 agent 输出报告进行总结和优化，

**Debug 数据汇总**（当 `debug` 为 `true` 时）：
   - 主 Agent 读取 `/tmp/global_market_<yymmddhhmmss>/` 下所有 `debug_<subagent>.json` 文件。
   - 解析所有文件的 `stats` 计数。
   - 在整合报告的最后呈现：
     ```markdown
     ### 调试统计信息
     - 每一个主题的联网搜索次数：X
     - 每一个主题通过本地的记忆存储搜索的次数：Y
     - 每一个主题对于本地记忆写入的次数：Z
     - 总计联网搜索次数：X
     - 总计通过本地的记忆存储搜索的次数：Y
     - 总计对于本地记忆写入的次数：Z     
     ```

### 第 5 步：清理 MemPalace 过时记录

创建独立子 Agent，清理 `wing="financial"` 中所有早于 `(event_start - 4 个月)` 的历史记录：

循环使用 `mempalace_list_drawers(wing="financial", limit=100, offset=offset)`，对比 created_at 时间戳，调用 `mempalace_delete_drawer(drawer_id="xxx")` 逐个删除过期记录。

---

## 4. 执行原则
- 优先获取本地当前真实时间。
- 搜索词带上明确的时间范围。
- 事实、判断、建议三者必须严格分离。
- 仅将重要核心结论写入 MemPalace。
