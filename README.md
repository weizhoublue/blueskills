# blueskills

[weizhoublue/blueskills](https://github.com/weizhoublue/blueskills) 是一个 Claude Code **marketplace**，收录面向研发场景的插件与 Skill。当前包含首个插件 **investigate-project**（开源项目业务功能分析）。

## 安装

在 Claude Code 会话内：

```text
/plugin marketplace add weizhoublue/blueskills
/plugin install investigate-project@blueskills
/reload-plugins
```

本地开发（已克隆本仓库）：

```text
/plugin marketplace add /absolute/path/to/blueskills
/plugin install investigate-project@blueskills
/reload-plugins
```

完整说明见 [`docs/installation.md`](docs/installation.md)。

## 使用方式

在**待分析开源项目**的根目录下执行（先 `cd` 到目标项目）：

```text
/investigate-project:report-features
```

阶段 0 会在该项目下创建 `analysis-report/` 并打印 `REPORT_ROOT` 绝对路径。请勿在 marketplace 源码目录内直接运行，以免报告写入错误位置。

## 仓库结构

```text
blueskills/
├── .claude-plugin/marketplace.json
├── plugins/
│   └── investigate-project/          # plugin：业务功能分析
│       ├── skills/report-features/   # skill 入口
│       └── agents/                   # 六个 sub-agent
└── docs/
```

## 文档

- 安装与故障排查：[`docs/installation.md`](docs/installation.md)
- 产品设计：[`docs/README.md`](docs/README.md)
- 能力设计 spec：[`docs/superpowers/specs/2026-06-03-blueskills-plugin-design.md`](docs/superpowers/specs/2026-06-03-blueskills-plugin-design.md)
- 重命名说明：[`docs/superpowers/specs/2026-06-03-blueskills-rebrand-design.md`](docs/superpowers/specs/2026-06-03-blueskills-rebrand-design.md)
