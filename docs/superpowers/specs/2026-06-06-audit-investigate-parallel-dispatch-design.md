# audit / investigate 阶段 2 真并行委派设计

**日期：** 2026-06-06  
**状态：** 已实施  
**范围：** `plugins/audit`（skill：`review`）、`plugins/investigate-issue`（skill：`investigate`）

---

## 背景

实测 audit 阶段 2 出现**伪并行**：主编排依次 `Agent(2a) → Done → Thought → Agent(2b) → …`，墙钟时间接近各 scanner 之和而非 `max`。

SKILL 虽写「并行」「单条消息内 N 次 Task」，但缺少 HARD-GATE、反模式与进入阶段 3 前的委派自检，主编排默认倾向串行等待。

---

## 目标

1. 强制主编排在**同一轮 assistant 回复**内发起阶段 2 全部 `Task`。
2. 明确禁止「等待 Done 后再派下一个 scanner」。
3. audit 与 investigate 采用同构委派协议（Task 数量分别为 3/4 与 2）。

---

## 已实施变更

| 文件 | 变更 |
|------|------|
| `plugins/audit/skills/review/SKILL.md` | `## 阶段 2 并行委派（HARD-GATE）`、委派前准备、阶段 2 自检、执行约束第 12 条 |
| `plugins/investigate-issue/skills/investigate/SKILL.md` | 阶段 2 HARD-GATE（两次 Task）、自检 |
| `plugins/audit/.claude-plugin/plugin.json` | 0.8.1 |
| `plugins/investigate-issue/.claude-plugin/plugin.json` | 0.8.2 |

---

## HARD-GATE 摘要

**必须：** 阶段 1 完成后先组装共享 prompt，再同一轮回复内发起全部 Task。

**禁止：**

- Task(2a) 等待 Done 后再 Task(2b/…)
- 任一 scanner 未返回前进入下一阶段合并/综合
- 阶段 2 委派轮次中的中间总结（「2a 已完成，开始 2b」）

**进入下一阶段前自检：**

- 已在同一轮回复发起全部 Task
- 全部 scanner 输出已收齐
- 未在收齐前做合并/质检/撰写

---

## 验收

**静态：**

```bash
rg -n 'HARD-GATE|等待 Done|同一轮' plugins/audit/skills/review/SKILL.md
rg -n 'HARD-GATE|单条消息内|同一轮' plugins/investigate-issue/skills/investigate/SKILL.md
```

**动态（人工）：**

- transcript 中阶段 2 应为同一 turn 内多个 Agent/Task 启动
- 墙钟时间应接近 `max(scanners)` 而非完全累加

---

## 非目标

- 不引入 shell 并行启动器或 merger sub-agent
- 不修改各 scanner 的 checklist 内容
- 不保证非 Cursor/Claude Task 环境的并行语义
