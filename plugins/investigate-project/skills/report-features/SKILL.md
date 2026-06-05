---
description: 对软件项目进行网站的功能分析，包含了功能的应用场景、原理、优点、缺点等多个方面的解读，生成一份面向用户的网站分析报告
---

你是本次 **report-features** 流程的**主编排者**。接收用户请求后，顺序委派各阶段 sub-agent（Task），在对话内以 **Markdown 全文粘贴** 传递上游产出；最终在 `REPORT_ROOT` 下仅写入 `overview.md` 与 `features/<slug>.md`。禁止修改被分析仓库代码；禁止运行测试；禁止 jq、禁止以 JSON 文件作为 agent 协作契约。

## 调用场景

**适用于如下场景**
- **软件功能解读** 对软件项目进行网站的功能分析，包含了功能的应用场景、原理、优点、缺点等多个方面的解读，生成一份面向用户的网站分析报告

**不适用于如下场景**
- 用户没有明确要求调用本 skill

---

## REPORT_ROOT 与磁盘产物（强约束）

**根目录变量 `REPORT_ROOT`**（默认 = 被分析项目根目录下的 `analysis-report`）：

```text
REPORT_ROOT = <当前工作目录绝对路径>/analysis-report
```

- 相对路径 `./analysis-report/` **仅在与阶段 0 确认的 cwd 一致时**有效；子 agent 可能 cwd 不同，故**禁止**只传相对路径。
- 用户**显式**指定其它目录时，`REPORT_ROOT` = 该绝对路径（须为目录，且在本机可写）。
- 主线程与各 sub-agent **禁止**写入：`../analysis-report`、插件/marketplace 仓库内的 `analysis-report`、`/tmp`、用户主目录、以及任何不以 `REPORT_ROOT/` 为前缀的路径。
- **仅允许落盘**：
  - `{REPORT_ROOT}/overview.md`
  - `{REPORT_ROOT}/features/<slug>.md`（`slug` 匹配 `^[a-z0-9]+(-[a-z0-9]+)*$`，长度 ≤ 64，清单内唯一）
- **禁止落盘**：`*.json`、`quality-review/**`、`boundary-review/**`、`improvement-log/**`、校验脚本产物、任何中间 JSON。

**`slug` 与 `name` 分工**：

- `name`：业务展示名（可为中文），用于报告正文标题、overview 一级功能列表、集成说明的 `owner_feature`。
- `slug`：仅用于磁盘路径；须匹配 `^[a-z0-9]+(-[a-z0-9]+)*$`，长度 ≤ 64，在终稿清单内**唯一**。
- 主线程在阶段 3 用户 `done` 后统一 `assign_slug`；`rename` **只改** `name`，**不改** `slug`；`merge` 目标项**保留**其 `slug`；`split` / `add` 产生的新项**新分配** `slug`。

---

## 全局约束（必须在每次委派 sub-agent 时在 prompt 里复述）

**Prompt 硬性红线（6 条）：**

1. 禁止把代码目录结构直接等同于业务功能结构。
2. 必须优先从用户入口、文档场景、配置能力、API/CLI/UI/SDK/CRD 暴露面来识别业务功能。
3. 禁止在缺乏证据时编造性能结论、优缺点或集成能力。
4. 无法确认时必须明确写「未能从文档和代码中确认」，不得猜测、不得留空。
5. 当文档与代码冲突时，以当前代码实现和用户可见入口为准，并标记冲突（按冲突处理优先级）。
6. 不要输出函数级调用链。工作原理应描述为：用户流程、系统抽象流程、状态变化、外部交互。

**统一排除（路径/目录级）：**

- 测试目录：`test/`、`tests/`、`__tests__/`、`spec/`
- `.github/`（CI 工作流）
- 依赖/第三方：`vendor/`、`vendors/`、`node_modules/`、`third_party/`
- README 要求：排除 CICD、镜像打包/发布相关

**业务功能判定规则**（语义级）：

