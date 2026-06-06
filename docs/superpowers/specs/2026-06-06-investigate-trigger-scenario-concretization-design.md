# 设计文档：investigate-issue — 触发条件场景具象化（R21）

- 日期：2026-06-06
- 状态：implemented（2026-06-06，见 plan `2026-06-06-investigate-trigger-scenario-concretization.md`）
- 父文档：[`2026-06-03-investigate-issue-plugin-design.md`](2026-06-03-investigate-issue-plugin-design.md)
- 相关 spec：
  - [`2026-06-05-investigate-issue-scenario-evidence-design.md`](2026-06-05-investigate-issue-scenario-evidence-design.md)（R20 场景证据层级）
  - [`2026-06-04-investigate-issue-drop-consequences-section-design.md`](2026-06-04-investigate-issue-drop-consequences-section-design.md)（§2 触发条件子节结构）
- 背景：R17/R20 已约束正反向逻辑结构与证据层级，但正向触发条件仍常以抽象布尔表述（「某配置为 X 且运行时状态为 Y」），缺少可评估的具体数值、配置快照、业务请求与应用层行为。读者难以判断「现实中如何踩坑」，且 agent 易用「可能 / 例如」等含糊场景填充报告。

## 1. 问题陈述

报告 `## 2. 触发条件` 中典型不足：

- 逻辑条件可读，但无数值（超时秒数、重试次数、副本数、QPS 阈值等）
- 未交代用户侧具体配置（CR spec 字段取值、env、helm values）
- 未交代业务输入（哪条 API、哪次 CLI、payload 关键字段）
- 未交代应用层在缺陷前的具体行为（哪次 reconcile、哪段 handler 路径）
- 用「高并发时可能」「例如网络不稳定」等 hedge 语冒充可触发场景

目标：**在保留 R17/R20 证据纪律的前提下**，将触发条件**场景化、量化、可评估**，杜绝含糊、不切实际的触发叙述。

## 2. Brainstorming 决策摘要

| 决策点 | 选择 |
| --- | --- |
| 量化数值来源策略 | **C — 分层表达**：逻辑条件保持 `confirmed`；具象 vignette 单独块落地 |
| 参考场景落点 | **并入** `### 触发条件（正向：须同时满足）` 子节末尾的 **参考触发场景** 块；**不**新增 `###` 子节 |
| 与 R20 关系 | R21 管「可评估具象化」；R20 管「逻辑条件是否有代码 依据」；正交 |
| `issue_false` | 参考触发场景**可选**；可写反向评估 vignette |
| 明确不做 | 无依据魔法数字；将 inference 升格为 confirmed；改动 §2 子节总数（仍为 5 个） |

## 3. 因果模型：R21 与 R17/R20 正交

| 规则 | 说明 |
| --- | --- |
| **R17** | 正/反向逻辑结构；逻辑条件须同时满足；非充分条件 |
| **R20** | 逻辑条件中的运行时状态须 `confirmed`+refs 或移出清单标 `(inference)` |
| **R21（新）** | 逻辑条件列表之后须提供 **参考触发场景** 块，将条件落地为可评估 vignette；不计入逻辑条件编号清单 |

**分层边界（硬约束）：**

1. **逻辑条件** — 仅 `confirmed`+refs 的抽象前提（config / runtime_state / code_path）
2. **参考触发场景** — 同子节内、逻辑条件之后的具象块；可含 `doc_declared` / `inference` 分项，但**不得**用 hedge 语冒充逻辑条件
3. **未能从代码确认的前提** — 仍为独立 `###` 子节（R20）；inference 场景不得进入逻辑条件列表

## 4. §2 结构与 `### 触发条件` 内部格式

### 4.1 §2 子节顺序（不变，共 5 个）

1. `### 触发条件（正向：须同时满足）` — 含逻辑条件 + 参考触发场景块（R21）
2. `### 故障表现`
3. `### 未能从代码确认的前提（不应计入触发清单）`（若有 inference）
4. `### 不触发 / 表现为正常的情形`
5. `### 完整触发调用链`

### 4.2 `### 触发条件（正向：须同时满足）` 模板

