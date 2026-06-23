# Design Spec: GitHub Trend Skill Optimization (Markdown-based Protocol)

## 1. 背景与目标

当前 `github-trend` 技能中，步骤之间的状态与文件同步极其复杂，且在 Step 2（项目分析阶段）会为每个候选项目分别启动一个子 Agent，导致大量子 Agent 被频繁创建，消耗大且流转混乱。

本设计旨在：
1. **减少子 Agent 的创建数量**：Step 2 项目分析由**单个**分析子 Agent 串行循环处理所有候选项目。
2. **极简化状态与文件同步**：彻底废弃所有零散的中间 JSON 文件，以 Markdown 格式作为 Agent 之间的通信协议。
3. **支持报告保存路径提取与 Stdout 抑制**：主 Agent 自动解析用户输入以确定报告写入路径（未提及则默认写入 `TMP_DIR/report.md`），且 stdout 仅输出一行保存位置提示，不直接打印报告内容。

---

## 2. 系统架构与数据流向

### 2.1 角色定义
*   **主 Agent (Parent Agent)**：整体流程调度中心。
*   **采集子 Agent (Collection Sub-agent)**：Step 1 启动一次，负责爬取 GitHub Trending 榜单并结合 MemPalace 过滤历史记录，生成 `collect_result.md` 文本。
*   **分析子 Agent (Analysis Sub-agent)**：Step 2 启动一次，传入候选 URL 列表，串行循环分析所有项目并过滤低 Star 项目，生成 `analyze_result.md` 文本。

### 2.2 数据流向图
```mermaid
graph TD
    Main[主 Agent] -->|1. 启动| CollectAgent[采集子 Agent]
    CollectAgent -->|2. 返回 collect_result.md 文本| Main
    Main -->|3. 提取待分析项目, 启动| AnalyzeAgent[分析子 Agent]
    AnalyzeAgent -->|4. 返回 analyze_result.md 文本| Main
    Main -->|5. 写入 MemPalace 并生成 mempalace_result.md 文本| Mem[MemPalace]
    Main -->|6. 拼接并写入目标文件, stdout 提示保存路径| Out[目标 Markdown 报告]
```

### 2.3 物理文件落盘与最终报告路径
最终报告的写入目标路径按以下规则解析（若指定相对路径，基于当前工作区根目录解析为绝对路径）：
*   **用户指定路径**：主 Agent 解析用户输入（如“保存到...”、“写入...”）以提取输出路径。若该路径是目录，自动生成 `github_trending_report_YYYYMMDD.md` 文件名。
*   **默认路径**：若用户未指定，默认写入 `TMP_DIR/report.md`。无论 `debug` 为何值，若用户未指定报告路径，主 Agent 均会创建 `TMP_DIR` 目录并写入该文件。
*   **物理文件落盘 (仅 `debug=true` 时)**：
    除了最终生成的报告文件外，各步骤的中间 Markdown 文本仍需写入以下路径：
    *   `TMP_DIR/collect_result.md`
    *   `TMP_DIR/analyze_result.md`
    *   `TMP_DIR/analyze/<owner>__<repo>.md` （分析成功的单个项目报告）
    *   `TMP_DIR/mempalace_result.md`
    *   若用户指定了其他输出路径，仍会在 `TMP_DIR/report.md` 保存一份报告副本供调试。

---

## 3. Markdown 协议规范

各步骤输出的 Markdown 采用固定二级标题进行划分，便于使用正则表达式进行数据提取。各步骤的“困难与统计”采用自由格式，不再强求结构化指标。

### 3.1 `collect_result.md` 协议格式
```markdown
## 待分析项目
- https://github.com/owner1/repo1
- https://github.com/owner2/repo2

## 剔除已分析项目
- https://github.com/owner3/repo3

## 采集困难与统计
（自由格式，记录网页加载、MemPalace 连通性、调用次数等）
```

### 3.2 `analyze_result.md` 协议格式
```markdown
## 分析报告

### owner1/repo1
**仓库地址**: https://github.com/owner1/repo1
**github star 数量**: 12000

#### 适用场景
（详细说明它项目适用的实际问题场景，描述必须大于 100 字）

#### 要解决的问题
（详细说明其要解决的技术问题，且必须大于 100 字）

#### 功能
（详细说明该项目的各个功能，每个功能文字至少大于 50 字）

### owner2/repo2
...

## 分析失败项目

### owner3/repo3
- **仓库地址**: https://github.com/owner3/repo3
- **github star 数量**: 6000
- **分析失败**: 页面加载超时

## 剔除 star 不足项目
- https://github.com/owner4/repo4

## 分析困难与统计
（自由格式，记录 star 数解析异常、超时重试、浏览器调用次数等）
```

