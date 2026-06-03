# 设计文档：blueskills 品牌重命名与 marketplace 修复

- 日期：2026-06-03
- 状态：已批准（A + D + G + **K**；`plugin.json` version = **0.1.0**；仓库 **weizhoublue/blueskills**）
- 上游：`2026-06-02-code-analyzer-plugin-design.md`（v7/v8 能力不变）
- 目标：仓库作为 **marketplace** 可安装；首个 plugin 位于 `plugins/blueskills/`；Skill 为 `investigate-project`。

## 1. 背景与问题

当前仓库（`weizhoublue/blueskills`）含 Skill、6 个 agent、superpowers 文档，但：

1. 缺少 `.claude-plugin/marketplace.json`，无法 `/plugin marketplace add`。
2. 历史命名混杂：`analyze-code`、`code-analyzer`、`analyze-codebase`。
3. 仓库定位为 **marketplace**（可挂多个 plugin），非单 plugin 占满根目录。

## 2. 已锁定决策

| 决策项 | 选择 |
| --- | --- |
| 品牌 | marketplace / 首个 plugin 名均为 **blueskills**；Skill **investigate-project** |
| 文档 | **D** 全仓替换旧标识 |
| 产物目录 | **G** 保留 `analysis-report/` |
| 版本 | **0.1.0** |
| 仓库布局 | **K** v0.1.0 起使用 `plugins/blueskills/`，为多 plugin 预留 |
| GitHub | **`weizhoublue/blueskills`** |

## 3. Marketplace 与 Plugin 的关系

```text
weizhoublue/blueskills          ← Git 仓库 = marketplace 根
├── .claude-plugin/
│   └── marketplace.json        ← 仅 marketplace 清单（无 plugin.json）
├── plugins/
│   └── blueskills/             ← 第 1 个 plugin（可再增 plugins/other-name/）
│       ├── .claude-plugin/
│       │   └── plugin.json
│       ├── skills/investigate-project/
│       └── agents/*.md
├── docs/                       ← 仓库级文档（不属于 plugin 包）
└── README.md
```

用户操作（不变）：

```text
/plugin marketplace add weizhoublue/blueskills    # 注册整个 marketplace
/plugin install blueskills@blueskills           # 只装其中一个 plugin
/blueskills:investigate-project                 # 调用该 plugin 的 skill
```

记忆：

- **Marketplace 名** = `marketplace.json` → `name`（`blueskills`）
- **Plugin 名** = 各 plugin 的 `plugin.json` → `name`（当前也是 `blueskills`）
- **安装** = `<plugin>@<marketplace>` → `blueskills@blueskills`
- **调用** = `<plugin>:<skill>` → `/blueskills:investigate-project`

### 3.1 未来新增第 2、第 N 个 plugin

在 `plugins/<新 plugin 名>/` 下新建完整 plugin 树，并在根 `marketplace.json` 的 `plugins` 数组追加一项：

```json
{
  "name": "doc-writer",
  "source": "./plugins/doc-writer",
  "description": "…"
}
```

用户侧：

```text
/plugin install doc-writer@blueskills
/doc-writer:some-skill
```

**无需**新的 `marketplace add`（除非换仓库）。各 plugin 的 `skills/`、`agents/` 互不共享。

