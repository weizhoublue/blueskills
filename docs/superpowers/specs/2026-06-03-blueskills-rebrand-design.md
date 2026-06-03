# 设计文档：blueskills 品牌重命名与 marketplace 修复

- 日期：2026-06-03
- 状态：已批准（方案 A + D + G；`plugin.json` version = **0.1.0**；仓库名 **blueskills**）
- 上游：`2026-06-02-code-analyzer-plugin-design.md`（v7/v8 能力不变，仅标识与安装路径变更）
- 目标：使 `weizhoublue/blueskills` 作为 Claude Code marketplace 可成功安装，Skill 更名为 `investigate-project`，仓库内命名一致。

## 1. 背景与问题

当前仓库（本地目录 `blueskills`，远程 `weizhoublue/blueskills`）包含完整的 Skill、6 个 agent 与 superpowers 设计文档，但：

1. **缺少** `.claude-plugin/marketplace.json` 与 `.claude-plugin/plugin.json`，无法按文档执行 `/plugin marketplace add`。
2. 品牌与历史命名混杂：`analyze-code`、`code-analyzer`、`analyze-codebase`。
3. 对外品牌为 **blueskills**（用户口语「blue skill」），Skill 为 **investigate-project**。

## 2. 已锁定决策

| 决策项 | 选择 |
| --- | --- |
| 品牌对齐范围 | **A** — marketplace、plugin、GitHub 路径、skill 对齐 `blueskills` / `investigate-project` |
| 文档替换范围 | **D** — 全仓 `.md` / `.json` 旧标识一律替换（含 `docs/superpowers/**`） |
| 产物目录 | **G** — 保留 `analysis-report/` 与 `REPORT_ROOT` 不变 |
| 插件版本 | **`0.1.0`** |
| GitHub 仓库 | **`weizhoublue/blueskills`**（不改为 coding-skills） |

## 3. 目标命名

| 层级 | 新名称 |
| --- | --- |
| GitHub 仓库 | `weizhoublue/blueskills` |
| Marketplace | `blueskills`（`marketplace.json` → `name`） |
| Plugin | `blueskills`（`plugin.json` → `name`） |
| 安装标识 | `blueskills@blueskills` |
| Skill 目录 | `skills/investigate-project/` |
| 斜杠命令 | `/blueskills:investigate-project` |
| 产物根目录 | `<cwd>/analysis-report/`（不变） |

### 3.1 用户可见命令（canonical）

```text
/plugin marketplace add weizhoublue/blueskills
/plugin install blueskills@blueskills
/reload-plugins
/blueskills:investigate-project
```

### 3.2 全局替换映射（按顺序执行）

| 序号 | 旧 | 新 |
| --- | --- | --- |
| 1 | `/code-analyzer:analyze-codebase` | `/blueskills:investigate-project` |
| 2 | `code-analyzer@analyze-code` | `blueskills@blueskills` |
| 3 | `analyze-codebase` | `investigate-project` |
| 4 | `weizhoublue/analyze-code` | `weizhoublue/blueskills` |
| 5 | `code-analyzer` | `blueskills` |
| 6 | `analyze-code` | `blueskills` |

**显式不替换：**

- `analysis-report`、`analysis-report/`、`REPORT_ROOT`。
- 已是 `blueskills` / `weizhoublue/blueskills` 的字符串（避免重复替换）。

**禁止引入：**

- 将仓库或命令写成 `coding-skills`（除非历史迁移表「旧→新」对比行中作为旧名出现）。

## 4. 目录结构（实施后）

```text
blueskills/                            # 仓库根 = marketplace 根 = plugin 根
├── .claude-plugin/
│   ├── marketplace.json
│   └── plugin.json                    # version: 0.1.0
├── skills/
│   └── investigate-project/
│       └── SKILL.md
├── agents/                            # 6 个 agent
├── docs/
└── README.md
```

### 4.1 主设计 spec 重命名

- `2026-06-02-code-analyzer-plugin-design.md` → `2026-06-03-blueskills-plugin-design.md`
- 标题：「blueskills Claude Code 插件」；架构图与 §3 命令一致。

## 5. 新建清单文件

### 5.1 `marketplace.json`

```json
{
  "name": "blueskills",
  "owner": {
    "name": "weizhoublue"
  },
  "metadata": {
    "description": "Claude Code skills marketplace for investigating open-source projects (blueskills plugin)."
  },
  "plugins": [
    {
      "name": "blueskills",
      "source": ".",
      "description": "Investigate an open-source codebase via investigate-project skill and six sub-agents."
    }
  ]
}
```

### 5.2 `plugin.json`

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

## 6. Skill 与 agent 变更要点

### 6.1 `skills/investigate-project/SKILL.md`

- `git mv skills/analyze-codebase skills/investigate-project`
- 标题：`# investigate-project`
- 防误写：若 cwd 为插件仓库 `blueskills`（含 `.claude-plugin/`），提示用户 cd 到待分析项目。

### 6.2 `agents/*.md`

- 页脚：`blueskills` 插件；improvement-log 指向 `investigate-project` skill。

## 7. 文档变更（D）

| 文件 | 变更 |
| --- | --- |
| `README.md` | 品牌 blueskills、§3.1 四条命令、产物树 |
| `docs/installation.md` | 命名表、安装、迁移、version `0.1.0` |
| `docs/superpowers/**` | §3.2 映射 + 主 spec 重命名 |

### 7.1 从旧版迁移

| 旧 | 新 |
| --- | --- |
| `weizhoublue/analyze-code` | `weizhoublue/blueskills` |
| `code-analyzer@analyze-code` | `blueskills@blueskills` |
| `/code-analyzer:analyze-codebase` | `/blueskills:investigate-project` |

## 8. 实施方式

1. 新建 `.claude-plugin/` 清单（§5）。
2. `git mv` skill 目录。
3. 按 §3.2 全仓替换。
4. 重命名主 spec，更新内链。
5. §9 验收。

## 9. 验收标准

### 9.1 结构自检

```bash
test -f .claude-plugin/marketplace.json
test -f .claude-plugin/plugin.json
test -f skills/investigate-project/SKILL.md
! test -d skills/analyze-codebase

python3 -c "import json; m=json.load(open('.claude-plugin/marketplace.json')); assert m['name']=='blueskills'"
python3 -c "import json; p=json.load(open('.claude-plugin/plugin.json')); assert p['name']=='blueskills' and p['version']=='0.1.0'"

rg -n 'analyze-codebase|code-analyzer@analyze-code|/code-analyzer:' --glob '!*.git' && exit 1 || true
rg -n 'weizhoublue/analyze-code' && exit 1 || true
rg -n 'coding-skills' --glob '!*.git' && exit 1 || true
```

### 9.2 Claude Code smoke test

```text
/plugin marketplace add weizhoublue/blueskills
/plugin install blueskills@blueskills
/reload-plugins
/blueskills:investigate-project
```

阶段 0 创建 `<项目>/analysis-report/`。

## 10. 范围外

- 不修改 GitHub 仓库名（保持 `blueskills`）。
- 不改 skill 业务逻辑与 JSON schema。
- 不重命名 `analysis-report/`。

## 11. 参考

- 插件文档：<https://code.claude.com/docs/zh-CN/plugins>
- Marketplace：<https://code.claude.com/docs/zh-CN/plugin-marketplaces>
- 能力设计（实施后）：[`2026-06-03-blueskills-plugin-design.md`](./2026-06-03-blueskills-plugin-design.md)