### 3.3 `mempalace_result.md` 协议格式
```markdown
## 写入摘要
成功写入 MemPalace 的项目：
- https://github.com/owner1/repo1

## 写入困难与统计
（自由格式，记录成功/失败/跳过数以及任何错误）
```

---

## 4. 详细执行流程与逻辑

### 4.1 Step 0：准备与初始化
1. **获取时间与路径解析**：读取本地系统当前真实时间作为生成时间。解析用户提示词，提取并解析报告的保存路径（若无则默认为 `TMP_DIR/report.md`）。
2. **连通性校验**：确认 `/usr/sbin/agent-browser` 与 MemPalace 可用。
3. **Debug 与临时目录配置**：解析 `debug` 指令参数（默认 `true`）。无论 `debug` 为何值，若用户未指定报告路径，主 Agent 均创建 `TMP_DIR` 目录及 `TMP_DIR/analyze/` 子目录；若 `debug=true`，则必定创建 `TMP_DIR` 目录及子目录。

### 4.2 Step 1：采集子 Agent
1. 主 Agent 启动采集子 Agent，任务为：
   * 访问 `https://github.com/trending` 抓取项目 URL，并规范化为 `https://github.com/<owner>/<repo>`。
   * 调用 `mempalace_search` 对 URL 进行历史去重。
   * 格式化并返回 `collect_result.md` 的文本内容。
2. 主 Agent 接收到返回内容。若 `debug=true`，落盘至 `TMP_DIR/collect_result.md`。

### 4.3 Step 2：分析子 Agent
1. 主 Agent 通过正则（匹配 `## 待分析项目` 块中的 `- https://...` 链接）从采集文本中提取待分析 URL 列表。
2. 若列表为空，跳过 Step 2 和 Step 3，直接跳转至 Step 4 输出「今日无新项目」报告。
3. 否则，主 Agent 启动分析子 Agent，在 Prompt 中传入待分析 URL 列表、以及 `debug` 状态与 `TMP_DIR` 路径，任务为：
   * **串行循环**处理每个项目。
   * 优先使用 `/usr/sbin/agent-browser` 提取项目主页的 Star 数。
   * **Star 门禁**：若 Star < 5000，归类到 `## 剔除 star 不足项目`；若 Star ≥ 5000，则提取 README 信息生成项目报告。若解析失败或处理异常，归类至 `## 分析失败项目`。
   * 若 `debug=true`，将分析成功的单个项目报告单独写入 `TMP_DIR/analyze/<owner>__<repo>.md`。
   * 格式化并返回 `analyze_result.md` 文本内容。
4. 主 Agent 接收到返回内容。若 `debug=true`，落盘至 `TMP_DIR/analyze_result.md`。

### 4.4 Step 3：写入历史数据库 (MemPalace)
1. 主 Agent 使用正则从 `analyze_result.md` 的 `## 分析报告` 段落中提取分析成功的项目 URL 列表。
2. 主 Agent 串行调用 `mempalace_diary_write` 写入已分析记录（不委派子 Agent）。
3. 主 Agent 格式化并生成 `mempalace_result.md` 文本。若 `debug=true`，落盘至 `TMP_DIR/mempalace_result.md`。

### 4.5 Step 4：整合输出报告
1. 主 Agent 原样提取各步骤 Markdown 内容，拼接生成最终报告。
2. **保存报告**：主 Agent 将最终报告写入已解析的目标路径。若 `debug=true` 且用户指定了其他输出路径，主 Agent 仍需在 `TMP_DIR/report.md` 存一份副本。
3. **Stdout 提示**：主 Agent **禁止**将报告正文打印到 stdout，仅在 stdout 打印一行提示：“报告已保存至：<绝对路径>”。

---

## 5. 异常处理规范

| 异常情况 | 应对策略 |
| :--- | :--- |
| `agent-browser` 不可用 | 终止运行，并报错提示安装全路径服务。 |
| MemPalace 不可用 (Step 1) | 终止运行（因为无法进行去重过滤）。 |
| MemPalace 不可用 (Step 3) | 记录警告困难，跳过写入步骤，继续执行 Step 4。 |
| 待分析项目列表为空 | 跳过 Step 2/3。在 Step 4 日报头部显示“今日无新项目”，并继续拼接收集阶段的“剔除已分析项目”与“采集困难与统计”，将最终报告保存至目标路径，并在 stdout 输出保存成功提示。 |
| 分析子 Agent 异常中断 | 主 Agent 捕获异常，将已完成部分的 Markdown 进行拼接，未完成的项目标记为分析失败。 |
