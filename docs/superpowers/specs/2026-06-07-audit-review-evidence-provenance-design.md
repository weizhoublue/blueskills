# 设计文档：audit/review — 证据出处与可达性追溯增强（E1 / R1 / T3 v2）

- 日期：2026-06-07
- 状态：待审阅（brainstorming 确认）
- 父文档：[`2026-06-06-audit-review-trigger-concretization-design.md`](2026-06-06-audit-review-trigger-concretization-design.md)
- 背景：T1–T3 落地后，实际输出仍存在四类问题：（1）可达性证据仅写一层 caller，未从用户可见入口追到缺陷函数；（2）参考场景配置/输入为裸字段，缺少 CLI/YAML/env 出处；（3）量化观测与「造成的后果」重复；（4）变更点证据仅行号，缺符号与代码片段。

## 1. 问题陈述

以 vLLM 弹性 EP 扩展缺陷为例，当前典型输出不足：

| 问题 | 表现 |
|------|------|
| 变更点证据 | 只写 `utils.py:714-801`，无函数名与关键片段 |
| 可达性证据 | 只写 `scale_elastic_ep` → `add_dp_placement_groups`，无 env/CLI 顶层入口 |
| 参考场景 | `VLLM_RAY_DP_PLACEMENT_NODE_IPS=…`、`dp_size=8` 无配置面与出处；内部 API 误作「业务输入」 |
| 量化观测 | 与「造成的代码后果和业务功能后果」冗余 |

## 2. Brainstorming 决策摘要

| 决策点 | 选择 |
| --- | --- |
| 可达性追溯 | **A — 分层必填**：用户可见入口 + 完整调用链；找不到入口 → 删除 finding |
| 参考场景结构 | **用户配置** + **外部输入输出** 双块；删量化观测 |
| 业务输入边界 | 外部 I/O only；内部函数调用归 R1-b，不得写入外部输入输出 |
| 变更点证据 | **E1**：符号锚点 + 3～15 行关键片段 + 行号（辅助） |
| 完整链路主责 | **扩展 2b**：upstream 向上追溯至用户可见入口 |
| 顶层逻辑条件 | **T1 v2**：轻量（配置面 + 键 + refs）；详细出处只在参考场景展开 |
| 范围 | 仅 `plugins/audit/skills/review/SKILL.md`；investigate-issue R21 不在本次范围 |

## 3. 新增规则：E1（变更点证据）

写入 `相关代码证据 → 变更点证据`，每条**必填**：

1. **文件路径**
2. **符号**：函数 / 方法 / 类名（对应 diff 锚点）
3. **行号区间**：辅助定位，**不得**为唯一依据
4. **关键代码片段**：3～15 行；兄弟对比须体现差异（如有过滤 vs 无过滤）
5. **变更摘要**：一句话说明差异性质

**质检拒收：**

| 代号 | 说明 |
| --- | --- |
| `change_evidence_symbol_missing` | 缺符号 |
| `change_evidence_snippet_missing` | 缺片段或仅行号 |

## 4. 新增规则：R1（可达性证据）

写入 `相关代码证据 → 可达性证据`，三块**均必填**：

### 4.1 用户可见入口（R1-a）

须明确配置面 + 键/参数 + refs（定义/注册）。类型包括：环境变量、CLI、YAML/配置文件、CR spec、HTTP/RPC API、SDK 构造参数。

找不到任何用户可见入口 → finding 不得输出（`reachability_no_user_entry`）。

### 4.2 完整调用链（R1-b）

从 R1-a 入口到缺陷函数，每跳：`符号名 @ 文件路径:行号`。中间框架层（Ray、HTTP router、K8s controller）保留，不得跳过。

链路断点且无法补全 → `reachability_chain_gap`。

**内部函数调用**（如 `scale_elastic_ep` → `add_dp_placement_groups`）只写在此处，**不得**写入参考场景的「外部输入输出」。

### 4.3 防护未生效原因（R1-c）

说明 validation / defaulting / fallback / 兄弟路径对比为何未挡住。

### 4.4 与 T1 边界