- 符合其一即视为业务功能：用户可直接感知或操作；文档面向用户介绍该能力；CLI/API/UI/SDK/CRD 暴露该能力；解决用户使用项目时的实际问题；影响用户最终结果、体验、成本、性能或安全。
- 通常不视为业务功能：CI/CD、镜像构建、release 脚本、单元/集成测试、内部工具脚本、代码生成流程、lint/format/依赖管理、benchmark（除非项目本身面向性能测试用户）。

**冲突处理优先级：**

1. 当前代码实现 > 文档描述
2. 默认分支代码 > 历史文档
3. 配置 schema / API 定义 > 教程文档
4. 用户可见入口 > 内部未暴露实现
5. 代码有实现但无入口 → 标记「内部能力或未暴露能力」
6. 文档有功能但代码无实现 → 标记「文档声明但未确认实现」

**扩展红线（R7–R17，委派相关 sub-agent 时按需复述）：**

- **R7（reviewer 中立判定）**：`feature-boundary-reviewer` 不得因 `origin` 非 `scout-initial` 而调整 `decision`；`prev_reviews` 仅供稳定性比对，**不作为判定来源**。
- **R8（scout 窄扫三态）**：`project-scout (mode: targeted)` 必须返回 `found` / `duplicate` / `not_found`；预算耗尽未命中**必须** `not_found`。
- **R9（叙事 tier 诚实）**：禁止把无 refs 的推断标为 `confirmed`；`industry_context` 不得进入 `problems_solved` / `scenarios` 主列表（仅 `industry_context_notes`）。
- **R10（质审不改清单）**：`report-quality-challenger` 不得修改功能终稿清单的条数、`name`、`slug`、顺序。
- **R11（质审轮次）**：每个质审 target 的 challenger 调用 **≤ 5 轮**（`MAX_QUALITY_ROUNDS = 5`）；第 5 轮后若仍有 blocking/major，主编排维护 `unclosed_quality_items[]` 并**继续**流水线（不阻塞出报告）；**禁止**写 `*-final.json`。
- **R12（英文报告文件名）**：`overview.md` 与 `features/<slug>.md` 的文件名必须为英文 kebab-case（`slug`）；禁止以中文 `name` 作为磁盘文件名。
- **R13（产物根目录）**：终稿 md **必须** 写在 `REPORT_ROOT/` 下；委派 prompt **必须** 附带 `REPORT_ROOT` 的**绝对路径**；禁止写到其它目录；**禁止**写入除 `overview.md` 与 `features/<slug>.md` 外的业务/中间文件。
- **R14（执行备注免质审）**：sub-agent 可在返回 Markdown 末尾附 `### 执行备注`；`report-quality-challenger` **不得**对 `### 执行备注` 提 blocking/major，**不得**要求删除或「证实」这些记录。主编排汇总至 overview `## 附录：流程执行与改进记录`（若有条目）。
- **R15（用户报告禁表）**：`overview.md` 与 `features/<slug>.md` **禁止** markdown 表格（`| ... |`）；用 `###`、有序/无序列表、分组 bullet。编排文档内部表格不受限。
- **R16（叙事深度）**：`scenarios` / `problems_solved` 须多层因果（L1 情境 → L2 后果 → [L3] → L4 本项目机制 → L5 用户结果）+ 专名首现解释；禁止为过关仅加长字数。
- **R17（机制动机）**：叙事中的关键机制须可回答 W1–W3；质审 `mechanism_motivation` 为 **major**（非 blocking）。禁止「用于保持连接」类同义反复代替 W2。本轮不强制 `integrations` W。

---

## 主编排上下文（内存维护，不写文件）

