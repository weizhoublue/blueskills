# 在 Claude Code 中安装 blueskills marketplace

本仓库是一个 **Claude Code marketplace**（`weizhoublue/blueskills`）。根目录仅有 marketplace 清单；各 plugin 位于 `plugins/<plugin-name>/`：

```text
blueskills/
├── .claude-plugin/
│   └── marketplace.json              # marketplace 名：blueskills
└── plugins/
    └── investigate-project/          # 当前首个 plugin
        ├── .claude-plugin/plugin.json
        ├── skills/report-features/
        └── agents/
```

流程：**添加 marketplace 一次** → **按需安装其中的 plugin**（例如 `investigate-project`）→ 调用对应 skill。

> 前置条件：已安装并登录 Claude Code（建议保持最新版，本文档命令在 v2.1.160 上验证通过）。如果你的 Claude Code 还没有 `/plugin` 命令，请先升级：
>
> ```bash
> brew upgrade claude-code            # 或
> npm install -g @anthropic-ai/claude-code@latest
> ```

---

## 命名约定

| 名称 | 含义 | 来源 |
| --- | --- | --- |
| `blueskills` | **marketplace 名**（安装时作为命名空间后缀） | `marketplace.json` 的 `name` |
| `investigate-project` | **plugin 名** | `plugin.json` 的 `name` |
| `investigate-project@blueskills` | 安装/启停/卸载时的**完整标识** | 由上面两项拼成 |
| `/investigate-project:report-features` | 启用后调用的 skill | `<plugin>:<skill>` |

> 记忆口诀：**`<插件名>@<marketplace 名>`**，调用 skill 时则是 **`<插件名>:<skill 名>`**。

---

## 方式一：从 GitHub 安装（推荐）

适合：日常使用、跨机器复用、团队共享。

在 Claude Code 会话内：

```text
/plugin marketplace add weizhoublue/blueskills
/plugin install investigate-project@blueskills
/reload-plugins
```

或在终端非交互执行：

```bash
claude plugin marketplace add weizhoublue/blueskills
claude plugin install investigate-project@blueskills
```

钉到特定分支/标签：

```bash
claude plugin marketplace add weizhoublue/blueskills@v0.3.0
```

非 GitHub 主机（GitLab / Bitbucket / 自建服务器）用完整 URL，`#ref` 钉分支或标签：

```bash
claude plugin marketplace add https://gitlab.com/your-org/blueskills.git#main
claude plugin marketplace add git@gitlab.com:your-org/blueskills.git
```

私有仓库注意事项：

- 手动 `add` / `install` 会复用本机 git 凭证（`gh auth login`、Keychain、`git-credential-store`、`ssh-agent`）。
- 启动时的**后台自动更新**不走交互式凭证，需要在 shell 环境提供 token：GitHub 用 `GITHUB_TOKEN` 或 `GH_TOKEN`，GitLab 用 `GITLAB_TOKEN`，Bitbucket 用 `BITBUCKET_TOKEN`。

---

## 方式二：从本地路径安装

适合：离线机器；或你已经克隆了仓库、想用本地副本作为 marketplace。

```bash
git clone https://github.com/weizhoublue/blueskills.git
cd /要分析的项目目录
```

在 Claude Code 会话内：

```text
/plugin marketplace add /absolute/path/to/blueskills
/plugin install investigate-project@blueskills
/reload-plugins
```

非交互：

```bash
claude plugin marketplace add /absolute/path/to/blueskills
claude plugin install investigate-project@blueskills
```

> 与方式一的区别只是 marketplace 的**来源**不同，安装后的命名空间、调用方式完全一致：仍然是 `investigate-project@blueskills`、`/investigate-project:report-features`。

---

## 方式三：本地开发模式（无需安装）

适合：你正在改插件源码，希望"改完立刻看到效果"。

```bash
cd /要分析的项目目录
claude --plugin-dir /absolute/path/to/blueskills/plugins/investigate-project
```

启动后：

```text
/investigate-project:report-features
```

特点：

- 改完源码运行 `/reload-plugins` 即可热加载，无需重启。
- 不会写入用户全局配置，退出会话即"卸载"。
- 与已安装的同名插件并存时，本地副本在该会话中优先生效，可用于调试已发布版本。

---

## 安装后的使用

无论用哪种方式安装，最终命令一致。**必须先 `cd` 到待分析项目根目录**再启动 `claude`，执行：

```text
/investigate-project:report-features
```

**产物位置**：skill 阶段 0 会在**当前工作目录**下创建 `analysis-report/`（绝对路径会在对话里打印一行确认）。若你在插件源码仓库 `blueskills` 里运行 skill 而未 cd 到目标项目，报告会误写到插件目录——这不是 bug，而是 cwd 不对。

完整执行流程与产出目录见仓库根 [`README.md`](../README.md) 的「使用方式」一节，详细设计见 [`docs/superpowers/specs/2026-06-03-blueskills-plugin-design.md`](./superpowers/specs/2026-06-03-blueskills-plugin-design.md)。

## 从旧版迁移

