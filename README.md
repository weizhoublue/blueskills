
建一个 名为 news 的 plugin，其下 创建一个 gitHub-trend 的 skill。
主要完成如下工作。


第一步骤

   这个 skill 的第一个步骤是创建一个 sub agent，进行要分析项目的采集。

    第 1.1  ，通过如下每天的这个趋势榜，获取出每天的趋势项目的 github url 地址 ， 如 https://github.com/<owner>/<repo>

    （1）https://ossinsight.io/trending?period=past_24_hours   采集前 20 的项目 
    （2）https://github.com/trending   采集当日的所有项目。

    第 1.2 ，实现历史信息的过滤：基于 MemPalace MCP  存储的历史数据，对上一步选出的 url 进行 历史过滤，  如果这个项目之前已经被分析过了（在 MemPalace 中找到了），那么就把它去除。

    第 1.3，进入剩下候选名单的每个 GitHub 项目官网，  如果其 github star 数量低于 5000，就把这个项目剔除。

    第 1.4 ，得到最终的 GitHub 项目的 URL 名单， 把它们的 url 记录到 MemPalace MCP 

第二步骤

通过上一个流程之后，我们得到了一个 需要分析的 github 项目的 名单，  然后 串行使用每一个新的 subagent 对每一个 gitub 项目进行分析

分析的这个报告的格式如下。
- GitHub 仓库的地址。
- 该项目要解决的问题。
- 该项目的功能。


第三步骤
    拼接所有的项目分析的 markdown 报告。


以上所有的搜索的行为，必须优先使用 agent-browser skill , 如果失败，才允许使用其他的 MCP 或者 skill。



### MemPalace MCP 使用

MemPalace MCP 用于存储、查询和清理关键结论。

固定参数为：
- `agent_name`: "claude"
- `wing`: "github-trending"
- `room`: "diary"

MemPalace MCP 提供了多个 tool, 常见操作方法：

1. **写入记录**（仅写入重要结论，不写完整报告）：
   mempalace_diary_write(
    agent_name="claude", 
    wing="github-trending", 
    topic="...", 
    entry="[写入时间 YYYY.MM.DD.HH.MM.SS] url 地址 "
  )

2. **读取最近记录**：
   mempalace_diary_read(agent_name="claude", wing="github-trending", topic="...", last_n=30)

3. **搜索历史记录**：
   mempalace_search(query="...", wing="github-trending", room="diary")


4. **清理记录**：
   mempalace_list_drawers(wing="github-trending", limit=100, offset=0)
   mempalace_delete_drawer(drawer_id="xxx")

 