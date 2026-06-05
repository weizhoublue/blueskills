# audit 插件设计文档

**日期：** 2026-06-05  
**状态：** 已确认

---

## 背景

`plugins/audit/skills/SKILL.md` 是一个独立设计的代码审计 skill，定义了四阶段缺陷审查流程。目标是将其包装成标准 Claude Code 插件结构，供 marketplace 分发，与现有 `audit-code` 插件并列。

---

## 目标

- 逻辑零改动：原 SKILL.md 的所有规则、输出格式、执行约束保持不变
- 结构标准化：符合 Claude Code 插件目录规范
- 可发布：注册进 `.claude-plugin/marketplace.json`

---

## 目录结构

```
plugins/audit/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   └── review/
│       └── SKILL.md          # 主编排者：总流程 + 阶段4报告拼装
└── agents/
    ├── intent-analyst.md     # 阶段1：变更意图分析
    ├── defect-scanner.md     # 阶段2：代码缺陷扫描
    └── quality-checker.md    # 阶段3：质检
```

旧文件 `plugins/audit/skills/SKILL.md`（无子目录）删除。

---

## plugin.json

```json
{
  "name": "audit",
  "displayName": "Audit",
  "version": "0.1.0",
  "description": "对本地代码变更、在线 PR 等进行缺陷分析和质量评审，输出一份完整的缺陷和严重等级的分析报告",
  "keywords": ["code-review", "pr-review", "audit"],
  "license": "MIT"
}
```

---

## 调用入口

`/audit:review` — 用户提供 PR URL、commit hash、patch 文件、diff 内容或本地仓库路径。

---

## 通信机制：Markdown 文本传递

四个阶段顺序执行，agent 间通过 markdown 文本传递上下文：

```
/audit:review
  ↓ 主skill读取输入（PR/diff/commit）
  ↓ 委派 intent-analyst
  ← 返回：变更意图分析 markdown
  ↓ 委派 defect-scanner（含意图分析 markdown）
  ← 返回：候选缺陷 markdown
  ↓ 委派 quality-checker（含候选缺陷 markdown）
  ← 返回：质检后缺陷 markdown
  ↓ 主skill执行阶段4报告拼装
  → stdout：最终审计报告
```

无临时文件、无 JSON 中间态。

---

## 各文件职责

### `skills/review/SKILL.md`（主编排）

- 接受用户输入，读取 PR/diff 内容
- 按顺序委派三个 agent
- 执行阶段4报告拼装（合并相同根因、去重、生成最终报告）
- 仅输出 stdout，不写入仓库文件

### `agents/intent-analyst.md`（阶段1）

从原 SKILL.md "# 1. 变更意图分析" 章节提取。

- 输入：diff/PR 元数据
- 输出：`## 变更意图分析` markdown 块
- 约束：不输出缺陷，不判断代码正确性

### `agents/defect-scanner.md`（阶段2）

从原 SKILL.md "# 2. 代码缺陷扫描" 章节提取。

- 输入：diff + 变更意图分析 markdown
- 输出：`### 候选缺陷 N：标题` markdown 块列表
- 约束：只输出满足五个成立条件的缺陷，忽略 P3

### `agents/quality-checker.md`（阶段3）

从原 SKILL.md "# 3. 质检" 章节提取。

- 输入：候选缺陷 markdown 列表
- 输出：质检后的候选缺陷（成立保留、不成立删除）
- 约束：终稿禁止含"可能/大概/也许/似乎/潜在"等模糊词

---

## marketplace.json 变更

在 `.claude-plugin/marketplace.json` 的 `plugins[]` 新增：

```json
{
  "name": "audit",
  "source": "./plugins/audit",
  "description": "对本地代码变更、在线 PR 等进行缺陷分析和质量评审，输出一份完整的缺陷和严重等级的分析报告"
}
```

---

## 不在本次范围内

- 不改造为 JSON 中间态通信（audit-code 风格）
- 不引入 shell 脚本
- 不修改审计逻辑、缺陷判断标准或报告格式
