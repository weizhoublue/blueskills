# 设计文档：blueskills marketplace 重命名与安装修复

- 日期：2026-06-03
- 状态：**已批准**（A + D + G + K + 三层命名；`plugin.json` version = **0.1.0**）
- 上游：`2026-06-03-blueskills-plugin-design.md`（v7/v8 能力不变）
- 目标：`weizhoublue/blueskills` 作为 marketplace 可安装；首个 plugin `investigate-project`；入口 skill `report-features`。

## 1. 三层命名（canonical）

| 层级 | 标识符 | 用户可见操作 |
| --- | --- | --- |
| **Marketplace**（Git 仓库） | `blueskills` | `/plugin marketplace add weizhoublue/blueskills` |
| **Plugin**（可安装单元） | `investigate-project` | `/plugin install investigate-project@blueskills` |
| **Skill**（斜杠命令） | `report-features` | `/investigate-project:report-features` |

记忆：

- 安装：`<plugin>@<marketplace>` → `investigate-project@blueskills`
- 调用：`<plugin>:<skill>` → `/investigate-project:report-features`
- **禁止** plugin 名与 marketplace 名相同（避免 `blueskills@blueskills` 看不出装的是什么）。

产物目录（不变）：`<待分析项目>/analysis-report/`。

## 2. 已锁定决策

| 项 | 选择 |
| --- | --- |
| GitHub | `weizhoublue/blueskills` |
| 仓库布局 | marketplace 根 + `plugins/<plugin-name>/`（**K**） |
| 首个 plugin | `investigate-project` |
| 首个 skill | `report-features` |
| 文档替换 | **D** 全仓 |
| 版本 | plugin `0.1.0` |

## 3. 目录结构（实施后）

```text
blueskills/                                      # marketplace 根
├── .claude-plugin/
│   └── marketplace.json                         # name: blueskills
├── plugins/
│   └── investigate-project/                     # plugin 根
│       ├── .claude-plugin/
│       │   └── plugin.json                      # name: investigate-project, version: 0.1.0
│       ├── skills/
│       │   └── report-features/
│       │       └── SKILL.md                     # 编排入口（原 report-features 逻辑）
│       └── agents/
│           ├── project-scout.md
│           ├── feature-boundary-reviewer.md
│           ├── feature-digger.md
│           ├── integration-analyst.md
│           ├── report-writer.md
│           └── report-quality-challenger.md
├── docs/
│   ├── installation.md
│   ├── README.md
│   └── superpowers/...
└── README.md
```

### 3.1 未来新增 plugin

1. 创建 `plugins/<新-plugin名>/`（完整 plugin 树）。
2. 在 `marketplace.json` → `plugins[]` 追加 `{ "name": "…", "source": "./plugins/…" }`。
3. 用户：`/plugin install <新-plugin名>@blueskills`，调用 `/<新-plugin名>:<skill名>`。

无需新的 `marketplace add`。

## 4. 清单文件

### 4.1 `.claude-plugin/marketplace.json`

```json
{
  "name": "blueskills",
  "owner": {
    "name": "weizhoublue"
  },
  "metadata": {
    "description": "Blue Skills — Claude Code marketplace for coding agents and skills."
  },
  "plugins": [
    {
      "name": "investigate-project",
      "source": "./plugins/investigate-project",
      "description": "Investigate an open-source codebase and produce business-feature reports (report-features skill + six sub-agents)."
    }
  ]
}
```

marketplace 根**不得**包含 `plugin.json`。

### 4.2 `plugins/investigate-project/.claude-plugin/plugin.json`

```json
{
  "name": "investigate-project",
  "displayName": "Investigate Project",
  "version": "0.1.0",
  "description": "分析开源项目代码，梳理面向用户的业务功能并产出综合分析报告（report-features Skill + 六个 sub-agent）",
  "keywords": ["code-analysis", "project-investigation", "documentation"],
  "license": "MIT"
}
```

## 5. 全局替换映射

自旧仓库（`blueskills` / `investigate-project` / `report-features`）迁移时，**按顺序**执行：

