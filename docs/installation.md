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

**干什么**：意图驱动的 **Code Review**（skill 名 `review`）——审 PR、本地 staged/分支 diff 或指定路径；只读、不跑测试；终稿为一份四节 Markdown（stdout）。

采用**问题驱动**：主编排根据 diff 列出要查的具体问题，探针只读相关代码段验证，减少重复读盘、缩短耗时。

**怎么用**：

```text
/plugin marketplace add weizhoublue/blueskills
/plugin install audit-code@blueskills
/reload-plugins
/audit-code:review 审一下当前 staged 改动
/audit-code:review https://github.com/OWNER/REPO/pull/42
/audit-code:review 相对 upstream/main 的 diff，忽略 vendor
```

在被审**目标仓库根目录**执行（不是 blueskills 本仓库）；PR 场景需安装并登录 `gh`。

**流程（默认 — 问题驱动）**：

1. **准备材料（Shell）**：解析审查范围 → 拉 diff → 过滤待审文件；按改动类型做 **triage**（如文档-only 可跳过性能/安全）；生成 **hunk-index**（每文件改动行、触及符号、diff 摘要）。
2. **背景 core**：`change-context-analyst` 写修改意图、模块、生产入口等（`pr_narrative` 先占位）。
3. **主编排出题（主线程）**：读 core + hunk-index + triage，写 **审查简报** `review-brief.md` 与 **出题单** `investigation-plan.json`（每题带文件/行号范围；按逻辑/非功能/架构聚成 2～3 簇）。
4. **并行验证**：
   - **probe-worker**（每簇一个）：对每题**先从生产入口沿 `entry_ref` 向下追溯到 `scope` 内代码**，再检查上下游挡板，然后判定假设；避免只看单行 diff 误报。成立则记缺陷（含调用链、根因原理、场景、可达性）。
   - **narrative-writer**：补全 §1 用的 PR 叙事（顶层调用链、修改前后**用户侧**与**软件侧**表现、方案原理）。
5. **汇编报告**：`report-assembler` 合并探针结果、去重与 gate，输出四节终稿；**§4 结论** 仅一行 `REVIEW_RESULT=mark_ignore` 或 `mark_should_fix`（存在 ≥1 条 P0–P2 则为 `mark_should_fix`）。

中间产物在临时目录 `REVIEW_TMP`；默认审完删除。调试时可设 `REVIEW_KEEP_TMP=1` 查看 `investigation-plan.json`、`findings/probes/*.json` 等。

**终稿结构**：

| 节 | 内容 |
|----|------|
| §1 修改意图分析 | 审查范围、顶层调用链、修改前/后（用户侧 + 软件侧）、方案原理 |
| §2 PR 自身缺陷 | `issue_origin=pr_introduced`；每条含位置、**根因原理**、场景、后果、建议 |
| §3 仓库残留缺陷 | `issue_origin=residual_existing`（非本 PR 造成）；格式同 §2 |
| §4 结论 | 仅 `REVIEW_RESULT=…` 一行 |

报告**不使用 Markdown 表格**。P3（如纯性能、重复代码）可列出，但不驱动 `mark_should_fix`。

**环境变量（可选）**：

| 变量 | 效果 |
|------|------|
| `REVIEW_DEPTH=full` | 加深：更多出题、可启用架构审查簇 |
| `REVIEW_KEEP_TMP=1` | 保留临时目录便于排查 |
| `AUDIT_CODE_SCRIPTS` | 指向 `audit-code-hunk-index.sh` / `audit-code-triage.sh` 所在目录（在被审仓库找不到插件脚本时使用） |

脚本默认查找顺序：`AUDIT_CODE_SCRIPTS` → 当前仓库 `plugins/audit-code/scripts` → `scripts/`。

---

## 卸载

```text
/plugin uninstall investigate-project@blueskills
/plugin marketplace remove weizhoublue/blueskills
```
