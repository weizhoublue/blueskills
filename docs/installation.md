# 安装


## investigate-project

**干什么**：读懂整个项目有哪些业务功能，写出一份面向用户的功能分析报告。

**插件形态（v0.3.0+）**：仅一个 skill 文件 `report-features`（`SKILL.md`），主编排按阶段 **委派 Task sub-agent**；各阶段在对话里用 **Markdown 全文** 传递上游结果（prompt 内粘贴），**不写**中间 `*.json`、`quality-review/`、`boundary-review/` 等文件。维护者只需读一份 SKILL 即可理解全流程（与 `audit` 插件同模式）。

**怎么用**：

```text
/plugin marketplace add weizhoublue/blueskills
/plugin install investigate-project@blueskills
/reload-plugins
/investigate-project:report-features
```

在被分析**项目根目录**执行（不要在 blueskills marketplace 仓库里跑）；skill 会创建并确认 `REPORT_ROOT`（默认 `<项目根>/analysis-report`）。

**流程**：

1. **读仓库（project-scout）**：Glob/Grep 建索引后定向读取，产出 `## 项目扫描结果`（项目概览叙事 + 候选一级功能表，均在 Markdown 中返回）。
2. **项目概览质审（≤5 轮）**：质审 sub-agent 检查 **L1–L5 多层因果** 与 **机制动机 W1–W3**；未通过则回灌 scout 只修订概览部分；第 5 轮仍有 blocking/major 时，主编排记入「未闭合项」列表（**不落盘** `*-final.json`）。
3. **功能边界（reviewer）**：对候选表做 `keep/exclude/merge/split` 初审；随后在**主线程**多轮与你确认清单（自然语言改项、`done` 结束）；`done` 后为每条保留项分配英文 `slug`，形成 `## 功能清单（终稿）`（仅存在于编排上下文，不写 `feature-plan.json`）。
4. **按功能深挖（feature-digger × N）**：每个 slug 委派一次 sub-agent，**只写入** `{REPORT_ROOT}/features/<slug>.md`；对关键机制写清 W1/W2/W3；每功能质审 ≤5 轮，修订同一 md 文件。
5. **集成分析（integration-analyst）**：返回 `## 集成能力分析` Markdown，供 overview §8 使用（不写 `integrations.json`）。
6. **汇总（report-writer）**：读取已落盘的各 `features/<slug>.md`，结合主编排持有的概览/清单/集成/未闭合项 Markdown，**只写入** `{REPORT_ROOT}/overview.md`；overview 成稿再质审 ≤5 轮。

**磁盘产物（仅此两类）**：

```text
analysis-report/
├── overview.md              # 项目总体报告
└── features/<slug>.md       # 各一级功能报告（slug 为英文 kebab-case）
```

报告**不是** stdout。overview 禁止 Markdown 表格；§9 根据是否有质审未闭合项二选一表述（有未闭合项时须有 `### 质审未闭合项`，且不得写「全部通过」）。

---

## investigate-issue

**干什么**：针对**某一个具体问题**（bug、异常行为等）做深度分析，解释业务上怎么回事、怎么触发、有什么后果。

**插件形态（v0.5.1+）**：仅一个 skill 文件 `investigate`（`SKILL.md`）；搜集与分析委派 sub-agent；**初稿由主编排在阶段 3 撰写**；深化阶段仍委派评审与补充；阶段间 Markdown 在对话中传递（无 `ISSUE_TMP`、无 `jq`、无独立 `agents/*.md`）。

**怎么用**：

```text
/plugin marketplace add weizhoublue/blueskills
/plugin install investigate-issue@blueskills
/reload-plugins
/investigate-issue:investigate 你的问题描述
```

在被分析**项目根目录**执行；输入应包含可分析的现象或组件线索（若只说「帮我分析」未指明问题，skill 会只问 1 个澄清问题）。

**流程**：