| 序号 | 旧 | 新 |
| --- | --- | --- |
| 1 | `/investigate-project:report-features` | `/investigate-project:report-features` |
| 2 | `investigate-project@blueskills` | `investigate-project@blueskills` |
| 3 | `report-features` | `report-features`（仅 skill/目录语境；plugin 名用 investigate-project） |
| 4 | `weizhoublue/blueskills` | `weizhoublue/blueskills` |
| 5 | `investigate-project` | `investigate-project`（plugin 语境）或 `blueskills`（若原指 marketplace/repo，需人工判断） |
| 6 | `blueskills` | `blueskills`（marketplace/repo 语境） |

**注意 `investigate-project` → 两种新名：** 实施时用上下文区分 marketplace vs plugin，避免一律替换。建议先替换行 1–4，再对剩余 `investigate-project` 按「安装标识 / 斜杠前缀 / 页脚插件名」分别改为 `investigate-project` 或 `blueskills`。

**显式不替换：** `analysis-report`、`REPORT_ROOT`。

**禁止：** `coding-skills`、`blueskills@blueskills`（作为安装标识）、`/blueskills:…`（作为斜杠命令前缀）。

### 5.1 迁移对照（用户文档必备）

| 旧 | 新 |
| --- | --- |
| `weizhoublue/blueskills` | `weizhoublue/blueskills` |
| `investigate-project@blueskills` | `investigate-project@blueskills` |
| `/investigate-project:report-features` | `/investigate-project:report-features` |

## 6. 文件迁移（实施顺序）

1. `mkdir -p plugins/investigate-project/.claude-plugin plugins/investigate-project/skills/report-features`
2. 写入 §4 两个 JSON。
3. `git mv agents plugins/investigate-project/agents`
4. `git mv skills/report-features plugins/investigate-project/skills/report-features`（或等价路径）
5. 更新 `SKILL.md` 标题为 `# report-features`；cwd 检测指向 marketplace/plugin 路径。
6. agents 页脚：`investigate-project` 插件；improvement-log 指向 `report-features` skill。
7. 全仓 §5 替换 + 架构图路径更新。
8. 主 spec：`2026-06-03-blueskills-plugin-design.md` → `2026-06-03-blueskills-plugin-design.md`（内容同步三层命名与 `plugins/investigate-project/` 树）。
9. `docs/`、`README.md` 留在 marketplace 根。

## 7. Skill 要点（`report-features`）

- 正文逻辑沿用原 `report-features` 编排（六 agent、多轮确认、质审、improvement-log）。
- 阶段 0：`REPORT_ROOT = <cwd>/analysis-report` 不变。
- 若 cwd 在本 marketplace 克隆内（存在 `plugins/investigate-project/.claude-plugin/plugin.json`），提示用户 `cd` 到待分析项目。

## 8. 验收

### 8.1 结构

```bash
test -f .claude-plugin/marketplace.json
test ! -f .claude-plugin/plugin.json
test -f plugins/investigate-project/.claude-plugin/plugin.json
test -f plugins/investigate-project/plugins/investigate-project/plugins/investigate-project/skills/report-features/SKILL.md
test -d plugins/investigate-project/agents
! test -f plugins/investigate-project/skills/report-features/SKILL.md
! test -d plugins/blueskills

python3 -c "
import json
m=json.load(open('.claude-plugin/marketplace.json'))
assert m['name']=='blueskills'
assert m['plugins'][0]['name']=='investigate-project'
assert m['plugins'][0]['source']=='./plugins/investigate-project'
p=json.load(open('plugins/investigate-project/.claude-plugin/plugin.json'))
assert p['name']=='investigate-project' and p['version']=='0.1.0'
"

rg -n 'report-features|investigate-project@blueskills|/investigate-project:|blueskills@blueskills|/blueskills:' --glob '!*.git' && exit 1 || true
rg -n 'weizhoublue/blueskills' && exit 1 || true
```

### 8.2 Smoke test

```text
/plugin marketplace add weizhoublue/blueskills
/plugin install investigate-project@blueskills
/reload-plugins
/investigate-project:report-features
```

可选：`claude plugin validate .`（在 marketplace 根）。

## 9. 范围外

- 不实现第二个 plugin（仅预留 `plugins/` 约定）。
- 不改 JSON schema 与 agent 业务逻辑。
- 不重命名 `analysis-report/`。

## 10. 参考

- [Plugin marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)
- [Create plugins](https://code.claude.com/docs/en/plugins)
- 能力设计（实施后）：[`2026-06-03-blueskills-plugin-design.md`](./2026-06-03-blueskills-plugin-design.md)
