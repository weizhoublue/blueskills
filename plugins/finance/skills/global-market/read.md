---
name: global-market
description: 采集指定周期内影响美股、纳斯达克、黄金、美债、能源等资产的信息，形成资产配置参考报告，并用 MemPalace 记录关键结论。
---

# Skill: global-market

## 目标

根据用户指定周期，采集影响美股和资产配置的关键信息，形成资产配置参考报告。

---

## 工具使用

### MemPalace 工具使用

MemPalace 提供了 MCP 工具，用于存储记录一些关键信息，供后续分析参考：

**读取最近记录**

示例：
    mempalace_diary_read(
      agent_name="claude",
      wing="financial",
      last_n=30
    )

**搜索历史记录**

按主题搜索历史记录。

示例：
    mempalace_search(
      query="纳斯达克 CPI FOMC 美债 黄金 能源",
      wing="financial",
      room="diary"
    )

**写入记录**

只写重要结论，不写完整报告。

示例：
    mempalace_diary_write(
      agent_name="claude",
      wing="financial",
      topic="AssetAllocation",
      entry="[2026.06.11] 基于 2026.06.04 至 2026.06.11 的市场信息....."
    )

entry 格式：
    [记录生成日期: YYYY.MM.DD] <事件发生时间> <核心事实>；<影响判断>；<后续关注点>; <该信息的时效区间，例如：2026.06.04 至 2026.06.11>

**固定参数**

所有 MemPalace 记录必须严格使用如下参数：
- agent_name: claude
- wing: financial
- room: diary

topic 按照不同的分析内容设置对应的值

---

### 联网搜索信息工具使用

- 优先使用 Tavily skill 
- 如果寻找不到信息，尝试使用 exa mcp
- 如果寻找不到信息，尝试使用  firecrawl mcp
- 如果寻找不到信息，再尝试其他任意可进行联网搜索的工具

## 执行流程

### 第 0 步：准备

**执行任何分析前，必须先获取本地时区的真实时间**
禁止：
- 禁止使用模型训练截止时间作为当前时间
- 禁止凭记忆判断“最新 CPI / PCE / FOMC / 就业报告”
- 禁止在未确认当前时间时判断“最近”“最新”“未来”

**确认本地工具可用**
- 具备 MemPalace MCP，如果缺失，终止流程
- 具备至上一个联网工具可用，否则终止流程。不限于 Tavily skill 、exa mcp、firecrawl mcp

---

### 第 1 步：解析用户周期

根据用户输入生成本次分析周期。

如果用户未指定周期，默认：

- analysis_start = analysis_now - 7 天
- analysis_end = analysis_now
- analysis_period_label = 最近 7 天

常见周期映射：

- 最近一周 / 最近 7 天：analysis_now 往前 7 天
- 最近两周 / 最近 14 天：analysis_now 往前 14 天
- 最近一个月 / 最近 30 天：analysis_now 往前 30 天
- 本周：本周一 00:00 到 analysis_now
- 本月：本月 1 日 00:00 到 analysis_now
- 明确日期范围：使用用户指定开始和结束日期

---

### 第 2 步：生成统一时间范围

后续所有查询必须基于以下时间范围。

已发生事件范围：

- event_start = analysis_start
- event_end = min(analysis_end, analysis_now)

历史对比范围：

- comparison_start = analysis_start - 本次周期长度
- comparison_end = analysis_start

未来事件范围：

- upcoming_start = analysis_now
- upcoming_end = analysis_now + 28 天

用途：
- event_start 到 event_end：查询本周期已经发生的信息
- comparison_start 到 comparison_end：判断相比前一周期是否变化
- upcoming_start 到 upcoming_end：查询未来 1 到 4 周重要事件

所有搜索都必须带明确时间范围，不要只搜索“最新”。

---

### 第 3 步： 各主题信息的事实采集

使用独立的 subagent 分别对如下各个方面进行分析

**本步骤中所有信息都通过存储的历史和联网搜索获取，禁止融入主观判断**

#### Employment Situation 就业形势报告

优先从 MemPalace 获取最近一次发布报告的结论，参考其中的内容时效性，进行一下次发布报告的联网补充搜索，并把最新的结论记录到 MemPalace

关注：
- 非农就业人数 NFP
- 失业率
- 平均时薪
- 劳动参与率

MemPalace topic: EmploymentSituation

输出 markdown 报告：

1. 最近一次已经发布的就业报告分析，包括
  - 发布时间
  - 就业是否过热
  - 劳动力市场是否降温
  - 是否影响降息预期
  - 对纳斯达克、美债、黄金的影响
2. 下一次报告
  - 发布时间
  - 市场最近对这次报告的预判

---

#### 通胀数据 CPI

通胀数据 CPI，由美国劳工统计局 BLS 发布 , 发布周期是每月一次

优先从 MemPalace 获取最近一次发布报告的结论，参考其中的内容时效性，进行一下次发布报告的联网补充搜索，并把最新的结论记录到 MemPalace

关注：
- Headline CPI
- Core CPI
- YoY
- MoM
- 住房和服务通胀
- 能源影响

MemPalace topic: CPI

输出 markdown 报告：
1. 最近一次已经发布的报告解读，包括
  - 发布时间
  - 通胀是否降温
  - 是否影响美联储降息预期
  - 是否影响美债收益率
  - 对纳斯达克、美债、黄金的影响