1. **问题信息搜集**：根据 `issue_brief` 在仓库中建索引，返回 `## 问题信息搜集结果`（候选模块、入口线索等）。
2. **并行分析**：
   - **代码追踪**：函数级调用链 C0–C4，每步 `path:line` + 业务含义；触发条件正向/反向；未能证实的运行时主张列入「未能确认的主张」；
   - **业务上下文**：B1–B5 业务因果、兄弟分支对比、可选机制动机 W1–W3。
3. **综合并撰写初稿（主编排，不委派）**：合并搜集与并行分析结果，写出 `## 1. 问题描述`、`## 2. 触发条件`、`## 3. 结论`（**仅一行** `REVIEW_RESULT=issue_true|false`）。
4. **整稿深化（≤3 轮）**：质审 sub-agent（R16–R20）；`needs_enrichment` 时由**补充** sub-agent 按缺失清单输出完整三节；call_chain 类 blocking 过多时可 **回滚重追踪 1 次** 后主编排重做步骤 3。
5. **组装终稿（主编排）**：按模板将三节报告输出到 **stdout**。

**输出**：完整报告打印到 **stdout**（不写仓库内中间文件）。终稿禁止 Markdown 表格；**§3 结论** 下也**只有**一行 `REVIEW_RESULT=…`。

---

## audit

**干什么**：对 PR、commit、patch 或 diff 做**静态代码缺陷审计**（skill 名 `review`）——只报有证据、有触发条件、与本次变更相关的真实缺陷；只读、不跑测试；终稿输出到 **stdout**。

**插件形态（v0.7.0+）**：仅一个 skill 文件 `review`（`SKILL.md`）；阶段 2 **并行**三个 specialist sub-agent（变更代码本身 / 周边影响 / 目的与兼容性），由主编排合并候选缺陷并做覆盖说明门禁；阶段间 Markdown 在对话中传递（无 `REVIEW_TMP`、无 `jq`、无 shell 脚本、无独立 `agents/*.md`）。

**怎么用**：

```text
/plugin marketplace add weizhoublue/blueskills
/plugin install audit@blueskills
/reload-plugins
/audit:review 审一下当前 staged 改动
/audit:review https://github.com/OWNER/REPO/pull/42
/audit:review <commit-hash>
```

在被审**目标仓库根目录**执行（不是 blueskills 本仓库）；PR 场景建议安装并登录 `gh`。输入支持 PR URL、commit hash、patch、diff 正文或本地路径；若只说「帮我审一下」未指明范围，skill 只问 1 个澄清问题。

**流程**：

1. **变更意图分析**：根据 diff 与 PR/commit 元数据返回 `## 变更意图分析`（变更性质、声称目标、涉及文件等）；本阶段不输出缺陷。
2. **代码缺陷扫描（并行）**：
   - **2a 变更代码本身**：语言/运行时缺陷、安全、边界条件（须 Read 变更所在完整函数）；
   - **2b 变更周边影响**：上下游调用链、兄弟/同类对比；bugfix 时搜索同类残留；
   - **2c 目的与兼容性**：变更意图是否实现、API/配置/schema/升级与回滚兼容性。
   每个 agent 须附 **`## 扫描覆盖说明`**（即使零缺陷）；主编排合并去重并做覆盖门禁后交给质检。
3. **缺陷质检**：逐条反证核查，删除证据不足项；不得因「其他 scanner 未报」而删除成立项。
4. **报告拼装（主编排）**：按 P0→P1→P2 排列，合并同根因，输出终稿。

**输出**：完整报告打印到 **stdout**（不写仓库内中间文件）。**结论** 节仅一行：

- 存在 ≥1 条 P0–P2 缺陷：`REVIEW_RESULT=review_mark_should_fix`
- 否则：`REVIEW_RESULT=review_mark_ignore`

终稿含 `## 代码变更背景`、`## 缺陷`（每条含性质、等级、证据、触发条件、解读、后果、反证、建议）、`## 最终结论`。忽略 P3；不报风格/命名/缺测试类噪音。

---

## 卸载

```text
/plugin uninstall investigate-project@blueskills
/plugin uninstall investigate-issue@blueskills
/plugin uninstall audit@blueskills
/plugin marketplace remove weizhoublue/blueskills
```
