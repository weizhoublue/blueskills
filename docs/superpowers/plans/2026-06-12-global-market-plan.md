# Implementation Plan: Global Market Skill Development with Debug Capability

## Goals
1. 开发 [SKILL.md](file:///Users/weizhoulan/Documents/git/blueskills/plugins/finance/skills/global-market/SKILL.md)，实现全球市场资产配置分析。
2. 支持全局 `debug` 变量及其落盘调试记录与次数统计。

---

## Plan

### Phase 1: SKILL.md 框架与初始化
- [ ] **Task 1.1**: 在 [SKILL.md](file:///Users/weizhoulan/Documents/git/blueskills/plugins/finance/skills/global-market/SKILL.md) 顶部声明 YAML 头部（name: global-market, description...）及 `debug` 变量（默认 `false`）。
  - *Verify*: 查看文件开头是否包含 `debug: false` 设定及启用提示词说明。
- [ ] **Task 1.2**: 编写 **Step 0 准备** 指令。要求 Agent 获取当前本地时间，并在 `debug` 开启时，在 `/tmp/` 下生成唯一标识符目录 `/tmp/global_market_<yymmddhhmmss>/`。
  - *Verify*: 验证目录生成逻辑。
- [ ] **Task 1.3**: 编写 **Step 1 & 2 周期解析与时间范围统一** 指令。
  - *Verify*: 确保已发生事件范围、历史对比范围和未来事件范围定义正确。

### Phase 2: 子 Agent 采集与 Debug 日志落盘
- [ ] **Task 2.1**: 编写子 Agent 调度框架。定义 9 个主题的独立采集要求。
- [ ] **Task 2.2**: 注入 Debug 日志写入规范。在各子 Agent 指引中说明：若 `debug` 为 `true`，在每次执行 `web_search`、`memory_read`、`memory_write` 时，调用 `write_to_file` 或相关工具向 `/tmp/global_market_<yymmddhhmmss>/debug_<subagent>.json` 中追加对应动作的记录及累加计数。
  - *Verify*: 日志格式中包含 `logs` 数组和 `stats` 计数器。

### Phase 3: 报告整合、汇总与清理
- [ ] **Task 3.1**: 编写 **Step 4 整合报告** 指令。要求主 Agent 汇总子 Agent 报告（使用 caveman-cn 压缩表达）。
- [ ] **Task 3.2**: 编写数据汇总逻辑。若 `debug` 开启，主 Agent 须读取所有 `/tmp/global_market_<yymmddhhmmss>/debug_<subagent>.json` 文件，并累加各项操作总数，最后在报告底部输出调试统计。
  - *Verify*: 输出的表格或列表符合预期。
- [ ] **Task 3.3**: 编写 **Step 5 清理记录** 指令。处理 MemPalace 4 个月前的过期历史数据。

### Phase 4: 验证测试
- [ ] **Task 4.1**: 运行 `global-market`，验证无 debug 模式下的输出。
- [ ] **Task 4.2**: 开启 debug 运行，验证 `/tmp/global_market_<yymmddhhmmss>/` 目录的创建、子 Agent 调试日志的生成以及报告底部统计数字的准确性。
