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

卸载

```text
/plugin marketplace remove analyze-code
/plugin uninstall investigate-project@analyze-code
/plugin marketplace add weizhoublue/blueskills
/plugin install investigate-project@blueskills
/reload-plugins
```

