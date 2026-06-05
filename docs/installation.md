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

**输出**：完整报告打印到 **stdout**（不写仓库内中间文件）。终稿禁止 Markdown 表格；**§3 结论** 下也**只有**一行 `REVIEW_RESULT=…`。

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

1. **准备材料（Shell）**：解析审查范围 → 拉 diff → 过滤待审文件；按改动类型做 **triage**（`bugfix` 时 `enable_residual=true`）；生成 **hunk-index**（每文件改动行、触及符号、diff 摘要）。
2. **背景 core**：`change-context-analyst` 写修改意图、模块、生产入口等（`pr_narrative` 先占位）。
3. **主编排出题（主线程）**：先归纳 **根因**（`root_causes[]`），再按 `root_cause_key` 出题（一因一题、`scopes[]` 多文件，避免同根因拆成多道 must 题）；**bugfix 时强制 ≥1 道「同类残留」题**（`kind: residual`）。
4. **并行验证**：
   - **probe-worker**（每簇一个）：对每题 **(1) 从入口向下追溯调用链 (2) 与兄弟/同类文件对比 pattern 是否对齐 (3) 检查挡板**，再判定假设；避免只看单行 diff 或缺少横向对比导致误报。成立则记缺陷（含调用链、peer 对照、根因原理、场景、可达性）。
   - **narrative-writer**：补全 §1 用的 PR 叙事（顶层调用链、修改前后**用户侧**与**软件侧**表现、方案原理）。
5. **汇编报告**：`report-assembler` 合并探针结果、**根因合并**（`root_cause pass`）与 gate，输出四节终稿；**§4 结论** 仅一行 `REVIEW_RESULT=mark_ignore` 或 `mark_should_fix`（存在 ≥1 条 P0–P2 则为 `mark_should_fix`）。

**一因多表现点：** 同一根因（如 ParentReference 指针比较）在多处文件表现不同时，终稿合并为 **1 条** finding：**根因原理** 写一次，**表现点** 有序列表列出各 `path:line` 与各自后果；`REVIEW_RESULT` 按合并后条数计（非表现点数）。

中间产物在临时目录 `REVIEW_TMP`；默认审完删除。调试时可设 `REVIEW_KEEP_TMP=1` 查看 `investigation-plan.json`、`findings/probes/*.json` 等。

**终稿结构**：

| 节 | 内容 |
|----|------|
| §1 修改意图分析 | 审查范围、顶层调用链、修改前/后（用户侧 + 软件侧）、方案原理 |
| §2 PR 自身缺陷 | `issue_origin=pr_introduced`；同根因合并为一条：**根因原理** + **表现点**（多位置/多后果）或单点格式 |
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

**RTK：** 若本机有 `rtk` 命令，审查时本地 `git diff` 须加 `RTK_DISABLED=1` 或 `rtk proxy`（见 skill 阶段 2）；否则 `hunk-index` 可能统计为 0。PR 场景优先 `gh pr diff`。

---

## 卸载

```text
/plugin uninstall investigate-project@blueskills
/plugin uninstall investigate-issue@blueskills
/plugin marketplace remove weizhoublue/blueskills
```
