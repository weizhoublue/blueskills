# 安装

## 安装  investigate-project

对当前目录下的开源项目生成功能分析报告

安装

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


claude code 中使用提示词触发生成， 会在当前目录下创建 `analysis-report/`

```text
/investigate-project:report-features
```

## 安装 audit（审计已合入 PR）

在**目标仓库根目录**、**缺省分支**（如 `main`）下使用：

```text
/plugin marketplace add weizhoublue/blueskills
/plugin install audit@blueskills
/reload-plugins
```

```text
/audit:audit-merged-pr https://github.com/OWNER/REPO/pull/123
```

- 需要已安装并登录 `gh`
- 最终审计报告仅输出到 stdout；中间产物在系统临时目录，默认结束后删除
- 调试可设置环境变量 `AUDIT_KEEP_TMP=1` 保留临时目录

卸载

```text
/plugin marketplace remove analyze-code
/plugin uninstall investigate-project@analyze-code
/plugin marketplace add weizhoublue/blueskills
/plugin install investigate-project@blueskills
/reload-plugins
```

