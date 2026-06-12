# Design Spec: Installation Documentation Update

## 1. 目标 (Goals)
更新 [installation.md](file:///Users/weizhoulan/Documents/git/blueskills/docs/installation.md)，添加 `productivity` 与 `finance` 两个新增插件的安装步骤、功能介绍和使用指令。

## 2. 变更设计 (Proposed Changes)

### 2.1 新增 Productivity 插件章节
- **插件名称**：`productivity`
- **Skill**：`caveman-cn`
- **安装与加载**：
  ```text
  /plugin install productivity@blueskills
  /reload-plugins
  ```
- **核心机制**：
  - 缩减口语和废话，句式短语化标签化。
  - 保留关键因果、边界和专业术语。
- **使用示例**：
  ```text
  /productivity:caveman-cn 请帮我精简一下这段报告...
  ```

### 2.2 新增 Finance 插件章节
- **插件名称**：`finance`
- **Skill**：`global-market`
- **安装与加载**：
  ```text
  /plugin install finance@blueskills
  /reload-plugins
  ```
- **工作流**：
  - 基于当前真实时间解析查询周期。
  - 调度子 Agent 分别采集就业、通胀（CPI/PCE）、美联储会议（FOMC）、美债、股指（纳斯达克）、黄金、能源与大厂财报资讯。
  - 主 Agent 读取子 Agent 报告，并调用 `caveman-cn` 机制整合输出为精简的资产配置参考报告。
  - 清理 4 个月前的过期历史记忆。
- **全局 Debug 模式**：
  - 调用时添加“开启 debug”或 `debug=true` 时激活。
  - 采集时自动将联网搜索和 MemPalace 读写动作日志落盘至 `/tmp/global_market_<yymmddhhmmss>/`。
  - 在报告结尾汇总展示联网搜索、记忆读取及记忆写入的总次数。
- **使用示例**：
  ```text
  /finance:global-market 最近两周
  /finance:global-market 最近一周 开启 debug
  ```

## 3. 规范要求 (Quality Checks)
- 保持原文档中关于 `coding` 插件和 `卸载` 流程的完整性。
- 代码块格式一致，不夹杂无关说明。
