# 安装


## investigate-project

**干什么**：读懂整个项目有哪些业务功能，写出一份功能分析报告。

**怎么用**：

```text
/plugin marketplace add weizhoublue/blueskills
/plugin install investigate-project@blueskills
/reload-plugins
/investigate-project:report-features
```

**流程**：

1. **读仓库**：扫描 README、文档和代码入口，摸清项目结构和用户能用到哪些能力。
2. **几个 agent 分工**：
   - scout 先把项目里可能的功能点列出来；
   - reviewer 帮你校准「什么算一个功能、什么不算」；
   - digger 对每个功能往下挖：谁用、解决什么问题、怎么工作；
   - integration-analyst 看功能之间怎么配合；
   - writer 把以上内容写成 `analysis-report/` 里的报告。
3. **审计 agent 反馈**：report-quality-challenger 读写完的报告，指出哪里因果不清楚、哪里缺背景，驱动 writer 改到能读懂为止。

报告落在当前目录的 `analysis-report/`，不是 stdout。

---

## investigate-issue

**干什么**：针对**某一个具体问题**（bug、异常行为等）做深度分析，解释业务上怎么回事、怎么触发、有什么后果。

**怎么用**：

```text
/plugin marketplace add weizhoublue/blueskills
/plugin install investigate-issue@blueskills
/reload-plugins
/investigate-issue:investigate 你的问题描述
```

**流程**：

1. **读仓库**：根据你写的问题描述，在代码和文档里找相关模块、配置入口和调用路径。
2. **几个 agent 分工**：
   - scout 收集和问题相关的线索；
   - code-tracer 从配置/输入往下追函数级调用链；
   - business-context-analyst 看业务上下游、和兄弟路径有什么不同；
   - writer 一次写好四节；**结论文件仅一行** `REVIEW_RESULT=issue_true` 或 `REVIEW_RESULT=issue_false`，无任何解释。
3. **审计 agent 反馈**：issue-challenger 通读整份报告，看叙事、触发条件、**结论是否仅一行且与前文一致**，驱动 writer 补全（整稿最多 3 轮）。

终稿 stdout 的 **§4 结论** 下也**只有**一行 `REVIEW_RESULT=…`。

---

## audit

**干什么**：审计一条**已经合进主分支**的 GitHub PR，看改动里有没有风险、缺陷或设计问题。

**怎么用**：

```text
/plugin marketplace add weizhoublue/blueskills
/plugin install audit@blueskills
/reload-plugins
/audit:audit-merged-pr https://github.com/OWNER/REPO/pull/123
```

需要本机已登录 `gh`，并在该仓库的缺省分支（如 `main`）下执行。

**流程**：

1. **读仓库**：用 `gh` 拉 PR 的 diff 和说明，对照当前仓库代码做静态分析（不跑测试）。
2. **几个 agent 分工**：
   - pr-intent-analyst 先理解作者想改什么、有没有在 PR 里说明的设计取舍；
   - 四个方向的 analyst 分别从逻辑、并发、安全等维度扫 effective diff；
   - 必要时 similar-defect-scout 找仓库里类似写法是否也有问题；
   - report-writer 把确认的 finding 整理成审计报告。
3. **审计 agent 反馈**：每条 finding 会经 peer-challenger、audit-challenger 多轮质询——原分析 agent 可以辩驳，challenger 决定 finding 是否成立、严重级别是否合适，避免误报后再出终稿。

终稿只输出到 stdout。

---


## 卸载

```text
/plugin uninstall investigate-project@blueskills
/plugin marketplace remove weizhoublue/blueskills
```