2. 下一次报告
  - 发布时间
  - 市场最近对这次报告的预判

---

#### PCE

个人消费支出价格指数 PCE，由美国商务部经济分析局 BEA 发布 , 发布周期是每月一次

优先从 MemPalace 获取最近一次发布报告的结论，参考其中的内容时效性，进行一下次发布报告的联网补充搜索，并把最新的结论记录到 MemPalace

MemPalace topic: PCE

输出 markdown 报告：
1. 最近一次已经发布的报告解读，包括
  - 发布时间
  - Core PCE 是否符合通胀回落路径
  - 是否影响美联储政策
  - 是否改变市场降息预期
  - 对纳斯达克、美债、黄金的影响
2. 下一次报告
  - 发布时间
  - 市场最近对这次报告的预判

---

#### 美联储降息会议 FOMC

美联储降息会议 FOMC，一年约 8 次左右
优先从 MemPalace 获取最近一次发布报告的结论，参考其中的内容时效性，进行一下次发布报告的联网补充搜索，并把最新的结论记录到 MemPalace

MemPalace topic: FOMC

输出 markdown 报告：
1. 最近一次已经发布的报告解读，包括
  - 发布时间
  - 利率决议
  - 声明措辞
  - 对纳斯达克、美债、黄金的影响
2. 下一次报告
  - 发布时间
  - 市场最近对这次报告的预判

---

#### 美债收益率

优先从 MemPalace 获取最近的记录，参考其中的内容时效性，联网补充搜索 event_start 到 event_end 的 10 年期和 2 年期美债收益率变化 ，并把最新的结论记录到 MemPalace

MemPalace topic: TreasuryYield

输出 markdown 报告：
- 长债和短债最近走势事实说明
- 长债和短债走势根因分析
- 长债和短债投资建议（买入或者卖出）
- 长短端收益率对纳斯达克、美债、黄金等其他市场的影响

---

#### 纳斯达克指数

优先从 MemPalace 获取最近的记录，参考其中的内容时效性，联网补充搜索 event_start 到 event_end 的纳斯达克指数变化 ，并把最新的结论记录到 MemPalace

MemPalace topic: NasdaqTrend

输出 markdown 报告：
- event_start 到 event_end 期间，指数走势事实说明
- 走势根因分析
- 市场对于未来短期的预期
- 上涨最多的 3 个行业和下跌最多的 3 个行业
- 投资建议（买入或者卖出）

---

#### 黄金

优先从 MemPalace 获取最近的记录，参考其中的内容时效性，联网补充搜索 event_start 到 event_end 的黄金走势 ，并把最新的结论记录到 MemPalace

MemPalace topic: Gold

输出 markdown 报告：
- event_start 到 event_end 走势事实说明
- 走势根因分析
- 对纳斯达克、美债等其他市场的影响
- 投资建议（买入或者卖出）

#### 能源

优先从 MemPalace 获取最近的记录，参考其中的内容时效性，联网补充搜索 event_start 到 event_end 的能源走势 ，并把最新的结论记录到 MemPalace

关注范围：
- 原油
- 天然气
- 煤矿

MemPalace topic: Energy

输出 markdown 报告：
- event_start 到 event_end 走势事实说明
- 走势根因分析
- 对纳斯达克、美债等其他市场的影响

---

#### 美股大型科技公司

优先从 MemPalace 获取最近的记录，参考其中的内容时效性，联网补充搜索公司相关资讯，并把最新的结论记录到 MemPalace

关注：
- Nvidia
- Microsoft
- Apple
- Amazon
- Meta
- Alphabet
- Tesla
- Broadcom
- AMD

MemPalace topic: TechEarnings

输出 markdown 报告：
- 每个公司下一次财报日期和市场预判（优先从MemPalace中获取，查询不到再联网补充）
- 每个公司上一次财报的核心事实、市场解读、市场反应（优先从MemPalace中获取，查询不到再联网补充）
- 每个公司 event_start 到 event_end 的重大 3 个消息
- 市场对于 AI 需求的预期、担忧、风险
- 每个公司股票投资建议（买入或者卖出）

---

### 第 4 步：整合报告

使用 productivity:caveman-cn skill ， 整合所有 subagent 输出，形成一份最终的报告

报告整合要求：
- 表达简短，突出核心结论，禁止冗长分析

### 第 5 步： 清理 MemPalace 过时记录

创建一个独立的 subagent ，完成如下清理工作：

使用 MemPalace mcp 的相关方法，清理 MemPalace 中 wing="financial" 中所有早于 ( event_start - 4 个月 ) 的历史记录，清除过时数据， 以保持 MemPalace 的时效性和相关性。

步骤

1. 通过如下方法，结合 offset 参数，进行多次调用，获取出所有早于 ( event_start - 4 个月 ) 的记录 

  mempalace_list_drawers(
      wing="financial",
      limit=100  <--- 每次获取出的数量
      offset=0   <---- 偏移位置
  )

  返回每个 drawer 的 created_at 时间戳。

2. 逐个删除上一步获取的过时记录

  mempalace_delete_drawer(drawer_id="xxx")

## 执行原则

- 必须先获取当前真实时间。
- 必须基于当前真实时间生成分析周期。
- 每个查询必须使用明确时间范围。
- 实时市场价格和未来事件必须重新确认。
- 事实、判断、建议必须分开。
- 重要结论写入 MemPalace，普通噪音不写入。
