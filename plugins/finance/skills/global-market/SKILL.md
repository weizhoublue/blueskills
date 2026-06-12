---
name: global-market
description: 采集指定周期内影响美股、纳斯达克、黄金、美债、能源等资产的信息，形成资产配置参考报告，并在 debug 开启时记录调试日志与累计搜索/读写次数。
---

# Skill: global-market

## 1. 配置与全局变量

- `debug`: 默认为 `false`。
  - **启用条件**：用户在运行指令中明确要求（如包含“开启 debug”、“debug=true”或类似表述）时，将 `debug` 置为 `true`。

---

## 2. 工具使用规范

### 2.1 MemPalace 工具使用
MemPalace MCP 工具用于存储、查询和清理关键结论，固定参数为：
- `agent_name`: "claude"
- `wing`: "financial"
- `room`: "diary"

常见操作方法：
1. **读取最近记录**：
   ```javascript
   mempalace_diary_read(agent_name="claude", wing="financial", last_n=30)
   ```
2. **搜索历史记录**：
   ```javascript
   mempalace_search(query="...", wing="financial", room="diary")
   ```
3. **写入记录**（仅写入重要结论，不写完整报告）：
   ```javascript
   mempalace_diary_write(agent_name="claude", wing="financial", topic="...", entry="[记录生成日期: YYYY.MM.DD] <时间> <核心事实>；<影响判断>；<后续关注点>; <时效区间，如：2026.06.04 至 2026.06.11>")
   ```
4. **清理记录**：
   ```javascript
   mempalace_list_drawers(wing="financial", limit=100, offset=0)
   mempalace_delete_drawer(drawer_id="xxx")
   ```

### 2.2 联网搜索工具
优先级：
1. Tavily skill
2. exa mcp
3. firecrawl mcp
4. 其他可用联网搜索工具

---

## 3. 执行流程

### 第 0 步：准备与初始化
1. **获取当前真实时间**：获取本地时区的当前真实时间（禁止使用模型截止时间，禁止凭记忆猜测）。
2. **确认本地工具可用**：检查 MemPalace MCP 及至少一个联网搜索工具。若不可用则终止流程。
3. **创建 Debug 临时目录**：
   - 若 `debug` 为 `true`，根据当前本地时间生成唯一的时间戳标识 `<yymmddhhmmss>`（如 `260612112200`）。
   - 调试目录为 `/tmp/global_market_<yymmddhhmmss>/`。
   - 主 Agent 必须负责在初始化时告知后续调度的所有子 Agent 该目录路径。

### 第 1 步：解析用户周期
根据用户输入生成本次分析周期。未指定时默认：
- `analysis_start` = `analysis_now` - 7 天
- `analysis_end` = `analysis_now`
- `analysis_period_label` = 最近 7 天

常见周期映射：
- 最近一周 / 最近 7 天：analysis_now 往前 7 天
- 最近两周 / 最近 14 天：analysis_now 往前 14 天
- 最近一个月 / 最近 30 天：analysis_now 往前 30 天
- 本周：本周一 00:00 到 analysis_now
- 本月：本月 1 日 00:00 到 analysis_now
- 明确日期范围：使用用户指定开始和结束日期

### 第 2 步：生成统一时间范围
- 已发生事件范围：`event_start` = `analysis_start`，`event_end` = `min(analysis_end, analysis_now)`
- 历史对比范围：`comparison_start` = `analysis_start` - `周期长度`，`comparison_end` = `analysis_start`
- 未来事件范围：`upcoming_start` = `analysis_now`，`upcoming_end` = `analysis_now` + 28 天

所有搜索请求必须带有明确的时间范围，不要只搜索“最新”。

### 第 3 步：各主题事实采集（子 Agent 调度）
使用独立的子 Agent 分别采集如下 9 个主题的信息，**禁止融入任何主观判断**。

每个子 Agent 的通用执行指令：
1. 优先读取 MemPalace 中的最近记录以获取上下文（属于 `memory_read`）。
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
1. **Employment Situation 就业形势报告** (MemPalace topic: `EmploymentSituation`)
   - 报告内容：最近已发布报告解读（发布时间、是否过热、是否降温、是否影响降息、对纳债金影响）、下一次报告（发布时间、市场预判）。
2. **通胀数据 CPI** (MemPalace topic: `CPI`)
   - 报告内容：最近已发布解读（发布时间、是否降温、是否影响政策与收益率、对纳债金影响）、下一次报告（发布时间、市场预判）。
3. **PCE** (MemPalace topic: `PCE`)
   - 报告内容：最近已发布解读（发布时间、Core PCE 是否符合回落路径、是否影响政策与降息预期、对纳债金影响）、下一次报告（发布时间、市场预判）。
4. **美联储降息会议 FOMC** (MemPalace topic: `FOMC`)
   - 报告内容：最近一次解读（发布时间、利率决议、声明措辞、对纳债金影响）、下一次会议（时间、市场预判）。
5. **美债收益率** (MemPalace topic: `TreasuryYield`)
   - 报告内容：10年期与2年期走势事实、根因分析、买入/卖出投资建议、对其他市场的影响。
6. **纳斯达克指数** (MemPalace topic: `NasdaqTrend`)
   - 报告内容：指数走势说明、根因分析、短期预期、涨跌幅前3行业、买入/卖出投资建议。
7. **黄金** (MemPalace topic: `Gold`)
   - 报告内容：走势事实、根因分析、对纳债影响、买入/卖出投资建议。
8. **能源** (MemPalace topic: `Energy`)
   - 报告内容：原油、天然气、煤矿走势事实、根因分析、对纳债等市场的影响。
9. **美股大型科技公司** (MemPalace topic: `TechEarnings`)
   - 报告内容：大厂（Nvidia, Microsoft, Apple, Amazon, Meta, Alphabet, Tesla, Broadcom, AMD）下次财报日期/市场预判、上次财报事实与反应、重大消息3条、AI需求预期/担忧/风险、买卖建议。

### 第 4 步：整合报告
1. 使用 `productivity:caveman-cn` 格式整合所有子 Agent 输出，形成最终的资产配置参考报告。
2. 表达简短，突出核心结论，严禁冗长叙述。
3. **Debug 数据汇总**（当 `debug` 为 `true` 时）：
   - 主 Agent 读取 `/tmp/global_market_<yymmddhhmmss>/` 下所有 `debug_<subagent>.json` 文件。
   - 解析并累加所有文件的 `stats` 计数。
   - 在整合报告的最后呈现：
     ```markdown
     ### 调试统计信息
     - 进行联网搜索的次数：X
     - 通过本地的记忆存储搜索的次数：Y
     - 对于本地记忆写入的次数：Z
     ```

### 第 5 步：清理 MemPalace 过时记录
1. 创建独立子 Agent，清理 `wing="financial"` 中所有早于 `(event_start - 4 个月)` 的历史记录。
2. 循环使用 `mempalace_list_drawers(wing="financial", limit=100, offset=offset)`，对比 created_at 时间戳，调用 `mempalace_delete_drawer(drawer_id="xxx")` 逐个删除过期记录。

---

## 4. 执行原则
- 优先获取本地当前真实时间。
- 搜索词带上明确的时间范围。
- 事实、判断、建议三者必须严格分离。
- 仅将重要核心结论写入 MemPalace。
