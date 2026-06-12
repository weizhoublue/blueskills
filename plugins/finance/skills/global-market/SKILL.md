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

`debug`: 默认为 `true`。

**启用条件**：用户如在运行指令中明确要求（如包含“开启 debug”、“debug=true”、“开启调试“、“关闭调试“等类似表述）时，将 `debug` 置为 `true` 或者 `false`，否则保持默认值。

---

## 工具使用规范

### MemPalace MCP 使用

MemPalace MCP 用于存储、查询和清理关键结论。

固定参数为：
- `agent_name`: "claude"
- `wing`: "financial"
- `room`: "diary"

MemPalace MCP 提供了多个 tool, 常见操作方法：

1. **写入记录**（仅写入重要结论，不写完整报告）：
   mempalace_diary_write(
    agent_name="claude", 
    wing="financial", 
    topic="...", 
    entry="[写入时间 YYYY.MM.DD.HH.MM.SS] <事件发生时间> <核心事实>；<影响判断>；<后续关注点>; <内容时效区间 YYYY.MM.DD 至 YYYY.MM.DD>"
  )

2. **读取最近记录**：
   mempalace_diary_read(agent_name="claude", wing="financial", topic="...", last_n=30)

3. **搜索历史记录**：
   mempalace_search(query="...", wing="financial", room="diary")


4. **清理记录**：
   mempalace_list_drawers(wing="financial", limit=100, offset=0)
   mempalace_delete_drawer(drawer_id="xxx")

**MemPalace 历史记录的使用原则**
- 必须严格判断其中的 `内容时效区间`和当前的分析周期，禁止使用过期的信息
- 如果有多条记录有效，优先使用`写入时间`最新的记录
- 读取和写入的记录仅限于自身场景的 MemPalace topic，禁止跨 topic 读取和写入

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

**必须告知每个 agent 如下信息获取等级**
- Allow_MemPalace 代表本信息优先从 MemPalace 缓存记录来获取和更新，如果查询不到，则尝试联网查询。并最终把最新结论写入 MemPalace 以供下次查询。
- Only_Search 代表本信息禁止使用 MemPalace， 必须通过联网搜索工具实时查询获取

**必须告知每个 MemPalace MCP 方法**

**必须告知每个 agent 如下联网搜索工具使用原则**
- 所有联网搜索的行为，必须严格遵循如下调用优先级，当一个工具不可用时，再尝试使用低优先级的工具
  1. Tavily skill
  2. exa mcp
  3. firecrawl mcp
  4. 其他可用联网搜索工具
- 每个 subagent 有明确的联网搜索次数上限

**每个子 Agent 的通用执行指令**：
1. 根据信息的 Allow_MemPalace / Only_Search 等级标注，进行相关查询
2. 如通过联网搜索获取了最新的补充信息，则提取最新关键结论，写入 MemPalace（属于 `memory_write`）。写入的原则是：
   - 对于同一事件的相同时间周期内的信息更新，进行记录更新，而非追加新记录
   - 对于同一事件的不同时间周期内的新信息，追加新记录，而不允许修改之前的记录
   - 对于不同一事件的信息，追加新记录
3. **Debug 日志落盘与计数**（当 `debug` 为 `true` 时）：
   - 子 Agent 在执行任一操作（网络搜索、本地记忆读取、本地记忆写入）后，必须将其以 JSON 格式追加/更新到调试文件 `/tmp/global_market_<yymmddhhmmss>/debug_<subagent>.json` 中。
   - 子 Agent 内部维护累计计数器，在每次操作后，更新 JSON 中的 `stats` 计数。
   - **必须告知每个 agent 遵循如下日志 JSON 格式，避免格式不一致导致调试信息无法统一解析**：
     ```json
     {
       "logs": [
         {
           "timestamp": "YYYY-MM-DDTHH:mm:ssZ",
           "action": "web_search | memory_read | memory_write",
           "query": "mcp tool 调用的完整参数、或联网搜索的关键词",
           "result": "返回结果前 100 字 ",
           "length": "返回结果的字符串长度"
         }
       ],
       "stats": {
         "web_searches": 0,
         "memory_reads": 0,
         "memory_writes": 0
       }
     }
     ```
4. 输出指定的主题 markdown 报告。

#### 主题列表与报告要求：
1. **美国就业形势报告 Employment Situation** 
  MemPalace topic: `EmploymentSituation`
  联网搜索次数上限: 5
  报告内容：
    - (Allow_MemPalace)最近已发布报告解读：发布时间、对纳债金的影响（明确指出影响性质：刺激上涨或下跌）。非主观判断
    - (Allow_MemPalace)下一次报告发布时间
    - (Only_Search)市场对于下一次报告的形势预判、对纳债金的影响（明确指出影响性质：刺激上涨或下跌）

