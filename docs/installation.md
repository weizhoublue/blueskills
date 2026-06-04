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
   - digger 对每个功能往下挖：谁用、解决什么问题、怎么工作；对关键机制（如长连接、sidecar、ext-proc）尽量写清 **为何这样设计**（`key_mechanisms`：架构角色 / 相对替代方案的好处 / 配错时怎样）；
   - integration-analyst 看功能之间怎么配合；
   - writer 把以上内容写成 `analysis-report/` 里的报告（overview 中可含「关键机制与设计动机」小节）。
3. **审计 agent 反馈**：report-quality-challenger 读写完的报告，除 **L1–L5 多层因果**（情境→后果→默认方案不足→本项目介入→用户结果）外，还会检查 **机制动机（W1–W3）**——例如不能只写「用于保持长连接」，须说明该机制在架构里干什么、不用短连接/别的做法会怎样；缺了会标 **major** 驱动 scout/digger 回灌补全（每块报告最多 5 轮质审）。

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
   - code-tracer 从配置/输入往下追函数级调用链；运行时状态（如「字段为 nil」）须有 path:line 或写入 `unverified[]`；
   - business-context-analyst 看业务上下游、和兄弟路径有什么不同，并可提供机制设计动机素材（`design_rationale`）；
   - writer 一次写好三节（问题描述、触发条件、结论）；**§1 问题描述** 中推荐含 **「关键机制为何如此设计」**（W1/W2/W3），避免只写手段复述；**§2 触发条件** 在正向清单后须有 **「故障表现」**（用户可见坏结果，素材来自分析中的 `consequences`，不设独立「问题后果」节）；正向清单仅列代码已证实状态，未能证实的场景进「未能从代码确认的前提」（R20）；**§3 结论** 仅一行 `REVIEW_RESULT=issue_true` 或 `REVIEW_RESULT=issue_false`。
3. **审计 agent 反馈**：issue-challenger 通读整份报告，看叙事、触发条件（含故障表现、不重复正向清单）、**机制动机（R18）**、**场景证据（R20）**、**结论是否仅一行且与前文一致**，驱动 writer 补全（整稿最多 3 轮；动机/场景类缺失为 **major**，3 轮后仍可 `partial` 收尾）。

终稿 stdout 的 **§3 结论** 下也**只有**一行 `REVIEW_RESULT=…`。

---

## audit-code

**干什么**：意图驱动的 **Code Review**（skill 名 `review`）——可审开放/已合入 PR、本地 staged、相对分支的 diff 或指定路径；六维并行（含 bugfix 时搜仓库同类残留）；§1 自顶层调用链叙述修改前后用户/软件表现；每条问题标注「本 PR 引入」或「仓库残留」，并从生产入口向下验证可达性。

**怎么用**：

```text
/plugin marketplace add weizhoublue/blueskills
/plugin install audit-code@blueskills
/reload-plugins
/audit-code:review 审一下当前 staged 改动
/audit-code:review https://github.com/OWNER/REPO/pull/42
/audit-code:review 相对 upstream/main 的 diff，忽略 vendor
```

在被审仓库根目录执行；PR 场景需 `gh`。只读分析，不跑测试；终稿为四节 Markdown（修改意图 / PR 缺陷 / 残留缺陷 / 结论），**不使用表格**；每条 P0–P2 缺陷含 **根因原理**（代码机制）；纯性能项为 P3；§4 仅一行 `REVIEW_RESULT=mark_ignore|mark_should_fix`。可审开放或已合入 PR、本地 staged、分支 diff 或指定路径（取代原 `audit` 插件的合入后 PR 审计场景）。

---

## 卸载

```text
/plugin uninstall investigate-project@blueskills
/plugin marketplace remove weizhoublue/blueskills
```
