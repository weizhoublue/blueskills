# 设计文档：coding-skills 品牌重命名与 marketplace 修复

- 日期：2026-06-03
- 状态：已批准（用户确认方案 A + D + G，`plugin.json` version = **0.1.0**）
- 上游：`2026-06-02-code-analyzer-plugin-design.md`（v7/v8 能力不变，仅标识与安装路径变更）
- 目标：使 `weizhoublue/coding-skills` 作为 Claude Code marketplace 可成功安装，Skill 更名为 `investigate-project`，仓库内命名一致。

## 1. 背景与问题

当前仓库（本地目录 `blueskills`，远程 `weizhoublue/blueskills`）包含完整的 Skill、6 个 agent 与 superpowers 设计文档，但：

1. **缺少** `.claude-plugin/marketplace.json` 与 `.claude-plugin/plugin.json`，无法按文档执行 `/plugin marketplace add`。
2. 品牌与历史命名混杂：`analyze-code`、`code-analyzer`、`analyze-codebase`。
3. 用户已将产品定位为 **weizhoublue coding-skills**，Skill 应称为 **investigate-project**。

## 2. 已锁定决策

| 决策项 | 选择 |
| --- | --- |
| 品牌对齐范围 | **A** — marketplace、plugin、GitHub 路径、skill 全部对齐 `coding-skills` / `investigate-project` |
| 文档替换范围 | **D** — 全仓 `.md` / `.json` 旧标识一律替换（含 `docs/superpowers/**` 历史 spec/plan） |
| 产物目录 | **G** — 保留 `analysis-report/` 与 `REPORT_ROOT` 语义不变 |
| 插件版本 | **`0.1.0`**（新品牌下的初始发布，非从旧 0.3.0 递增） |

## 3. 目标命名

| 层级 | 新名称 |
| --- | --- |
| GitHub 仓库 | `weizhoublue/coding-skills` |
| Marketplace | `coding-skills`（`marketplace.json` → `name`） |
| Plugin | `coding-skills`（`plugin.json` → `name`） |
| 安装标识 | `coding-skills@coding-skills` |
| Skill 目录 | `skills/investigate-project/` |
| 斜杠命令 | `/coding-skills:investigate-project` |
| 产物根目录 | `<cwd>/analysis-report/`（不变） |

### 3.1 全局替换映射（按顺序执行）

执行顺序从长到短、从具体到泛化，避免子串误替换：

| 序号 | 旧 | 新 |
| --- | --- | --- |
| 1 | `/code-analyzer:analyze-codebase` | `/coding-skills:investigate-project` |
| 2 | `code-analyzer@analyze-code` | `coding-skills@coding-skills` |
| 3 | `analyze-codebase` | `investigate-project` |
| 4 | `weizhoublue/analyze-code` | `weizhoublue/coding-skills` |
| 5 | `code-analyzer` | `coding-skills` |
| 6 | `analyze-code` | `coding-skills` |

**显式不替换：**

- `analysis-report`、`analysis-report/`、`REPORT_ROOT` 相关逻辑与路径示例（除非句子同时提及旧插件名，仅替换插件/skill 部分）。

**谨慎替换：**

- 本地路径 `blueskills` → 仅在表示「仓库目录/Git 克隆名」时改为 `coding-skills`；不修改用户本机已有文件夹名。

## 4. 目录结构（实施后）

```text
coding-skills/                         # 仓库根 = marketplace 根 = plugin 根
├── .claude-plugin/
│   ├── marketplace.json               # 新建
│   └── plugin.json                    # 新建，version: 0.1.0
├── skills/
│   └── investigate-project/
│       └── SKILL.md
├── agents/
│   ├── project-scout.md
│   ├── feature-boundary-reviewer.md
│   ├── feature-digger.md
│   ├── integration-analyst.md
│   ├── report-writer.md
│   └── report-quality-challenger.md
├── docs/
│   ├── installation.md
│   ├── README.md
│   └── superpowers/
│       ├── specs/
│       │   ├── 2026-06-03-coding-skills-rebrand-design.md   # 本文
│       │   ├── 2026-06-03-coding-skills-plugin-design.md    # 自旧主 spec 重命名并替换内容
│       │   └── …（其余 spec 内链与旧名全量更新）
│       └── plans/                     # 全量更新旧名与路径
└── README.md
```

### 4.1 主设计 spec 重命名

- `2026-06-02-code-analyzer-plugin-design.md` → `2026-06-03-coding-skills-plugin-design.md`
- 文首标题改为「coding-skills Claude Code 插件」；架构图中目录树与命令同步 §3。
- 所有引用该文件的 spec/plan/README 内链更新为新文件名。

## 5. 新建清单文件

### 5.1 `marketplace.json`

```json
{
  "name": "coding-skills",
  "owner": {
    "name": "weizhoublue"
  },
  "metadata": {
    "description": "Claude Code skills for investigating open-source projects (coding-skills plugin marketplace)."
  },
  "plugins": [
    {
      "name": "coding-skills",
      "source": ".",
      "description": "Investigate an open-source codebase and produce business-feature reports via investigate-project skill and six sub-agents."
    }
  ]
}
```