```markdown
### 触发条件（正向：须同时满足）

**逻辑条件**（仅 confirmed；R17 + R20）：
- 条件1（config）：... refs: path:line (confirmed)
- 条件2（runtime_state）：... refs: path:line (confirmed)

**参考触发场景**（可评估，不计入上方逻辑条件；R21）：
- **场景1**（来源：code_synth | user_incident | hybrid）
  - **映射条件**：条件1 + 条件2
  - **配置快照**：`key=value` …（每项 refs 或 tier）
  - **业务输入**：API/CLI/事件 + 关键参数
  - **应用层行为**：…（对齐 C0–C3 业务语言）
  - **量化观测**：…（`confirmed` / `inference` / `未能从代码量化`）
```

### 4.3 场景来源枚举

| 值 | 含义 | 数值依据 |
| --- | --- | --- |
| `code_synth` | 代码默认值 + 分支约束合成的可触发示例 | 配置/阈值须 `confirmed`+refs |
| `user_incident` | 复述 issue_brief 事故 | 用户口述标 `doc_declared`；与代码不符须点明 |
| `hybrid` | 用户现象 + 代码补全缺失字段 | 分项标 tier，禁止整段升格 `confirmed` |

### 4.4 `issue_true` vs `issue_false`

| 结论 | 参考触发场景 |
| --- | --- |
| `issue_true` | **必填** ≥1 条正向 vignette |
| `issue_false` | **可选**；若写，须标明 `场景类型：反向`（典型评估下为何不触发） |

## 5. Upstream 改造

### 5.1 阶段 2a `code-tracer`

在现有 **触发条件** 输出块中，逻辑条件列表之后增加：

```markdown
**参考触发场景素材**（供阶段 3 撰写；R21）：
- 场景1（来源：code_synth | …）
  - 配置快照：… refs
  - 业务输入：（若代码可推断入口则填，否则记「未能从代码确认」）
  - 应用层行为：…（对齐 C0–C3）
  - 量化观测：…（从常量/默认值/校验边界提取；无法则标注）
```

**工作步骤（新增）：**

1. 从缺陷落点反向收集：相关配置键默认值、常量、校验 `min/max`、枚举字面量（Grep/Read）。
2. 从 C0 入口推断典型业务输入（api/cli/config apply）；无法确认 → 写入「未能确认的主张」，场景中标 `inference`。
3. 合成 ≥1 条 `code_synth` 场景；若 issue_brief 含用户配置/请求，增 `user_incident` 或 `hybrid` 场景。
4. **禁止**在逻辑条件或参考场景中使用无 refs 的魔法数字。

### 5.2 阶段 2b `business-context-analyst`

在 **业务流** / **B1 情境** 中补充：

- 用户声称的配置取值、操作步骤、输入请求（前提核实 P* 引用）
- `user_incident` 场景素材：配置快照、业务输入、可观察量化现象（区分 `doc_declared` vs `confirmed`）

**规则：**

- 用户主张 `missing` / `doc_only` 的能力**不得**写入参考场景作为已发生事实
- B4 对齐 2a C3 时，应用层行为描述须与调用链一致

## 6. 阶段 3 主编排撰写

撰写 `## 2. 触发条件` 时：

1. 逻辑条件仅取自 2a `confirmed` 项（R20）
2. 参考触发场景合并 2a 素材 + 2b 用户情境；`issue_true` 时必填
3. 每条参考场景必须映射到逻辑条件编号
4. 量化观测：优先代码字面量；用户口述标 tier；都算不出则写「未能从代码量化」
5. hedge 语（「可能」「例如」「某些情况下」）**禁止**出现在逻辑条件；若出现在参考场景须标 `(inference)` 并说明依据

## 7. 阶段 4 评审（`issue-challenger` 等价逻辑）

在现有 R17/R20 扫描基础上，增加 **R21** 维度：

### 7.1 blocking

| 项 | 说明 |
| --- | --- |
| 缺参考触发场景块 | `issue_true` 且 `### 触发条件` 下无 **参考触发场景** |
| 魔法数字 | 参考场景含具体数值无 refs 且未标 `(inference)` |
| hedge 冒充逻辑条件 | 逻辑条件列表含「可能/例如/某些情况下」未标 inference |

### 7.2 major

| 项 | 说明 |
| --- | --- |
| 参考场景缺字段 | 缺配置快照 / 业务输入 / 应用层行为 / 量化观测任一项 |
| 未映射逻辑条件 | 参考场景未写「映射条件：条件 N」 |
| 场景不可评估 | 读者仍无法用该 vignette 判断是否会触发 |
| 与 R20 交叉 | 参考场景将 `missing`/`doc_only` 能力写作已发生事实 |

### 7.3 resolution（与 R18/R20 一致）