| 变量 | 含义 |
| --- | --- |
| `project_overview_md` | 阶段 1b 通过后，scout Part 1「### 项目概览」全文（叙事 Markdown，供 writer §1–§6） |
| `candidates_md` | 候选一级功能表（Markdown，含 id/name/summary/exposure/paths/evidence） |
| `reviews_md` | 边界 reviewer 最新一轮校准结果（Markdown） |
| `feature_list_final_md` | 用户 `done` 后生成的 `## 功能清单（终稿）`（name/slug/exposure/paths 等，顺序即 overview §7 顺序） |
| `integrations_md` | 阶段 5 通过后 integration-analyst 返回的 `## 集成能力分析` 全文 |
| `unclosed_quality_items[]` | 任质审 target 第 5 轮仍有 blocking/major 时，人类可读 bullet 列表（供 overview §9） |
| `execution_notes[]` | 从各 sub-agent 返回的 `### 执行备注` 收集的条目 |
| `used_slugs` | `assign_slug` 已占用集合 |

**每次委派 sub-agent 时，prompt 必须含：**

1. 上文「全局约束」全文（6 条红线 + 统一排除 + 业务功能判定 + 冲突优先级 + 相关 R7–R17）
2. 一行 `REPORT_ROOT: <绝对路径>`
3. 本阶段所需的**上游 Markdown 全文**（按阶段粘贴，禁止「见上文」或路径代替正文）

---

## 大项目 Read 预算（主线程判定）

阶段 1 开始前在 `ANALYZE_CWD` 检测（满足**任一**即 `large_project: true`）：

- `Glob` 得 `**/*crd*.yaml` 或 `**/charts/**` 命中 ≥ 3
- 存在 `docs/architecture*` 或 `docs/design*`
- 存在 `go.mod` 且同时存在 `**/deploy/**` 或 `**/config/crd/**`

| 模式 | project-scout Read 上限 | feature-digger Read 上限 |
| --- | --- | --- |
| 默认 | ≤ 35 | ≤ 35 |
| `large_project: true` | ≤ 45 | ≤ 45 |

委派 `project-scout` / `feature-digger` 时 prompt 须带：`read_budget: <N>`。

---

## assign_slug（自然语言算法）

在阶段 3 用户 `done` 后，对每条 `decision == keep` 的候选（尚无 `slug` 或 split/add 新项）执行：

1. 从 `name` 提取英文关键词；若无英文，从 `code_paths` / `doc_paths` 最后一段路径名取 ASCII 词。
2. 转 **kebab-case**（小写、连字符、仅 `[a-z0-9-]`）。
3. 若与 `used_slugs` 冲突，追加后缀 `-2`、`-3`… 直至唯一。
4. 将结果加入 `used_slugs`。
5. `merge` 保留**目标 id** 已有 `slug`；被合并项 slug 废弃；`rename` 不改 slug。

---

## 工作流（严格顺序执行）

**MAX_QUALITY_ROUNDS = 5**（每个质审 target 独立计数）。

### 阶段 0：锁定 REPORT_ROOT（**必须最先执行**）

在委派任何 sub-agent **之前**，主线程完成：

```text
1. 执行 pwd 得到 ANALYZE_CWD（被分析项目根目录的绝对路径）
   - 若 cwd 在本 marketplace 克隆内（例如存在 plugins/investigate-project/.claude-plugin/plugin.json
     或根目录 .claude-plugin/marketplace.json 且无待分析项目特征），
     提示用户先 cd 到待分析项目再运行本 skill，不要继续写产物
2. REPORT_ROOT ← ANALYZE_CWD + "/analysis-report"（或用户指定的绝对路径）
3. mkdir -p REPORT_ROOT/features
   （禁止创建 boundary-review、quality-review、improvement-log 等目录）
4. 向用户确认一行：「分析报告将写入：<REPORT_ROOT>」
5. 初始化 used_slugs ← ∅；unclosed_quality_items ← []；execution_notes ← []
```

**自检**：阶段 4 写入前，主线程应能列出 `REPORT_ROOT`；若不存在则回到步骤 3。

---

### 阶段 1：勘察（project-scout）

委派 sub-agent（扮演**项目勘察员**），附 `read_budget` 与全局规则。

**工作内容（摘要）**：识别主语言/平台/架构；Glob/Grep 建索引后定向 Read；每候选 3~8 条证据样本；产出 Part 1 项目概览（叙事 Markdown）+ Part 2 候选表。

**返回格式（对话内完整 Markdown，禁止写盘）：**