（`metadata` / `plugins[].description` 可在实施时改为中文，与仓库语言风格一致。）

### 5.2 `plugin.json`

```json
{
  "name": "coding-skills",
  "displayName": "Coding Skills",
  "version": "0.1.0",
  "description": "分析开源项目代码，梳理面向用户的业务功能并产出综合分析报告（investigate-project Skill + 六个 sub-agent）",
  "keywords": ["code-analysis", "project-investigation", "documentation"],
  "license": "MIT"
}
```

## 6. Skill 与 agent 变更要点

### 6.1 `skills/investigate-project/SKILL.md`

- 目录：`git mv skills/analyze-codebase skills/investigate-project`
- 标题：`# investigate-project`
- frontmatter `description`：保留中文，体现「调查/梳理项目」与 `analysis-report` 输出路径。
- 阶段 0：`REPORT_ROOT = <cwd>/analysis-report` 不变。
- 防误写：检测「当前 cwd 是否为插件仓库 `coding-skills`」而非旧名 `analyze-code`。

### 6.2 `agents/*.md`

- 报告页脚：`coding-skills` 插件自动生成。
- improvement-log 等维护说明：指向 `investigate-project` skill。
- 所有写入路径仍以 `REPORT_ROOT` / `analysis-report` 为准。

## 7. 文档变更（D）

| 文件 | 变更 |
| --- | --- |
| `README.md` | 重写：品牌、安装、调用、产物树、设计文档链接 |
| `docs/README.md` | 与安装/使用命令对齐 |
| `docs/installation.md` | 命名表、命令、故障排查、迁移小节；`version` 说明改为 `0.1.0` |
| `docs/superpowers/specs/*.md` | 映射表替换 + 主 spec 重命名 |
| `docs/superpowers/plans/*.md` | 映射表替换；`cd` 示例路径改为 `coding-skills` |

### 7.1 从旧版迁移（写入 `installation.md`）

| 旧 | 新 |
| --- | --- |
| `/plugin marketplace add weizhoublue/analyze-code` | `weizhoublue/coding-skills` |
| `code-analyzer@analyze-code` | `coding-skills@coding-skills` |
| `/code-analyzer:analyze-codebase` | `/coding-skills:investigate-project` |

建议步骤：`/plugin marketplace remove analyze-code` → `/plugin uninstall code-analyzer@analyze-code` → 按新命令安装 → `/reload-plugins`。

不保留旧 marketplace 别名（干净切断）。

## 8. 实施方式（推荐：结构化迁移）

1. **创建** `.claude-plugin/marketplace.json`、`plugin.json`（version `0.1.0`）。
2. **`git mv`** `skills/analyze-codebase` → `skills/investigate-project`。
3. **按 §3.1 顺序** 对全仓 `*.md`、`*.json` 执行替换（可用脚本，但须人工 diff 审查）。
4. **重命名** 主 spec 并更新所有相对链接。
5. **运行验收脚本**（§9）。
6. **手动**：`claude plugin validate .`（若 CLI 可用）+ 安装 smoke test。

不推荐双轨并存旧 skill/plugin 目录。

## 9. 验收标准

### 9.1 结构自检

```bash
test -f .claude-plugin/marketplace.json
test -f .claude-plugin/plugin.json
test -f skills/investigate-project/SKILL.md
! test -d skills/analyze-codebase

python3 -c "import json; m=json.load(open('.claude-plugin/marketplace.json')); assert m['name']=='coding-skills'"
python3 -c "import json; p=json.load(open('.claude-plugin/plugin.json')); assert p['name']=='coding-skills' and p['version']=='0.1.0'"

# 以下应无匹配（exit 0 = 通过）
rg -n 'analyze-codebase|code-analyzer@analyze-code|/code-analyzer:' --glob '!*.git' && exit 1 || true
rg -n 'weizhoublue/analyze-code' && exit 1 || true
```

### 9.2 Claude Code 安装 smoke test

```text
/plugin marketplace add weizhoublue/coding-skills
/plugin install coding-skills@coding-skills
/reload-plugins
```

在待分析项目目录：

```text
/coding-skills:investigate-project
```

阶段 0 应创建 `<项目>/analysis-report/`。

## 10. 范围外

- 不重命名 GitHub 远程仓库（用户自行将 `blueskills` 改为 `coding-skills` 或添加新 remote）。
- 不修改 skill 业务逻辑、agent 工作流、JSON schema（v7/v8 行为保持不变）。
- 不将 `analysis-report/` 改为 `investigation-report/`。

## 11. 参考

- Claude Code 插件：<https://code.claude.com/docs/zh-CN/plugins>
- Marketplace：<https://code.claude.com/docs/zh-CN/plugin-marketplaces>
- 能力设计（重命名后）：[`2026-06-03-coding-skills-plugin-design.md`](./2026-06-03-coding-skills-plugin-design.md)（实施时由旧文件迁移）
