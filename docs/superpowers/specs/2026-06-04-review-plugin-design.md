# 设计文档：blueskills marketplace — `review` 插件（通用 Code Review）

- 日期：2026-06-04
- 状态：已审阅（2026-06-04）
- 前置：头脑风暴确认（与现有 `audit` 插件并存，不替代）
- 参考实践：
  - [agency-agents engineering-code-reviewer](https://github.com/msitarzewski/agency-agents/blob/main/engineering/engineering-code-reviewer.md)
  - [ECC code-reviewer](https://github.com/affaan-m/ECC/blob/main/agents/code-reviewer.md)
  - [addyosmani code-reviewer agent](https://github.com/addyosmani/agent-skills/blob/main/agents/code-reviewer.md)
  - [addyosmani code-review-and-quality SKILL](https://github.com/addyosmani/agent-skills/blob/main/skills/code-review-and-quality/SKILL.md)
- 运行环境：**Claude Code**（`/plugin install audit-code@blueskills`，`/audit-code:review`）

## 1. 目标与动机

现有 `audit` 插件面向**已合入 PR** 的事后审计，通过 dedupe、peer 质询（≤2 轮）、audit 质询（≤3 轮）等机制**强力压误报**。实践中出现**召回不足**（漏报多）。

新插件 `review` 的目标：

1. **意图驱动**：用户用自然语言指定审查对象（线上 PR、开放 PR、本地 staged/分支/range/路径等）；含糊时**只问一个**澄清问题。
2. **变更背景调研（六维前）**：先产出 `change-context.json`（修改意图、模块定位、`pr_narrative` 顶层调用链 + 用户/软件前后表现），再进入六维并行。
3. **六维并行发现**：addyosmani 四轴（正确性、架构、安全、性能）+ **影响面（impact）** + **残留同类缺陷（residual，仅 bugfix）**；**不含**可读性维（风格/嵌套/命名类噪音由 merger `out_of_scope_style` 拒收）。
4. **全局 finding 属性**：每条问题必须标注 `issue_origin`：`pr_introduced`（本 PR 修改引入）| `residual_existing`（仓库内同类残留，非本 PR 引入）。
5. **顶层入口可达性（六维硬要求）**：任何 finding 须从软件**生产主路径入口**向下回溯调用链，证明问题**真的可能在生产中发生**；入口以下已被 guard/类型/框架挡住的，不得按 P0/P1 上报。
6. **v1 高召回、轻收口**：发现 → `finding-merger`（去重 + Gate + 定级）→ 报告；**不做**多轮辩驳。
7. **结论契约**：报告**最后一节**仅一行 `REVIEW_RESULT=mark_ignore|mark_should_fix`；≥1 条 P0–P2 → `mark_should_fix`。

## 2. 与 `audit` 的关系

| 维度 | `audit` | `review`（本插件） |
|------|---------|-------------------|
| 典型输入 | 已合入 PR URL | PR（开放/已合入）+ 本地 git + 路径 + 用户提示 |
| 编排重心 | 压误报（辩驳、后续已修淘汰） | 偏高召回（六维广扫 + merger gate） |
| 质询 | peer + audit 多轮 | v1 无；`REVIEW_ENABLE_CHALLENGE=1` 预留 v2 |
| 结论 | `fix_mark_*` + P0–P2 进终稿 | 同左；P3 可列但不驱动 `REVIEW_RESULT` |
| 共存 | 保留 | 新 marketplace 条目，不删除 audit |

## 3. 命名与仓库布局

```text
blueskills/
├── .claude-plugin/marketplace.json    # 增加 review 插件条目
└── plugins/audit-code/
    ├── .claude-plugin/plugin.json     # name: audit-code
    ├── skills/review/SKILL.md         # /audit-code:review
    └── agents/
        ├── change-context-analyst.md   # 六维前：变更意图 + 模块定位 + 项目内功能角色
        ├── correctness-analyst.md
        ├── architecture-analyst.md
        ├── security-analyst.md
        ├── performance-analyst.md
        ├── impact-analyst.md
        ├── residual-defect-scout.md   # 第 6 维：仅 bugfix，搜仓库同类残留
        ├── finding-merger.md
        └── report-writer.md
```

| 层级 | 标识 |
|------|------|
| Plugin | `audit-code` |
| Skill | `review` |
| 调用示例 | `/audit-code:review` + 用户自然语言（PR 链接、审 staged、相对 main 等） |

## 4. 前置条件

- 用户 **`cd` 到被审项目仓库根**（非本 marketplace 克隆）。
- **PR 场景**：已登录 `gh`；可选 GitHub MCP 兜底。
- **只读**：禁止修改被审仓库源码；**禁止运行测试**（Verification Story 仅建议作者如何验证）。
- **终稿**：审计报告 **仅 stdout**；中间 JSON 只写 `$REVIEW_TMP`。

## 5. 审查范围解析（意图驱动）

主编排读取用户整句提示，解析并写入 `$REVIEW_TMP/scope.json`：

| 用户信号 | `scope.type` | 附加字段 |
|----------|--------------|----------|
| `https://github.com/.../pull/N` | `pr` | `pr_url` |
| staged / 暂存区 | `git` | `mode: staged` |
| 相对 main / upstream | `git` | `mode: branch`, `base` |
| commit / `A..B` | `git` | `mode: range`, `range` |
| 路径列表 | `paths` | `paths[]` |
| 含糊 | — | 向用户**只问 1 句**后写入 |

**默认 ignore 建议**（用户未反对则应用，写入 `scope.ignore_patterns`）：

- `docs/**`, `**/*.md`（除非用户要求审文档）
- `vendor/`, `third_party/`, `node_modules/`
- lock 文件、`*.pb.go`, `zz_generated`, `mock_`, `generated/`
- `**/*_test.go`, `test/`, `tests/`, `__tests__/`, `spec/`（除非 `include_tests: true`）

用户可说「也要审测试」「不要忽略 examples」等覆盖默认。

### 5.1 PR diff 获取

- **开放 PR**：`gh pr diff` + `gh pr view --json ...`
- **已合入 PR**：优先本地 merge commit / `git diff parent..C`（与 audit 阶段 2 类似）；失败则 `gh pr diff`
- **仓库绑定**：PR 场景下校验至少一条 `remote.*.url` 归一化后与 PR 的 `owner/repo` 一致（逻辑同 audit 0b）

### 5.2 本地 diff 获取（Shell only）

| mode | 命令倾向 |
|------|----------|
| staged | `git diff --staged` |
| branch | `git diff base...HEAD` |
| range | `git diff A..B` |
| paths | 对路径 `git diff` 或 Read 全文（无 git 时仅 Read 指定路径） |

产出：`raw-diff.patch`、`changed-files.json`、`review-files.json`（最终待审路径列表）。

## 6. 主编排阶段

| 阶段 | 执行者 | 产出 |
|------|--------|------|
| 0 | 主编排 Shell | marketplace 自检、git 仓库校验 |
| 1 | 主编排 | `scope.json`（含糊则先问用户） |
| 2 | Shell | `raw-diff.patch`, `changed-files.json` |
| 2b | Shell | `review-files.json` |
| 3 | Shell（PR 时） | `pr-snapshot.json`（title/body/comments 摘要，可选） |
| **3b** | **`change-context-analyst`** | **`change-context.json`**（意图 + 模块 + 定位 + `change_kind`） |
| 4 | **六维并行** | `findings/*.json`（**必读** `change-context.json`；第 6 维见 §8.5） |
| 5 | `finding-merger` | `findings/merged.json`, `findings/rejected.json` |
| 6 | `report-writer` | Markdown → stdout |
| 清理 | trap | 默认 `rm -rf $REVIEW_TMP`；`REVIEW_KEEP_TMP=1` 保留 |

**阶段 3 / 3b 分工：**

- **阶段 3**：主编排 Shell/`gh` 拉 PR 元数据写入 `pr-snapshot.json`（非 PR 则跳过）；不做深度代码调研。
- **阶段 3b**：`change-context-analyst` 产出六维共用的**审查背景板**（含 `pr_narrative`）；其中 `change_kind` 决定是否启用第 6 维（residual）。

**输出策略**（同 audit）：对话内仅阶段摘要；禁止粘贴 findings JSON 全文；sub-agent 返回 ≤6 行。

## 7. change-context-analyst（六维前背景调研）

### 7.0 职责

在六维并行**之前**，回答三类问题（写入 `change-context.json`，供全部 analyst 只读引用）：

1. **修改意图**：这次改动想解决什么？用户提示 + PR 描述 + commit message 是否一致？
2. **涉及模块**：动到了哪些包/目录/子系统？模块之间依赖关系如何？
3. **项目内定位**：该能力在整体产品/架构里扮演什么角色？主路径还是边缘？与哪些既有功能相邻？

### 7.0.1 输入

| 来源 | 用途 |
|------|------|
| 用户首条提示 | `user_stated_goal` |
| `$REVIEW_TMP/scope.json` | 审查范围 |
| `$REVIEW_TMP/review-files.json` | 待审文件列表 |
| `$REVIEW_TMP/raw-diff.patch` 或 diff 摘要 | 改了什么（不贴全文进 prompt） |
| `$REVIEW_TMP/pr-snapshot.json`（若有） | PR title/body/review 摘要 |
| 被审仓库 | README、顶层目录、与改动相关的**未改**入口文件（如 main、router、API 注册处） |

### 7.0.2 输出 schema（`change-context.json`）

```json
{
  "version": 1,
  "stated_intent": "一句话：改动要达成什么",
  "user_stated_goal": "来自用户提示的原文摘要",
  "change_kind": "bugfix|feature|refactor|chore|docs|unknown",
  "modules": [
    {
      "id": "M1",
      "name": "pkg/router",
      "role_in_project": "请求路由与策略选择",
      "files_in_scope": ["pkg/router/handler.go"],
      "neighbors": ["pkg/scheduler", "api/v1"]
    }
  ],
  "feature_positioning": "该功能在系统中的位置（2-5 句）",
  "primary_flows": ["用户请求 → handler → backend"],
  "prod_entry_refs": ["cmd/foo/main.go:main", "pkg/server/server.go:Run"],
  "assumptions": ["假设上游已校验 X"],
  "risks_to_watch": ["与 feature gate Y 的交互"],
  "author_positions": [],
  "evidence_refs": ["README.md:12", "cmd/main.go:45"]
}
```

- `author_positions[]`：PR 时从 comment/review 提取的 waive/defer（对齐 audit `intent.author_stated_positions`，供 merger 参考，**不**替代质询）。
- 信息不足时填 `open_questions[]`（≤3 条），**禁止**编造模块职责；未知写 `unknown` 并注明依据不足。

### 7.0.3 约束

- `Write` **仅** `$REVIEW_TMP/change-context.json`
- Read ≤35，Grep ≤25（可 Read 未在 diff 中的入口/注册文件）
- 返回主线程 ≤6 行

### 7.0.4 与六维的关系

阶段 4 委派**任意** analyst 时，主编排 prompt **必须**附：

```text
必读背景：$REVIEW_TMP/change-context.json
finding 应结合 stated_intent 与 feature_positioning；无关背景的臆测 finding 视为低置信。
每条 finding 必填 issue_origin（§10.1）与 reachability（§8.0）。
```

---

## 8. 六维 analyst

### 8.0 全局硬要求（六个 agent 共同遵守）

#### 8.0.1 问题来源 `issue_origin`（每条 finding 必填）

| 值 | 含义 | 典型场景 |
|----|------|----------|
| `pr_introduced` | 缺陷由**本 PR 修改**引入，或仅存在于本次改动触及的逻辑 | diff 内新 bug、改坏调用方、改签名未改全 |
| `residual_existing` | **本 PR 修改之前**仓库已存在同类问题；本 PR 未修到 | 兄弟模块同 pattern 未修、上下游遗留；**第 7 维主责** |

- 第 1–5 维：以 `pr_introduced` 为主；若在**未改文件**发现与 PR 修复模式相同的遗漏 → `residual_existing`（或与第 6 维去重后保留一条）。
- 第 6 维（residual）：输出**仅** `residual_existing`。
- `report-writer` 终稿须分组或标签展示来源，禁止混为一谈。

#### 8.0.2 顶层入口可达性 `reachability`（防局部放大）

上报前必须从 **`change-context.primary_flows` / `prod_entry_refs`**（或自行识别的生产入口，如 `main`、`ServeHTTP`、controller Reconcile）**向下**追踪到声称的触发点：

```json
"reachability": {
  "prod_entry_refs": ["cmd/foo/main.go:42", "pkg/api/server.go:ListenAndServe"],
  "trace_summary": "main → InitRouter → handler → 触发点（≤5 步，path:line）",
  "reachable_in_prod": true,
  "blocked_by": null
}
```

| 规则 | 说明 |
|------|------|
| `reachable_in_prod: false` | 须在 `blocked_by` 写明挡板（guard、类型收窄、仅测试入口、feature off） |
| P0/P1 且 `reachable_in_prod: false` | merger **必须**降级至 P2 或 `rejected`（`unreachable_in_prod`） |
| 只读 diff 内一段代码就报 P0/P1 | **禁止**；须完成向下或向上贯通到入口/边界的追溯 |

`change-context.json` 应提供 `prod_entry_refs[]` 候选（来自 README、cmd/、常见启动路径）；各 analyst 可补充但不得虚构。

### 8.1 维度定义

| Agent | 维度 | 职责 |
|-------|------|------|
| correctness-analyst | 正确性 | 逻辑、边界、错误路径、与测试意图一致性（不执行测试） |
| architecture-analyst | 架构 | 模式一致性、模块边界、依赖方向、重复代码 |
| security-analyst | 安全 | 注入、鉴权、密钥、不可信输入、依赖风险提示 |
| performance-analyst | 性能 | N+1、无界查询/循环、热路径、UI 不必要重渲染 |
| impact-analyst | 影响面 | 本 PR 改动对兄弟路径/调用链/配置的波及（多为 `pr_introduced`） |
| residual-defect-scout | 残留同类缺陷 | **仅 bugfix**：仓库内同修复模式未修位置（仅 `residual_existing`） |

### 8.2 impact-analyst（第 5 维）

与第 6 维分工：**impact** 关注「这次改动是否牵连他人」；**residual** 关注「这次修 bug 的模式别处还有没有」。

### 8.3 impact-analyst 发现逻辑（自 audit 提炼，无质询）

**必读**（在 `review-files.json` 之外允许扩展阅读）：

1. **同类路径**：仓库内与本次修改同模式的其他文件/函数（对齐 audit `peer-path-comparator` / `similar-defect-scout` 的**发现**部分，不做法庭式质询）。
2. **调用链**：Grep 调用方；签名/guard 变更是否与 call site 一致（对齐 audit `path_consistency`）。
3. **改动外波及**：共享类型、默认值、feature flag、配置语义变更对未改文件的影响（对齐 audit `edge-effect-analyst`）。

鼓励 finding 字段：

```json
"impact": {
  "kind": "peer_path|call_chain|config_ripple",
  "related_sites": ["pkg/bar.go:88"]
}
```

**Read/Grep 预算**：建议高于其它 analyst（如 Read≤60, Grep≤40），在 agent 文件中写明。

### 8.4 residual-defect-scout（第 7 维，仅 bugfix）

**启用条件**（满足任一）：`change-context.change_kind == bugfix`；用户提示为 bug 修复；`pr-snapshot` 强暗示 fix。

**未启用**：`findings/residual.json` 且 `items: []`，`skipped: true`。

**任务**：提取 PR 修复模式 → 全仓库搜未修同类 → 仅输出 `issue_origin: residual_existing`；必填 `residual.pr_fix_pattern_ref`、`unfixed_evidence_refs[]`；`reachability.reachable_in_prod` 为 true 方可 P0/P1。

**与 impact 去重**：同根因保留一条，`dimensions` 可含 `residual` + `impact`。

### 8.5 各 analyst 通用约束

- **必须先 Read** `change-context.json`，再扫 `review-files.json`。
- 遵守 §8.0：`issue_origin` + `reachability` **必填**。
- 仅针对 `review-files.json` 扫描（impact/residual 可扩展阅读/Grep）。
- 每条 finding 须有 `location` + `trigger.failure_mode`。
- 遵守 ECC 误报清单（§9.2）。
- `Write` 仅 `$REVIEW_TMP/findings/<dimension>.json`。
- 返回主线程 ≤6 行。

### 8.6 严重等级 P0–P3（与 audit §5.7 对齐）

| 等级 | 要点 |
|------|------|
| P0 | 生产主路径崩溃/死锁/核心功能完全不可用 |
| P1 | 核心功能错误、数据错丢、可利用且影响生产的安全问题 |
| P2 | 边缘路径或特殊配置；有 workaround |
| P3 | 日志/指标/文案；不影响正确性 |

Analyst 可标 draft severity；**最终 severity 以 merger 为准**。

## 9. finding-merger

### 9.1 去重

- 键：`file` + `line÷20` + 归一化根因摘要（标题相似度）。
- 多维重复：合并为一条，`dimensions[]` 记录来源。
- **根因为「只改一处、同类未改」**：优先保留 **residual** 或 **impact** 一条（含 `residual_existing`），弱化 correctness 重复项。

### 9.2 ECC Pre-Report Gate（不通过 → `rejected.json`）

每条进入终稿的 finding 必须满足：

1. 能 cite 精确 `path:line`。
2. 能描述 **failure mode**（输入/状态/坏结果）。
3. analyst 已声明读过足够上下文（`context_read: true` 或 merger 可接受的 `evidence[]`）。
4. **P0/P1**：说明为何现有类型/guard/框架默认挡不住。

**误报黑名单**（merger 再扫，对齐 ECC）：

- 空泛「加 error handling」且调用方/框架已处理。
- 内部函数在调用方已校验时的「缺 validation」。
- 明显 magic number（HTTP 状态码、1024 等）。
- 仅 diff 断言、未读 yield/闭包全文的 two-phase 问题（impact/correctness 须 Read 完整块）。
- 测试/fixture 中的 hardcoded 期望。
- `Math.random` 非加密场景等。

### 9.3 输出

- 可读 `change-context.json`：与 `stated_intent` 明显无关 → `false_positive`。
- `reachable_in_prod: false` 且原 severity P0/P1 → 降级或 `unreachable_in_prod`。
- 缺少 `issue_origin` 或 `reachability` → `gate_failed`。

- `findings/merged.json`：`items[]`（终稿 finding，severity 最终值）。
- `findings/rejected.json`：`items[]` + `reject_reason`（gate_failed | false_positive | duplicate）。

**v1 禁止**：辩驳轮次、修改 analyst 原始文件（只读合并）。

## 10. Finding schema

```json
{
  "id": "C-003",
  "dimensions": ["correctness"],
  "issue_origin": "pr_introduced",
  "severity": "P1",
  "title": "简短标题",
  "location": { "file": "pkg/foo.go", "line": 42 },
  "trigger": {
    "description": "触发条件",
    "failure_mode": "具体坏结果"
  },
  "reachability": {
    "prod_entry_refs": ["cmd/app/main.go:28"],
    "trace_summary": "main → Run → handler → foo:42",
    "reachable_in_prod": true,
    "blocked_by": null
  },
  "evidence": ["pkg/foo.go:40-45 说明"],
  "suggestion": "建议改法",
  "confidence": "high|medium",
  "context_read": true,
  "impact": {
    "kind": "peer_path",
    "related_sites": ["pkg/bar.go:88"]
  }
}
```

### 10.1 `issue_origin`（必填枚举）

- `pr_introduced` | `residual_existing` — 见 §8.0.1。
- merger 拒绝缺少该字段的 finding。

### 10.2 residual 专用字段（`issue_origin == residual_existing` 时建议填）

```json
"residual": {
  "pr_fix_pattern_ref": "pkg/foo.go:100",
  "unfixed_evidence_refs": ["pkg/bar.go:88", "pkg/baz.go:120"],
  "fix_pattern_summary": "两阶段 yield 前缺少 eligibility 检查"
}
```

`id` 前缀建议：`C` correctness, `A` architecture, `S` security, `P` performance, `I` impact；merger 可重编号为 `F-001`。

## 11. REVIEW_RESULT 与报告

### 11.1 REVIEW_RESULT

| 条件 | 值 |
|------|-----|
| `merged.json` 中无成立 **P0–P2** | `mark_ignore` |
| 存在 ≥1 条成立 **P0–P2** | `mark_should_fix` |

- **P3**：可写入报告「仅供参考」；**不**改变 `REVIEW_RESULT`。
- **零 finding** 为合法结果 → `mark_ignore`。

### 11.1b 终稿最后一节（R16）

报告**最后**必须为：

```markdown
### 结论

REVIEW_RESULT=mark_ignore
```

或 `REVIEW_RESULT=mark_should_fix`。**仅此一行**，禁止解释、列表或其它段落。

### 11.2 stdout 报告结构（R15：禁止 markdown/HTML 表格）

`report-writer` 可读 `change-context.json`，在「摘要」中融入 `stated_intent` 与 `feature_positioning`（1–2 句）。

```markdown
## review 结论

### 摘要
（审查范围一句话；P0–P2 条数）

### 问题列表
（按 P0 → P1 → P2；每条须含 **来源**：本 PR 引入 / 仓库残留；含可达性摘要）
### 本 PR 引入的问题（issue_origin=pr_introduced）
### 仓库残留同类问题（issue_origin=residual_existing，若有）

### P3 备注（若有）

### 做得好的地方
（至少 1 条）

### 验证说明
（建议测试/检查项；不代跑）

### 结论

REVIEW_RESULT=mark_ignore
```

最后一节 `### 结论` **仅**一行 `REVIEW_RESULT=...`（R16），见 §11.1b。

`report-writer` 读 `findings/merged.json` + `scope.json` + `change-context.json`（+ `pr-snapshot.json` 可选）；返回 Markdown 字符串，主编排一次性 stdout。

## 12. 临时目录

```bash
REVIEW_TMP=$(mktemp -d)
mkdir -p "$REVIEW_TMP/findings"
trap '[[ -z "${REVIEW_KEEP_TMP:-}" ]] && rm -rf "$REVIEW_TMP"' EXIT
```

委派任何 sub-agent 时 prompt **必须**含：`REVIEW_TMP: <绝对路径>`。

## 13. v2 预留（本次不实现）

| 开关 | 行为 |
|------|------|
| `REVIEW_ENABLE_CHALLENGE=1` | 对 P0/P1 增加单轮 `review-challenger` |
| 后续已修 scout | 仅 merged PR + 用户显式要求对比 `HEAD` |
| 多模型审查 | writer / reviewer 不同模型（addyosmani 模式） |

## 14. 非目标（YAGNI）

- 原 `audit` 插件已从 marketplace 移除；历史 fix_mark / llm session 等专用节不在本插件范围。
- v1 不做 GitHub PR 自动发 comment（仅 stdout）。
- v1 不做 CI 集成 / GitHub Action。
- v1 不做自动修复代码。

## 15. 验收标准（插件级）

1. 用户给定开放 PR URL → 能产出带 `REVIEW_RESULT` 的 stdout 报告。
2. 用户给定「审 staged」→ 仅针对暂存区 diff 审查。
3. 阶段 3b 产出 `change-context.json`（含 `prod_entry_refs`、`pr_narrative`），六维 agent 含「必读 change-context」与 §8.0。
4. bugfix 时第 7 维产出 `residual.json`；非 bugfix 为空数组。
5. 所有 finding 含 `issue_origin` + `reachability`；不可达 P0/P1 被 merger 降级/拒绝。
6. 六维各写出 `findings/<dimension>.json`；merger 去重后无重复 P0–P2 双份同根因。
7. 故意含糊输入 → 主编排**只问 1 个**澄清问题，不猜测范围。
8. 干净小 diff → 允许 `fix_mark_ignore` 零 finding，不捏造问题。

## 16. Spec 自检记录（2026-06-04）

- [x] 无 TBD / TODO 占位
- [x] REVIEW_RESULT 与 P2+ 阈值一致（§11.1）
- [x] v1 无辩驳与 §13 v2 不矛盾
- [x] impact 与 audit peer/edge 职责边界：仅发现，无质询
- [x] change-context 在六维前（§7.0.4）
- [x] 六维含 residual（§8.4）；issue_origin + reachability（§8.0、§10）
- [x] 范围：单插件单 skill，可支撑后续 implementation plan 拆分