```markdown
## 项目扫描结果

### 项目概览

#### 1. 基本信息
- 主开发语言：
- 运行平台：
- 总体职责：（≤ 60 字）

#### 2. 应用场景
（≥ 2 条 NarrativeBlock，每条独立 ### 小节，结构见下「NarrativeBlock」）

#### 3. 解决的问题与痛点
（≥ 3 条 NarrativeBlock；复杂主题建议含 L3）

#### 4. 行业背景补充（无项目内证据）
（可选；`industry_context` tier；全项目 ≤ 3 条；不得混入 §2/§3 主列表）

#### 5. 优点
- 要点：（证据: doc|code|both；refs: …）

#### 6. 缺点与限制
- 要点：（证据: …）

#### 7. 架构摘要
（≤ 200 字抽象描述，无函数名）

#### 8. 功能模块与协作关系
##### 8.1 架构组件层
（≥ 2 层；每层 name / responsibility / collaborates_with / evidence_tier / refs）
##### 8.2 一级业务功能协作
（≥ 1 条；与 Part 2 候选 name 对齐）
##### 8.3 组件与功能映射
（≥ 1 条 mapping）

---

### 候选一级功能清单

| id | name | summary | exposure | code_paths | doc_paths | 证据摘要 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | … | ≤30字 | cli,api | … | … | path:kind:snippet… |

（证据样本 3~8 条/候选；origin 均为 scout-initial）
```

**NarrativeBlock（每条 scenario / problem 须含）**：

- `### <title>`
- 连贯 `narrative`（由 L1→L2→[L3]→L4→L5 合成）
- **若无本能力：** `contrast`（≤ 80 字）
- **本项目如何缓解（抽象）：** `mechanism_at_a_glance`
- **证据层级:** confirmed | doc_declared；**refs:** 逗号分隔路径
- 可选 **背景：**、**术语：** term — glossary
- 可选 **关键机制与设计动机**（W1 角色 / W2 为何不用替代 / W3 失灵后果）

接收返回后：将 `### 项目概览` 存入 `project_overview_md`；候选表存入 `candidates_md`。

---

#### 阶段 1a：project-overview 预检（主线程，**必须**）

进入 1b **之前**，主线程核对 `project_overview_md`（**禁止**调用校验脚本）：

- `#### 2. 应用场景` 下 NarrativeBlock 条数 ≥ 2
- `#### 3. 解决的问题与痛点` 条数 ≥ 3
- `#### 8. 功能模块与协作关系` 下架构层 ≥ 2
- 每条 problem 能从 narrative / contrast / mechanism 还原 ≥3 层因果（L1/L2/L4/L5 或含 L3）
- 不满足 → 回灌 project-scout **仅修订 Part 1**（`### 项目概览`），保持 Part 2 候选表不变；重跑 1a（不计入质审 round）

---

#### 阶段 1b：project-overview 质审（report-quality-challenger）

```text
target ← "project-overview"
round ← 1
prior_issues_md ← null
while round ≤ MAX_QUALITY_ROUNDS:
    委派 report-quality-challenger
    若 status == passed: break
    若 round == MAX_QUALITY_ROUNDS 且仍有 blocking/major:
        将未闭合项追加到 unclosed_quality_items[]（人类可读 bullet）
        break
    prior_issues_md ← 本轮 ## 质审 project-overview（第N轮）中的 blocking/major 清单
    回灌 project-scout：仅修订 ### 项目概览；Part 2 不变
    更新 project_overview_md
    round ← round + 1
```

---

### 阶段 2：功能边界校准 — 初审（feature-boundary-reviewer）

委派 sub-agent（扮演**功能边界校准员**），输入：`candidates_md` 全文；**不重读全仓**。

**返回格式：**

```markdown
## 边界初审

### 校准结果

| id | decision | reason | evidence |
| --- | --- | --- | --- |
| 1 | keep | ≤120字 | path… |
| 2 | exclude | 属于 CI/CD… | … |

（decision: keep | exclude | merge | split；merge 须 merge_target + merge_with_ids；split 须 split_into）

### 给用户的呈现表

| id | name | summary | decision | reason |
| --- | --- | --- | --- | --- |
```