2. **美国通胀数据 CPI** 
  MemPalace topic: `CPI`
  联网搜索次数上限: 5
  报告内容：
    - (Allow_MemPalace)最近已发布解读：发布时间、对纳债金影响（明确指出影响性质：刺激上涨或下跌）。 非主观判断
    - (Allow_MemPalace)下一次报告发布时间
    - (Only_Search)市场对于下一次报告的形势预判、对纳债金的影响（明确指出影响性质：刺激上涨或下跌）

3. **美国个人消费支出价格指数 PCE** 
  MemPalace topic: `PCE`
  联网搜索次数上限: 5
  报告内容：
    - (Allow_MemPalace)最近已发布解读：发布时间、对纳债金影响（明确指出影响性质：刺激上涨或下跌）。 非主观判断
    - (Allow_MemPalace)下一次报告发布时间
    - (Only_Search)市场对于下一次报告的形势预判、对纳债金的影响（明确指出影响性质：刺激上涨或下跌）

4. **美联储降息会议 FOMC** 
  MemPalace topic: `FOMC`
  联网搜索次数上限: 10
  报告内容：
    - (Allow_MemPalace)最近一次解读：发布时间、对纳债金影响（明确指出影响性质：刺激上涨或下跌）。 非主观判断
    - (Allow_MemPalace)下一次会议时间
    - (Only_Search)市场对于下一次报告的形势预判、对纳债金的影响（明确指出影响性质：刺激上涨或下跌）

5. **美债收益率** 
  MemPalace topic: `TreasuryYield`
  联网搜索次数上限: 10
  报告内容：
    - (Allow_MemPalace)event_start 至 event_end 期间，10年期与2年期美债走势事实
    - (Allow_MemPalace)市场对于根因的分析（非主观判断）
    - (Allow_MemPalace)市场对于短期内的长短债的投资建议，并明确指出结论买入或卖出（非主观判断）
    - (Only_Search)市场对 event_end 之后的美债走势判断，以及对纳债金影响的影响（明确指出影响性质：刺激上涨或下跌）。 非主观判断

6. **纳斯达克指数** 
  MemPalace topic: `NasdaqTrend`
  联网搜索次数上限: 10
  报告内容：
    - (Allow_MemPalace) event_start 至 event_end 期间，指数走势事实阐述
    - (Allow_MemPalace) 涨跌幅前3行业
    - (Allow_MemPalace) 市场对于根因的分析（非主观判断）
    - (Only_Search) event_end 之后短期内影响纳斯达克的事件，事件内容和发生时间
    - (Only_Search)市场对于 event_end 之后短期内的投资建议，并明确指出结论买入或卖出（非主观判断）

7. **黄金** 
  MemPalace topic: `Gold`
  联网搜索次数上限: 5
  报告内容：
    - (Allow_MemPalace)event_start 至 event_end 期间，走势事实
    - (Allow_MemPalace) 市场对于根因的分析（非主观判断）
    - (Only_Search)市场对于 event_end 之后短期内的最新投资建议，并明确指出结论买入或卖出（非主观判断）

8. **全球能源** 
  MemPalace topic: `Energy`
  联网搜索次数上限: 10
  分析范围：原油、天然气、煤矿
  报告内容：
    - (Allow_MemPalace) event_start 至 event_end 期间，每个能源的走势事实
    - (Allow_MemPalace) 市场对于根因的分析（非主观判断）
    - (Only_Search) 市场对于 event_end 之后短期内的投资最新建议，并明确指出结论买入或卖出（非主观判断）

9. **美股大型科技公司** 
  MemPalace topic: `TechEarnings`
  联网搜索次数上限: 30
  分析公司范围：Nvidia, Microsoft, Apple, Amazon, Meta, Google, Tesla, Broadcom, AMD
  报告内容：
    - (Allow_MemPalace)每个公司的上次财报时间、市场反应（非主观判断）
    - (Allow_MemPalace)每个公司的下次财报日期、市场预判（非主观判断）
    - (Only_Search) 市场对于 event_end 之后每个公司短期内的投资建议，并明确指出结论买入或卖出，每个公司用中文名称呼。非主观判断

### 第 4 步：整合报告

整合所有子 Agent 输出为一份完整的 markdown 格式的报告，格式如下：

  ```markdown
  # 全球市场资产配置分析报告

  分析周期  YYYY.MM.DD 至 YYYY.MM.DD （本地时区）

  ## xxx 主题报告

  某 subagent 输出的完整报告（禁止任何修改和总结优化）

  ```

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
  - 中间产物路径: /tmp/global_market_<yymmddhhmmss>
  ```

### 第 5 步：清理 MemPalace 过时记录

创建独立子 Agent，清理 `wing="financial"` 中所有早于 `(event_start - 4 个月)` 的历史记录：

循环使用 `mempalace_list_drawers(wing="financial", limit=100, offset=offset)`，对比 created_at 时间戳，调用 `mempalace_delete_drawer(drawer_id="xxx")` 逐个删除过期记录。

---

## 执行原则
- 优先获取本地当前真实时间。
- 搜索词带上明确的时间范围。
- 事实、判断、建议三者必须严格分离。
