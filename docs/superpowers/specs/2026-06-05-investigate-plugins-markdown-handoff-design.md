# Investigate 插件自然语言 / Markdown 流转重构设计

## 文档关系

| 文档 | 关系 |
|------|------|
| 本文 | **总设计**：两插件共用原则 + Phase 1/2 范围 |
| `2026-06-05-investigate-issue-main-agent-writing-design.md` | Phase 1 **增量修订**（主线程撰写/改稿）；与本文冲突时以该文为准 |
| `2026-06-05-investigate-issue-inline-refactor-design.md` | Phase 1 **细节已对齐**；实现以本文 §4 为准，冲突时以本文为准 |
| `plans/2026-06-05-investigate-issue-inline-refactor.md` | Phase 1 实现计划草稿；实现前应由 `writing-plans` 刷新 |

## 背景

`investigate-issue` 与 `investigate-project` 当前均采用：多份 `agents/*.md` + 临时/持久目录下的 **JSON 中间产物** + 主编排 **bash/jq** 合并或校验。人类需跨文件理解工作流；LLM 实际在上下文中传递状态，文件系统 handoff 增加维护成本且易与 audit 插件模式不一致。

**参考标杆**：`plugins/audit/skills/review/SKILL.md` — 单 SKILL、阶段用自然语言描述、sub-agent 间通过 **Markdown 粘贴** 传递上游输出，无 jq、无独立 agent 文件。

## 目标

1. 主编排与各 sub-agent 之间**仅**使用自然语言指令 + **结构化 Markdown** 传递信息。
2. **禁止** jq / bash 脚本在阶段间合并 JSON；**禁止**以 JSON 文件作为 agent 协作契约。
3. 质量规则（全局红线、R15–R20、C0–C4、B1–B5、W1–W3 等）**全部保留**，表达方式改为 SKILL 内自然语言与各阶段 Markdown 模板。
4. 维护者阅读 **一个** `SKILL.md` 即可理解全流程；删除 `agents/*.md`（角色内联到 SKILL）。

## 非目标

- 不改变 investigate-issue **终稿仅 stdout** 的对外行为。
- 不改变 investigate-project **最终交付物** 为 `overview.md` + `features/<slug>.md`（英文 slug 文件名）。
- Phase 1 **不包含** investigate-project 代码改动。

## 方案选择

| 方案 | 描述 | 结论 |
|------|------|------|
| **A** | 单 SKILL + Markdown handoff + Task sub-agent（audit 模式） | **采用** |
| B | 自然语言 SKILL + 保留 feature-plan.json 等路径键文件 | 拒绝：违背全 Markdown handoff |
| C | 拆多 SKILL 文件 | 拒绝：与 audit 不一致 |

## 跨插件原则

1. **委派 sub-agent（Task）**：每次 prompt 含：全局规则全文 + 场景变量（`issue_brief` 或 `REPORT_ROOT` 绝对路径）+ **上游 Markdown 全文粘贴**。
2. **sub-agent 返回**：对话内返回**完整 Markdown 块**（按阶段模板）；禁止「≤6 行摘要 + 文件路径」替代正文；禁止 Write 中间 JSON（Phase 2 终稿 md 除外）。
3. **主编排合并**：在上下文中综合（替代 jq）；可生成简短 `## 综合分析` 再委派下游。
4. **文件结构**：插件目录仅 `plugin.json` + 一个 `SKILL.md`；删除 `agents/`、`scripts/*`（jq 校验脚本）。
5. **质审**：评审输出为 Markdown 模板；轮次上限与 rollback 逻辑与原插件一致，仅载体变更。

## 落地顺序

| Phase | 插件 | 验收后再进行 |
|-------|------|----------------|
| **1** | `investigate-issue` | — |
| **2** | `investigate-project` | Phase 1 验收通过 |

---

## Phase 1：`investigate-issue`

### 文件变更