存入 `reviews_md`。

---

### 阶段 3：人工确认（主线程多轮循环）

软上限 3 轮提示（不强制终止）；用户 `done` / `ok` / 空回车退出。**禁止**写 `boundary-review/*.json`；可选在对话输出 `## 边界审计（第 N 轮）` 摘要。

#### 3.1 每轮展示与提示词

````text
========== 候选一级功能清单（第 N 轮） ==========
（上方为候选表格，含 id | name | summary | review.decision | review.reason）

请用中文自然语言描述你的修改意见，例如：

- 把 2、5、7 剔除
- 把第 3 项和第 4 项合并成「配置管理」
- 把第 6 项拆成「证书签发」和「证书轮换」
- 第 1 项改名为「网络策略管理」
- 加一个关于「IPv6 双栈」的功能分析
- 输入 done / ok / 直接回车 表示清单确认完成，进入深挖阶段

我会把指令归一化后展示一次让你确认；某条听不懂会反问你具体指哪一项。
````

#### 3.2 内部动作集

| op | 必填字段 | 等价口语示例 |
| --- | --- | --- |
| `add` | `name`（必填），`hints`（可选） | "加一个 xxx" |
| `exclude` | `ids` | "去掉 2 5 7" |
| `split` | `id`, `into` (字符串数组) | "把第 6 拆成 A、B" |
| `merge` | `ids` (≥2), `name` | "把 3 和 4 合成 配置管理" |
| `rename` | `id`, `name` | "把 1 改名为 xxx" |
| `done` | — | "ok" / "done" / 空回车 |

#### 3.3 origin 字段语义

| 取值 | 何时产生 |
| --- | --- |
| `scout-initial` | 阶段 1 |
| `user-added@round-N` | 第 N 轮 add 且 scout 窄扫 `found` |
| `user-split-from-<id>@round-N` | 第 N 轮 split 子项 |

`merge` / `rename` / `exclude` **不改变**目标项 `origin`（merge 目标 id = min(ids)，合并 paths/samples/exposure，目标 slug 不变）。

#### 3.4 reviewer 重审

每轮用户确认 `yes` 后：同轮顺序 **add → split → merge → rename → exclude**；再委派 feature-boundary-reviewer，传入完整 `candidates` Markdown + 可选 `prev_reviews` Markdown（仅稳定性偏好，**禁止**作为判定来源）。

#### 3.5 用户 `done` 后

1. 校验 keep 数量 > 0，否则拒绝 done。
2. 对每条 keep 执行 `assign_slug`，生成：

```markdown
## 功能清单（终稿）

1. **<name>**
   - slug: `<slug>`
   - exposure: cli, api, …
   - code_paths: …
   - doc_paths: …
   - origin: scout-initial | user-added@…
   - notes: （可选）

2. **<name>**
   …
```

存入 `feature_list_final_md`。非 keep 项不进终稿；向用户提示已忽略 N 项。

#### 3.6 解析与反问红线

1. 归一化后**必须复述确认**；仅 `yes` 执行；`修改这一条` / `重输` 不消耗轮次。
2. 编号越界 / 名字不唯一 / 动作不清晰 → 反问。
3. 禁止善意脑补（吐槽不等于 exclude）。
4. 解析连续失败 ≥ 3 次 → 兜底贴回 §3.1。

#### 3.7 失败 / 边界场景

| 场景 | 处理 |
| --- | --- |
| add 但 scout `not_found` | 跳过该 add；记入 execution_notes |
| add 但 scout `duplicate` | 提示与第 N 项重复 |
| done 时 keep == 0 | 拒绝，提示至少保留一项 |
| round >= 3 | 软警告 |
| reviewer 对用户 add 项 exclude | 下轮高亮 reason |

---

### 阶段 4：深挖（feature-digger × N）

对 `feature_list_final_md` 中**每一条**委派 feature-digger（可并行；各附相同 `read_budget`）。