| 规则 | 职责 |
| --- | --- |
| T1 顶层逻辑条件 | 抽象布尔前提（什么配置/外部条件使缺陷可触发） |
| R1 可达性证据 | 这些前提如何沿代码路径到达缺陷函数 |

## 5. T1 v2 — 顶层逻辑条件

每条逻辑条件至少含：

- **配置面**（环境变量 / CLI / YAML / CR / HTTP API / SDK / runtime 部署态 / 外部依赖态）
- **键或参数名**
- **refs**

不写完整四元组（避免与参考场景重复）。

## 6. T3 v2 — 参考触发场景

### 6.1 结构

```markdown
- **参考触发场景**（可评估；T3）：
  - **场景1**（来源：code_synth | pr_context | hybrid）
    - **映射条件**：条件1 + 条件2 + …
    - **用户配置**：（结构化条目；无则写「无」）
    - **外部输入输出**：（结构化条目；无则写「无（纯用户配置/内部运行时触发）」）
    - **应用层行为**：用户可理解的操作结果（非函数名罗列）
```

**删除字段：** `量化观测`、`软件配置`（旧名）、`业务输入`（旧名）。

### 6.2 用户配置 — 结构化条目

每个配置项一条：

| 字段 | 说明 |
| --- | --- |
| 配置面 | 环境变量 / CLI / YAML / CR spec / SDK 默认值等 |
| 键或参数 | 具体名称 |
| 取值 | 具体值 |
| 定义/注册 refs | 定义、注册、文档化位置 |
| 读取/生效 refs | 传入缺陷路径的读取点 |

### 6.3 外部输入输出 — 结构化条目

分两类子项（按实际存在选用）：

**A. 外部客户端输入** — 外部主动发给本软件的请求/操作（HTTP、CLI、gRPC、MQ 等）

**B. 外部服务响应** — 本软件依赖的外部系统返回（Ray cluster state、K8s API、第三方回调等）

每条条目含：I/O 类型、请求标识或来源服务、关键参数/字段与取值、定义/注册 refs、传入软件 refs。

无外部 I/O 时：

```markdown
- **外部输入输出**：无（纯用户配置 + 内部运行时触发；内部调用链见 R1-b）
```

### 6.4 内容归属表

| 内容 | 归属 |
| --- | --- |
| env / CLI / YAML / CR | 用户配置 / T1 顶层逻辑条件 |
| 外部 HTTP/CLI/gRPC 请求 | 外部输入输出 → 客户端输入 |
| Ray/K8s/第三方 API 响应 | 外部输入输出 → 外部服务响应 |
| 内部模块间函数调用 | R1-b 完整调用链 |
| 用户可观察的错误结果 | 应用层行为 + 造成的后果 |

## 7. 2b 流程扩展

在「阶段 B — upstream 核实」中追加：

1. caller 非用户可见入口时，**继续向上** Grep/Read，直至命中 env/CLI/YAML/CR/HTTP/SDK 或确认无法追溯。
2. 覆盖说明新增 **可达性追溯记录** 表（锚点、用户可见入口、链路跳数、结论）。
3. **主责**：2b 构建 R1 完整链路；2a/2c/2d 可写初步 caller，合并时以 2b 为准。

## 8. 阶段 3 质检新增/调整拒收项

| 代号 | 说明 |
| --- | --- |
| `change_evidence_symbol_missing` | E1：缺符号 |
| `change_evidence_snippet_missing` | E1：缺片段或仅行号 |
| `reachability_no_user_entry` | R1：无用户可见入口 |
| `reachability_chain_gap` | R1：调用链断点 |
| `trigger_logic_no_config_surface` | T1：顶层条件缺配置面或键名 |
| `trigger_scenario_no_provenance` | T3：缺配置面/I/O 类型/定义 refs/生效 refs |
| `trigger_scenario_bare_value` | T3：裸 key=value |
| `trigger_scenario_internal_as_external` | T3：内部调用写入外部输入输出 |
| `trigger_scenario_external_missing` | T3：有外部 API/依赖却写「无」 |
| `trigger_scenario_quant_obs_present` | T3：仍含量化观测 |

保留既有：`trigger_function_level_only`、`trigger_scenario_hedge`、`trigger_logic_hedge`；`trigger_scenario_no_concrete_value` 改为检查结构化字段完整性（不再检查量化观测）。