| 操作 | 路径 |
|------|------|
| 重写 | `plugins/investigate-issue/skills/investigate/SKILL.md` |
| 删除 | `plugins/investigate-issue/agents/*.md`（5 个） |
| 删除 | `plugins/investigate-issue/scripts/verify-investigate-issue-plugin.sh` |
| 更新 | `plugins/investigate-issue/.claude-plugin/plugin.json` → version `0.4.0` |

### SKILL.md 结构

- 元数据 + 「故障分析主编排者」角色
- 调用场景（适用 / 不适用）
- **全局规则**：分析规则 + 报告规则（原 15 条红线）
- **证据层级**：`confirmed` / `doc_declared` / `inference`（无 JSON schema）
- **工作流** 阶段 0–6：每阶段含目标、委派说明、Markdown 输出模板
- 阶段 4：评审员 / 补充员、blocking 维度、rollback 伪代码
- 阶段 5：stdout 终稿模板 + 附录 B/C

### 工作流

```
阶段0：自检 + issue_brief（不写临时目录）
阶段1：问题信息搜集 → ## 问题信息搜集结果
阶段2：并行
  2a 代码追踪 → ## 代码追踪结果
  2b 业务上下文 → ## 业务上下文分析结果
阶段3：主编排综合（上下文内 Markdown，不委派）
阶段4：撰写三节初稿 → 三节 Markdown
阶段4：整稿深化 ≤3 轮（评审 / 补充 Markdown；rollback 最多 1 次）
阶段5：组装 stdout 终稿
```

### 删除的能力

- `ISSUE_TMP`、`mktemp`、`trap`
- `scout.json` / `trace.json` / `business-context.json` / `issue-analysis.json`
- `sections/*.md`、`challenges/*.json`、`rebuttals/*.json` 中间文件
- jq 合并脚本块
- `EvidenceClaim` 等 JSON schema 定义

### 保留的能力

- 三节报告结构与 R15–R20
- C0–C4 调用链、B1–B5 业务因果、W1–W3 机制动机
- `MAX_REVIEW_ROUNDS = 3`
- rollback：第 1 轮 call_chain blocking ≥2 → 重跑 2a + 3 + 4，最多 1 次
- `REVIEW_RESULT=issue_true|false` 单行结论
- marketplace 自检（在插件/marketplace 目录运行则提示 cd）

### plugin.json

```json
{
  "name": "investigate-issue",
  "displayName": "Investigate Issue",
  "version": "0.4.0",
  "description": "针对软件项目单个故障做深度分析（单 SKILL.md，Markdown 阶段流转，无 JSON/jq 中间产物）",
  "keywords": ["issue-analysis", "code-tracing", "debugging"],
  "license": "MIT"
}
```

### Phase 1 完成标准

- [ ] `plugins/investigate-issue/` 下仅有 `plugin.json` 与 `skills/investigate/SKILL.md`
- [ ] SKILL 无 `ISSUE_TMP`、`jq`、`*.json` schema 块
- [ ] 人工试跑：能完成一次分析并 stdout 输出含 `REVIEW_RESULT=` 的报告

---

## Phase 2：`investigate-project`

### 文件变更

| 操作 | 路径 |
|------|------|
| 重写 | `plugins/investigate-project/skills/report-features/SKILL.md` |
| 删除 | `plugins/investigate-project/agents/*.md`（6 个） |
| 删除 | `plugins/investigate-project/scripts/validate-analysis-report.sh` |
| 更新 | `plugins/investigate-project/.claude-plugin/plugin.json`（version 与 description） |

### 磁盘产物（仅终稿）

```text
{REPORT_ROOT}/
├── overview.md
└── features/<slug>.md    # slug: ^[a-z0-9]+(-[a-z0-9]+)*$，≤64，清单内唯一
```

**禁止**写入：`*.json`、`quality-review/**`、`boundary-review/**`、`improvement-log/**`、`*-round-*.json`、`*-final.json`。