**输入**：该条 feature 的 Markdown 块（name/slug/exposure/paths/evidence）+ `feature_list_final_md` 全文（禁止传 boundary 审计内容）。

**sub-agent 磁盘 Write 唯一允许**：`{REPORT_ROOT}/features/<slug>.md`

**返回格式（对话内）：**

```markdown
## 功能深挖：<name>

- slug: `<slug>`
- md: {REPORT_ROOT}/features/<slug>.md
- confidence: high|medium|low
- conflicts: <数量>
- unconfirmed: <数量>

### 执行备注
（可选；执行摩擦、预算耗尽等；质审不得据此 blocking/major）
```

**features/<slug>.md 结构模板（sub-agent 必须按此 Write）：**

```markdown
# <功能名>

## 启用方式 / 用户入口
- …

## 应用场景
### <scenario.title>
<narrative>
（证据: <tier>；refs: …）
（若无本能力：…）
（本项目如何缓解（抽象）：…）

## 解决的问题与痛点
### <problem.title>
…

#### 行业背景补充（无项目内证据）
（仅当有 industry_context_notes 时）

## 优点
## 缺点
## 抽象工作原理（5 维）
1. 启用方式
2. 主要处理阶段
3. 状态变化
4. 外部交互
5. 最终结果

## 性能表现
## 二级功能
### <sub.name>
<narrative>
与一级功能边界：…

## 依据来源标注
## 冲突与未确认事项
```

**每 feature 质审循环：**

```text
target ← "features/<slug>"
round ← 1
while round ≤ MAX_QUALITY_ROUNDS:
    委派 report-quality-challenger（Read 该 slug 的 .md）
    若 passed: break
    若 round == MAX_QUALITY_ROUNDS 且有 blocking/major:
        追加 unclosed_quality_items[]
        break
    回灌 feature-digger：仅修订 features/<slug>.md
    round ← round + 1
```

全部 feature 完成后进入阶段 5。

---

### 阶段 5：集成分析（integration-analyst）

委派 sub-agent，输入：`feature_list_final_md` + 主编排 **Read** 全部 `{REPORT_ROOT}/features/*.md` 后粘贴摘要或全文 + 全局规则。

**禁止**写 `integrations.json`；**禁止**新增不在终稿清单中的 `owner_feature`。

**返回格式（对话内，不落盘）：**

```markdown
## 集成能力分析

### 项目级公共集成（project-level）
- **<target>**（<kind>）
  - 谁在用：…
  - 缺它会怎样：…
  - 对接方式：…
  - 证据：refs…

### 与一级功能绑定的集成（feature-level）
- **<owner_feature>**（须命中终稿 name）
  - **<target>**（<kind>）：…

### 排除的内部依赖（internal-dependency，不进用户列表）
- …

### 未能确认
- …
```

存入 `integrations_md`。

#### 阶段 5b：integrations 质审

```text
target ← "integrations"
round ← 1
while round ≤ MAX_QUALITY_ROUNDS:
    委派 report-quality-challenger
    若 passed: break
    若 round == MAX_QUALITY_ROUNDS 且有 blocking/major: 追加 unclosed_quality_items[]; break
    回灌 integration-analyst：修订 ## 集成能力分析 Markdown
    更新 integrations_md
    round ← round + 1
```

---

### 阶段 6：汇总（report-writer）

主编排 **Read** 全部 `{REPORT_ROOT}/features/*.md`，与下列内容一并粘贴委派 report-writer：

- `project_overview_md`（全文）
- `feature_list_final_md`（全文）
- `integrations_md`（全文）
- `unclosed_quality_items[]`（若有，格式化为 Markdown 列表）
- `execution_notes[]`（若有）

**sub-agent 仅 Write**：`{REPORT_ROOT}/overview.md`

**约束**：不得新增/删除/合并/拆分/重命名一级功能；§7 名称与顺序**严格**来自 `feature_list_final_md`；缺失 feature md → 摘要写「未能从中间产物确认」；全文禁止表格（R15）。

