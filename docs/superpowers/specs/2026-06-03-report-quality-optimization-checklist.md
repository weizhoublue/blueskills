# 报告质量优化清单（落地版）

- 日期：2026-06-03
- 状态：**B1 + B2 + B3 已写入 agent / SKILL / 脚本**
- 上游：[`2026-06-02-report-depth-and-quality-agent-design.md`](./2026-06-02-report-depth-and-quality-agent-design.md) §13

## 深度标准（四维）

1. **多层因果**：L1 情境 → L2 后果 → [L3] → L4 机制 → L5 用户结果
2. **铺垫**：`contrast` / 无本项目时的后果
3. **术语**：专名首现解释
4. **证据**：refs 与主张对齐

## 红线

- **R15**：`overview.md`、`features/*.md` 禁止 markdown 表格
- **R16**：禁止为过关仅加长 narrative

## 已改文件

| 文件 | 内容 |
| --- | --- |
| `agents/report-quality-challenger.md` | 多层因果、术语、metrics、overview-md、integrations 深度 |
| `agents/report-writer.md` | overview-md-final、§9 与 *-final 联动 |
| `agents/project-scout.md` | read_budget 45、causal 字段 |
| `agents/feature-digger.md` | read_budget、浅/深样例、addressed_by_principle_dims |
| `agents/integration-analyst.md` | integration_context、集成叙事深度 |
| `skills/report-features/SKILL.md` | 1a 预检、大项目预算、6b 强制、三问、validate 门禁 |
| `scripts/validate-analysis-report.sh` | 半自动校验 |
| `docs/.../2026-06-02-report-depth-and-quality-agent-design.md` | §13 v7.1 |

## 未做（刻意）

- `feature-boundary-reviewer`（不负责 overview 深度）
- 重跑示例项目 / 修改仓库根 `README.md`
- `2026-06-03-blueskills-plugin-design.md` 全量合并（仅 v7 设计 doc §13 指向本清单）