### 工作流概要

| 阶段 | 行为 | 对话 Markdown（示例标题） | 落盘 |
|------|------|---------------------------|------|
| 0 | REPORT_ROOT、自检、建 `features/` | — | 目录 |
| 1 | project-scout | `## 项目扫描结果` | 否 |
| 2 | boundary 初审 | `## 边界初审` | 否 |
| 3 | **主线程**人工确认循环 | 候选表 + 用户 NL；reviewer 全量重审 → review 块 | 否；`done` 后生成 `## 功能清单（终稿）`（含 slug） |
| 4 | 每 slug feature-digger + 质审 ≤5 轮 | `## 功能深挖：<name>`、`## 质审 features/<slug>（第 N 轮）` | `features/<slug>.md` |
| 5 | integration-analyst + 质审 | `## 集成能力分析` | 否（供 overview §8） |
| 6 | report-writer + overview 质审 | — | `overview.md` |

### slug

- 主编排在阶段 3 结束、`done` 后统一 `assign_slug`；`used_slugs` 在编排上下文维护。
- `merge` 保留目标 slug；`rename` 不改 slug；`split` / `add` 新 slug。
- `feature-digger` / `overview` 一级功能列表**严格**按 `## 功能清单（终稿）` 的 name 与顺序；路径用 slug。

### 人工确认（阶段 3）

- 保留：表格展示、自然语言 op（add/exclude/merge/split/rename/done）、解析确认 yes、软上限 3 轮。
- 候选与 review 状态由主编排维护为 **Markdown 表**（含 id、name、origin、decision、reason），不写 `boundary-review/*.json`。
- 可选：每轮在对话中输出 `## 边界审计（第 N 轮）` 摘要，不落盘。

### 质审未闭合项

- 第 5 轮仍有 blocking/major：**不写** `*-final.json`。
- 主编排维护「未闭合摘要」Markdown 列表；`report-writer` 写入 overview `### 质审未闭合项`。
- 若无未闭合项：overview §9 写「质量质审均在约定轮次内通过…」；**禁止**与未闭合项并存。

### improvement-log

- 不再写 `improvement-log/*.json`。
- sub-agent 可在返回 Markdown 末尾附 `### 执行备注`；`report-writer` 汇总至 overview `## 附录：流程执行与改进记录`（若有条目）。

### 保留规则

- 全局 6 条红线 + R7–R17（含 R10 质审不改功能清单、R11 五轮、R12 英文文件名、R15 用户报告禁表、R16–R17 叙事与机制动机）。
- scout 窄扫三态；reviewer 不因 origin 改 decision。
- writer 禁止增删一级功能。

### Phase 2 完成标准

- [ ] 插件目录仅 `plugin.json` + `SKILL.md`
- [ ] 试跑：人工确认 → 生成 `overview.md` + N 个 `features/<slug>.md`，无 json 中间文件
- [ ] overview 无 markdown 表格；一级功能条数与终稿清单一致

---

## 风险与缓解

| 风险 | 缓解 |
|------|------|
| 长 Markdown 撑满 context | 分阶段 Task；主编排综合时只传必要小节；digester 每次单 feature |
| 无磁盘中间产物无法断点续跑 | Phase 2 接受；必要时用户重跑 skill（YAGNI） |
| slug 冲突 | SKILL 内明确 `assign_slug` 与 `used_slugs` 算法（沿用现 v7.1 规则） |
| 质审规则遗漏 | Phase 1 从现 challenger.md 逐项迁入 SKILL；Phase 2 同理 |

## 测试策略

- **无** jq 自动化脚本；以 SKILL 自检清单 + 人工试跑为主。
- Phase 1：在真实仓库上跑一条故障描述，检查 stdout 结构与 `REVIEW_RESULT`。
- Phase 2：跑完整功能分析，检查 `analysis-report/` 仅含 md、slug 合法、overview §9 与质审结果一致。