**overview.md 模板：**

```markdown
# 项目总体分析报告

> 本报告由 investigate-project 插件自动生成，所有结论均基于代码与文档双源印证。
> 当文档与代码冲突时，以代码实现与用户可见入口为准；无法确认的事项已显式标注。

## 1. 基本信息
- 主开发语言：
- 运行平台：
- 总体职责：

## 2. 应用场景
（按 project_overview_md §2 NarrativeBlock 渲染，### 小节）

## 3. 解决的问题与痛点
（同上；含行业背景补充子节若有）

## 4. 优点
## 5. 缺点与限制
## 6. 功能模块与协作关系
### 6.1 架构组件层
### 6.2 一级业务功能协作
### 6.3 组件与功能映射

## 7. 一级功能（共 N 项）
> 名称与顺序严格来自功能清单终稿，本节不引入新功能、不重命名。

1. **<name>** — <摘要>
   - 详情：[features/<slug>.md](./features/<slug>.md)
…

## 8. 集成能力
### 8.1 项目级公共集成（project-level）
### 8.2 与一级功能绑定的集成（feature-level）

## 9. 综合视角说明
- 文档与代码对照要点
- 冲突与未确认（业务语言）
### 质审未闭合项
（仅当 unclosed_quality_items 非空时出现；逐条人类可读摘要）
（若 unclosed 为空：写一句「质量质审均在约定轮次内通过，无未闭合的 blocking/major 项。」且**禁止**与本节「未闭合项」子标题并存）

## 附录：流程执行与改进记录
（仅当 execution_notes 非空；按来源分组；质审不核实）
```

---

#### 阶段 6b：overview-md 质审

```text
target ← "overview-md"
round ← 1
while round ≤ MAX_QUALITY_ROUNDS:
    委派 report-quality-challenger（Read overview.md + 对照 project_overview_md 是否缩水）
    若 passed: break
    若 round == MAX_QUALITY_ROUNDS 且有 blocking/major: 追加 unclosed_quality_items[]; break
    回灌 report-writer：仅修订 overview.md
    round ← round + 1
```

---

### 阶段 6 出口门禁（主线程自查，**必须**）

**禁止**运行 `validate-analysis-report.sh` 或任何 jq 校验。

- [ ] `{REPORT_ROOT}/overview.md` 存在且全文无 markdown 表格（`| ... |`）
- [ ] 含 `## 6. 功能模块与协作关系`；`## 2` 至少 2 个 `###`；`## 3` 至少 3 个 `###`（与 project_overview 条数一致或标注未能确认）
- [ ] `## 7` 一级功能条数 == `feature_list_final_md` 条数；名称与顺序一致
- [ ] §9：若 `unclosed_quality_items` 非空，须有 `### 质审未闭合项` 且**禁止**写「均在约定轮次内通过」；若为空，仅允许通过句、**禁止**未闭合子节
- [ ] `REPORT_ROOT` 下除 `overview.md` 与 `features/*.md` 外无业务/中间产物（无 json、无 quality-review 等目录）
- [ ] 每个 `features/<slug>.md` 的 slug 合法且唯一

---

## Sub-agent 角色与输出模板

### project-scout（项目勘察员）

**工具**：Read, Grep, Glob, Bash（仅 ls/stat/wc）

**Read 预算**：见「大项目 Read 预算」；Grep ≤20（限定路径）；Glob ≤10。

**窄扫 mode: targeted**（阶段 3 add 时）：仅搜 query.name/hints；返回三态之一（对话 Markdown，不写文件）：

```markdown
### 窄扫结果
- result: found | duplicate | not_found
- （found 时附候选字段与 3~6 条 evidence_samples）
- （duplicate 时附 duplicate_of: <id> 与 reason）
- （not_found 时附 tried_keywords、searched_paths、reason）
```

**质审回灌**：仅修订 `### 项目概览`；Part 2 候选表不变；注明 `revision_round: N`。

---

### feature-boundary-reviewer（功能边界校准员）

**补证预算**：Read ≤5（每次 ≤100 行）；Grep ≤5；Glob ≤3。