> 依据 [Claude Code marketplace 文档](https://code.claude.com/docs/en/plugin-marketplaces)：同仓库 plugin 使用以 `./` 开头的相对路径，`source` 相对于**含 `.claude-plugin/` 的 marketplace 根**解析，而非相对于 `marketplace.json` 文件本身。

## 4. 目标命名与替换映射

| 层级 | 名称 |
| --- | --- |
| GitHub | `weizhoublue/blueskills` |
| Marketplace | `blueskills` |
| Plugin（首个） | `blueskills` |
| Skill | `investigate-project` |
| 产物 | `<cwd>/analysis-report/` |

### 4.1 全局替换（顺序执行）

| 序号 | 旧 | 新 |
| --- | --- | --- |
| 1 | `/code-analyzer:analyze-codebase` | `/blueskills:investigate-project` |
| 2 | `code-analyzer@analyze-code` | `blueskills@blueskills` |
| 3 | `analyze-codebase` | `investigate-project` |
| 4 | `weizhoublue/analyze-code` | `weizhoublue/blueskills` |
| 5 | `code-analyzer` | `blueskills` |
| 6 | `analyze-code` | `blueskills` |

不替换：`analysis-report`、`REPORT_ROOT`。禁止引入 `coding-skills`。

架构图/路径示例中的旧「仓库根 = plugin 根」改为 **marketplace 根** vs **`plugins/blueskills/`**。

## 5. 清单文件

### 5.1 根目录 `.claude-plugin/marketplace.json`

```json
{
  "name": "blueskills",
  "owner": {
    "name": "weizhoublue"
  },
  "metadata": {
    "description": "Blue Skills — Claude Code marketplace for project investigation and related skills."
  },
  "plugins": [
    {
      "name": "blueskills",
      "source": "./plugins/blueskills",
      "description": "Investigate an open-source codebase (investigate-project + six sub-agents)."
    }
  ]
}
```

**注意：** marketplace 根**不要**放 `plugin.json`。

### 5.2 `plugins/blueskills/.claude-plugin/plugin.json`

```json
{
  "name": "blueskills",
  "displayName": "Blue Skills",
  "version": "0.1.0",
  "description": "分析开源项目代码，梳理面向用户的业务功能并产出综合分析报告（investigate-project Skill + 六个 sub-agent）",
  "keywords": ["code-analysis", "project-investigation", "documentation"],
  "license": "MIT"
}
```

## 6. 文件迁移步骤（实施）

1. `mkdir -p plugins/blueskills/.claude-plugin`
2. 写入 §5 两个 JSON。
3. `git mv agents plugins/blueskills/agents`
4. `git mv skills/analyze-codebase plugins/blueskills/skills/investigate-project`（若已是 analyze-codebase；否则先 mv 再 rename skill 目录）
5. 全仓 §4.1 替换；更新架构图中的路径前缀为 `plugins/blueskills/`。
6. `docs/`、`README.md` 留在 marketplace 根（描述整个 marketplace + 已安装 plugin 列表）。

### 6.1 Skill 防误写（cwd 检测）

在 `plugins/blueskills/skills/investigate-project/SKILL.md` 中，若 cwd 含本 marketplace 特征（例如存在 `plugins/blueskills/.claude-plugin/plugin.json` 或用户位于克隆的 `blueskills` 仓库内），提示先 `cd` 到**待分析项目**再运行。

### 6.2 agents

页脚改为 `blueskills` 插件；improvement-log 指向 `investigate-project`。

## 7. 文档（D）

| 文件 | 内容 |
| --- | --- |
| `README.md` | 说明这是 marketplace；列出 plugin；安装 §3 命令；指向 `docs/installation.md` |
| `docs/installation.md` | 区分 marketplace / plugin / skill 三层；`plugins/` 布局说明；迁移表 |
| `docs/superpowers/**` | 替换 + 主 spec → `2026-06-03-blueskills-plugin-design.md` |

### 7.1 从旧版迁移

| 旧 | 新 |
| --- | --- |
| `weizhoublue/analyze-code` | `weizhoublue/blueskills` |
| `code-analyzer@analyze-code` | `blueskills@blueskills` |
| `/code-analyzer:analyze-codebase` | `/blueskills:investigate-project` |

## 8. 验收

### 8.1 结构

```bash
test -f .claude-plugin/marketplace.json
test ! -f .claude-plugin/plugin.json
test -f plugins/blueskills/.claude-plugin/plugin.json
test -f plugins/blueskills/skills/investigate-project/SKILL.md
test -d plugins/blueskills/agents

python3 -c "import json; m=json.load(open('.claude-plugin/marketplace.json')); assert m['name']=='blueskills'; assert m['plugins'][0]['source']=='./plugins/blueskills'"
python3 -c "import json; p=json.load(open('plugins/blueskills/.claude-plugin/plugin.json')); assert p['name']=='blueskills' and p['version']=='0.1.0'"

rg -n 'analyze-codebase|code-analyzer@analyze-code|/code-analyzer:' --glob '!*.git' && exit 1 || true
rg -n 'weizhoublue/analyze-code' && exit 1 || true
rg -n 'coding-skills' --glob '!*.git' && exit 1 || true
```

### 8.2 Smoke test

```bash
claude plugin validate .   # 在 marketplace 根执行（若 CLI 可用）
```

```text
/plugin marketplace add weizhoublue/blueskills
/plugin install blueskills@blueskills
/reload-plugins
/blueskills:investigate-project
```

## 9. 范围外

- 不新增第二个 plugin（仅预留目录约定）。
- 不改业务逻辑与 JSON schema。
- 不重命名 `analysis-report/`。

## 10. 参考

- Marketplace：<https://code.claude.com/docs/en/plugin-marketplaces>
- Plugins：<https://code.claude.com/docs/en/plugins>
- 能力设计（实施后）：[`2026-06-03-blueskills-plugin-design.md`](./2026-06-03-blueskills-plugin-design.md)