## 9. 正反例（vLLM 弹性 EP）

### 9.1 好例子（摘要）

```markdown
- 相关代码证据：
  1. 变更点证据：
     - 文件：`vllm/v1/engine/utils.py`
     - 符号：`create_dp_placement_groups` vs `add_dp_placement_groups`
     - 行号：527–550 vs 714–801
     - 关键片段：（create 含 allowed_ips 过滤；add 直接 list_nodes 无过滤）
     - 变更摘要：弹性扩展路径未复用节点 IP 过滤
  2. 可达性证据：
     - 用户可见入口：环境变量 `VLLM_RAY_DP_PLACEMENT_NODE_IPS`（envs.py:160）；Engine `enable_elastic_ep=True`
     - 完整调用链：env → Engine.__init__ → scale_elastic_ep @ :803 → add_dp_placement_groups @ :714
     - 防护未生效：create 有过滤，add 未复用，无 fallback
- 缺陷的触发条件：
  - **顶层逻辑条件**：
    - 条件1（config）：环境变量 `VLLM_RAY_DP_PLACEMENT_NODE_IPS` 已设置 refs: envs.py:160
    - 条件2（runtime）：弹性 EP 启用并触发 scale refs: utils.py:803
  - **参考触发场景**：
    - **场景1**（来源：code_synth）
      - **映射条件**：条件1 + 条件2
      - **用户配置**：（env + enable_elastic_ep 结构化条目，含 refs）
      - **外部输入输出**：
        - Ray `list_nodes()` 响应含 allowlist 外节点 refs: utils.py:714
      - **应用层行为**：扩展后新增 DP rank 的 placement 落在 allowlist 外节点
```

### 9.2 坏例子

| 写法 | 问题 |
| --- | --- |
| 变更点：`utils.py:714-801` 无符号无片段 | E1 违规 |
| 可达性：仅 `scale_elastic_ep → add_dp_placement_groups` | R1 违规 |
| 业务输入：`scale_elastic_ep(12)` | 内部调用误作外部输入 |
| 软件配置：`VLLM_RAY_…=10.0.0.1` 无配置面 | T3 裸值 |
| 量化观测：placement key 含 10.0.0.3 | 冗余，应删 |

## 10. `SKILL.md` 改动清单

| 位置 | 改动 |
| --- | --- |
| 共享规则 | 新增 E1、R1；T3 升级为 v2；T1 轻量出处 |
| 候选/终稿输出格式 | 变更点证据模板、可达性证据三块、参考场景双块 |
| 字段要求 `相关代码证据` | E1 + R1 全文 |
| 字段要求 `缺陷的触发条件` | T1 v2 + T3 v2；删量化观测 |
| 2b 必扫流程 | upstream 向上追溯 + 可达性追溯记录表 |
| 阶段 3 质检 | §8 拒收项 |
| 执行约束 | 禁止内部调用写入外部输入输出；禁止仅行号变更点证据 |

## 11. 验收标准

| # | 标准 |
| --- | --- |
| 1 | 共享规则含 E1、R1、T1 v2、T3 v2 全文 |
| 2 | 候选与终稿模板含变更点符号+片段、可达性三块、用户配置+外部输入输出双块 |
| 3 | 量化观测从 T3 与质检中移除 |
| 4 | 2b 含向上追溯与可达性追溯记录 |
| 5 | 阶段 3 含 §8 全部拒收代号 |
| 6 | 正反例含 vLLM 类案例 |
| 7 | 四阶段流程不变；不新增报告 `###` 子节 |

## 12. 非目标

- investigate-issue R21 同步（仍保留量化观测）
- 恢复 JSON schema / jq 管线
- 在参考场景中编造 PR/代码无法佐证的外部流量数值
- 要求每条 finding 必须有外部 HTTP 输入（纯配置触发时外部输入输出可为「无」）

## 13. Rollout

1. 更新 `plugins/audit/skills/review/SKILL.md`
2. bump `plugins/audit/.claude-plugin/plugin.json` 版本（若存在）
3. 编写 implementation plan（writing-plans）
4. 本 spec 于用户审阅通过后标 `approved`