**红线 7**：不因 `origin != scout-initial` 改变 decision。

**重审**：`prev_reviews` 仅稳定性偏好；对用户已 split/merge/rename 的二次建议，`reason` 以「reviewer 二次建议」开头。

---

### feature-digger（功能深挖员）

**禁止** Read `boundary-review/`；**禁止** Write 除 `{REPORT_ROOT}/features/<slug>.md` 外的文件。

**五维原理**：activation_flow / processing_stages / state_changes / external_interactions / user_outcomes（阶段粒度，无函数名）。

**叙事**：scenarios ≥2；problems_solved ≥2；sub_features ≥1；industry_context_notes ≤2。

**质审回灌**：仅修订该 slug 的 `.md`；禁止改 slug。

---

### integration-analyst（集成分析员）

**三分类**：feature-level（必填 owner_feature = 终稿 name）/ project-level / internal-dependency（不进用户列表）。

**Grep** ≤15；**Read** ≤20。

---

### report-quality-challenger（报告质量质审员）

**禁止** Read/Write 功能终稿清单以外的「改清单」行为；**禁止**对 `### 执行备注` blocking/major。

**多层因果**：缺 L2 或 L4 → blocking；缺 L1 或 L5 → major；复杂主题缺 L3 → major。

**机制动机 W1–W3**：缺 W2 单独 major（非 blocking）；须填 `mechanism_motivation_audit` 式说明于返回 Markdown。

**质审返回模板（每轮，对话内完整返回，禁止写 quality-review 文件）：**

```markdown
## 质审 <target>（第 N 轮）

**结论**: passed | issues_found

**检查摘要**
- scenarios_count: …
- problems_solved_count: …
- （其它 metrics 一行一条）

### 问题清单
- **[blocking|major|informational]** `<field_path>` — <question>
  - 建议：<suggestion>（须指明补 L1–L5 / 术语 / ref / W1–W3，禁止仅「写长一点」）
  - 维度：causal_layers | terminology | mechanism_motivation | tier_refs | …

### 因果层审计
- `<field_path>`：已有层 [1,2,4]；缺失 [3,5]

### 机制动机审计
- 机制：…；已有 [W1]；缺失 [W2,W3]

### 术语审计
- 术语 EPP @ problems_solved[0]：未解释
```

**target 取值**：`project-overview` | `features/<slug>` | `integrations` | `overview-md`

第 5 轮仍有 blocking/major 时：在返回中列出 `### 未闭合项摘要`（主编排抄入 `unclosed_quality_items[]`）；**禁止** Write `*-final.json`。

---

### report-writer（报告撰写员）

**只读**主编排粘贴的 Markdown + `{REPORT_ROOT}/features/*.md`（由主编排 Read 后粘贴或授权 Read 仅该目录）。

**§9 规则**：

| 情况 | §9 写法 |
| --- | --- |
| `unclosed_quality_items` 为空 | 一句「质量质审均在约定轮次内通过…」；**不要** `### 质审未闭合项` |
| 非空 | **必须** `### 质审未闭合项` + 人类可读列表；**禁止**同时写「全部通过」 |

**附录**：合并 `execution_notes`；无则省略整章。

---

## 完成后

向用户简要汇报：

- 一级功能总数（与 `feature_list_final_md` 一致）
- 写入产物路径（`REPORT_ROOT` 绝对路径）
- 冲突 / 未确认项总数（从各 feature md 与 integrations 归纳）
- 质审未闭合项（若有；**不得**在存在未闭合时报「全部通过」）

### 完成后抽检（「三问」）

从报告中各抽 1 项，用业务语言自问（两题答不上则提示报告深度可能不足）：

1. **痛点**：随机 1 条 `problems_solved` — 遮住项目名，能否说清「没有该项目时会怎样」？
2. **证据**：随机 1 条 `refs` — 能否对应 narrative 里的哪一句主张？
3. **边界**：随机 1 个一级功能 — 能否说清与相邻功能的差异（不靠目录名）？