| 旧 | 新 |
| --- | --- |
| `weizhoublue/blueskills`（历史 analyze-code 仓库） | `weizhoublue/blueskills` |
| `investigate-project@blueskills`（历史命名） | `investigate-project@blueskills` |
| `/investigate-project:report-features`（历史 analyze-codebase） | `/investigate-project:report-features` |

若曾安装旧 marketplace `analyze-code` 或 `investigate-project@analyze-code`：

```text
/plugin marketplace remove analyze-code
/plugin uninstall investigate-project@analyze-code
/plugin marketplace add weizhoublue/blueskills
/plugin install investigate-project@blueskills
/reload-plugins
```

斜杠命令：`/investigate-project:report-features`（plugin 名 ≠ marketplace 名，勿使用 `/blueskills:…`）。

---

## 安装范围（scope）

`/plugin install` 默认安装到 user scope；如需指定其他范围：

| Scope | 含义 | 推荐场景 |
| --- | --- | --- |
| `user`（默认） | 仅你本人，所有项目可见 | 个人长期使用 |
| `project` | 写入仓库 `.claude/settings.json`，团队成员信任项目后会被提示安装 | 团队共享 |
| `local` | 仅你本人，仅当前仓库 | 临时实验 |

非交互指定 scope：

```bash
claude plugin install investigate-project@blueskills --scope project
```

要让团队成员**信任你的业务仓库时被自动提示安装**，在该仓库的 `.claude/settings.json` 加入：

```json
{
  "extraKnownMarketplaces": {
    "blueskills": {
      "source": {
        "source": "github",
        "repo": "weizhoublue/blueskills"
      }
    }
  },
  "enabledPlugins": {
    "investigate-project@blueskills": true
  }
}
```

---

## 常用维护命令

会话内：

```text
/plugin                                       # 打开插件管理 TUI（Discover / Installed / Marketplaces / Errors）
/plugin marketplace list                      # 列出已添加的 marketplace
/plugin marketplace update blueskills       # 刷新 marketplace 目录、拉取新版本
/plugin marketplace remove blueskills       # 移除 marketplace（会同时卸载来自它的插件）
/plugin disable investigate-project@blueskills    # 仅禁用、不卸载
/plugin enable  investigate-project@blueskills
/plugin uninstall investigate-project@blueskills
/reload-plugins                               # 不重启会话，立刻应用插件变更
```

非交互（脚本 / CI）：

```bash
claude plugin marketplace add    weizhoublue/blueskills
claude plugin install            investigate-project@blueskills
claude plugin marketplace update blueskills
claude plugin uninstall          investigate-project@blueskills
```

校验 marketplace / plugin 清单是否合法（本仓库根目录执行）：

```bash
claude plugin validate .
# Validating marketplace manifest: …/marketplace.json
# ✔ Validation passed
```

---

## 版本与自动更新

本仓库当前的版本来源（Claude Code 解析顺序）：

1. `plugins/investigate-project/.claude-plugin/plugin.json` 的 `version` 字段（当前是 `0.1.0`） →
2. marketplace 条目里的 `version`（未设） →
3. 否则使用 git commit SHA。

因此**只要不动 `plugin.json` 的 `version`，推新 commit 不会触发已有用户的更新**。发布新版本时请同步提升 `plugin.json` 的 `version`。

第三方 marketplace（包括本仓库）默认**关闭自动更新**。如需为团队默认开启，可在管理设置的 `extraKnownMarketplaces` 条目上设 `"autoUpdate": true`；或个人在 `/plugin` → Marketplaces 中手动切换。

---

## 故障排查

| 现象 | 处理 |
| --- | --- |
| `/plugin` 命令不存在 | 升级 Claude Code（见文首），重启终端 |
| `plugin not found in any marketplace` | `/plugin marketplace update blueskills` 刷新；或确认已先 `add` 再 `install` |
| 安装成功但 `/investigate-project:report-features` 找不到 | 执行 `/reload-plugins`；若仍无效则 `/plugin` → Errors 标签看具体报错 |
| 修改了本地插件源码但没生效 | `/reload-plugins`；如果是 `--plugin-dir` 启动，直接重新启动 `claude --plugin-dir …` |
| 私有仓库后台自动更新失败 | 在 shell 设置 `GITHUB_TOKEN` / `GH_TOKEN`（GitLab/Bitbucket 对应变量见上文） |
| 完全离线环境 | `export CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE=1` 保留旧缓存；或用 `CLAUDE_CODE_PLUGIN_SEED_DIR` 预填充 |
| 插件缓存损坏 / skill 不出现 | `rm -rf ~/.claude/plugins/cache`，重启 Claude Code 后重新安装 |

---

## 参考

- 创建插件：<https://code.claude.com/docs/zh-CN/plugins>
- 创建并分发 marketplace：<https://code.claude.com/docs/zh-CN/plugin-marketplaces>
- 发现与安装预制插件：<https://code.claude.com/docs/en/discover-plugins>
- 本插件设计文档：[`docs/superpowers/specs/2026-06-03-blueskills-plugin-design.md`](./superpowers/specs/2026-06-03-blueskills-plugin-design.md)