- 仅有 R21 类 `major`、无 blocking → `needs_enrichment`
- 第 3 轮结束仍有 R21 `major` → `partial`
- **禁止**因参考场景缺量化 alone 判 `issue_false`

### 7.4 读者检验（追加）

遮住 path:line 后，读者能否用参考场景中的配置 + 输入 + 数值复述「如何踩坑」？不能 → R21 `major`。

## 8. `SKILL.md` 改动清单

| 位置 | 改动 |
| --- | --- |
| 全局规则 | 新增 **R21 场景具象化** 条文 |
| 2a 输出模板 | `触发条件` 块增加 `参考触发场景素材` |
| 2a 阶段 B | 工作步骤增加量化常量提取、场景合成 |
| 2b 输出模板 | 业务流/B1 强调用户配置与输入素材 |
| 阶段 3 §2 必含要素 | `### 触发条件` 说明含逻辑条件 + 参考触发场景块 |
| 阶段 4 评审 | 增加 R21 blocking/major 项 |
| 阶段 5 stdout 模板 | `## 2. 触发条件` 注释更新 |

**全局规则 R21 正文（拟粘贴）：**

```markdown
- **场景具象化（R21）**：`### 触发条件（正向：须同时满足）` 在**逻辑条件**列表之后须提供 **参考触发场景** 块（`issue_true` 时必填 ≥1 条）。每条须含：场景来源（code_synth / user_incident / hybrid）、映射逻辑条件编号、配置快照、业务输入、应用层行为、量化观测点。数值须为代码字面量/校验边界（confirmed+refs）或 issue_brief 陈述（doc_declared/inference）；无法量化写「未能从代码量化」；禁止无依据魔法数字。参考场景不计入逻辑条件清单；禁止用 hedge 语冒充逻辑条件。
```

## 9. 正反例

### 9.1 好例子（逻辑条件 + 参考场景）

**逻辑条件：**

- 条件1（config）：`spec.strategy=Recreate` refs: types.go:88 (confirmed)
- 条件2（runtime）：滚动更新触发旧 Pod 删除 refs: controller.go:210 (confirmed)

**参考触发场景：**

- 场景1（来源：code_synth）
  - 映射条件：条件1 + 条件2
  - 配置快照：`replicas: 3`，`strategy: Recreate`，`terminationGracePeriodSeconds: 30` (confirmed) refs: types.go:42,88
  - 业务输入：`kubectl apply` 更新 Deployment，仅修改 `spec.template.spec.containers[0].image` (inference) — 未能从代码确认用户是否仅改 image
  - 应用层行为：controller 按 Recreate 策略删除旧 RS 下 3 个 Pod，新 Pod 尚未 Ready (confirmed) refs: controller.go:210-225
  - 量化观测：终止宽限 30s 内可用副本可能降为 0 (inference) — 未能从代码精确计算时间线

### 9.2 坏例子（应被 R21/R20 拦截）

- 逻辑条件写：「高并发时可能触发」— hedge 冒充逻辑条件
- 参考场景写：「timeout 设得很短」— 无数值、无 refs
- 参考场景写：「用户执行某操作后」— 无具体 API/CLI/参数

## 10. 验收标准

| # | 标准 |
| --- | --- |
| 1 | `issue_true` 终稿 `### 触发条件` 含 **逻辑条件** + **参考触发场景** 两块 |
| 2 | 参考场景每条含映射条件、配置快照、业务输入、应用层行为、量化观测 |
| 3 | 逻辑条件列表无 hedge 语；inference 场景在「未能从代码确认的前提」或参考场景分项标 tier |
| 4 | 评审对缺参考场景报 R21 blocking；对缺量化/缺字段报 major |
| 5 | 不破坏 R17/R20/R18：逻辑条件仍仅 confirmed；动机 W 层规则不变 |
| 6 | §2 仍为 5 个 `###` 子节，不新增独立「参考场景」子节 |

## 11. 非目标

- 要求每个 open question 再跑一轮 code-tracer（除非 rollback 已触发）
- 自动脚本替代评审对 vignette 质量的判断
- investigate-project / audit 插件同步（可后续单独 spec）
- 在参考场景中编造用户未提供且代码无法佐证的具体生产流量数值

## 12. Rollout

1. 更新 `plugins/investigate-issue/skills/investigate/SKILL.md`（R21 + 各阶段模板与评审项）
2. 本 spec 标记 `implemented` 于对应 PR/提交说明
3. 不修改 stdout 三节标题；不增加 §2 `###` 子节数量
