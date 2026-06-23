# Design Spec: GitHub Trend Skill — Star 过滤下沉与剔除分类

## 1. 背景与问题

当前 `plugins/news/skills/github-trend/SKILL.md` 存在两处体验与效率问题：

### 问题 1：重复页面加载

- Step 1.1 合并两源趋势榜后最多 40 个候选 URL。
- Step 1.3 要求采集子 Agent 用 agent-browser **逐个**访问仓库页读取 Star 数。
- Step 2 分析子 Agent 第一步同样访问仓库页。

同一仓库页被加载两次，浪费 Token、延长执行时间，且增加超时与反爬风险。

### 问题 2：剔除原因不可辨

最终报告「## 剔除分析项目」仅列 URL，且禁止附加说明。用户无法区分项目是因 MemPalace 历史命中被剔除，还是因 Star 不足被剔除。

## 2. 已确认的产品决策

| 决策项 | 选择 |
|--------|------|
| Star 过滤时机 | 从 Step 1.3 移至 Step 2 分析子 Agent 门禁 |
| Star < 5000 | 跳过详细分析，不输出项目报告块，归入 `excluded_urls.star_insufficient` |
| Star 无法解析 | 视同 Star 不足，同上处理，并上报 `[warning]` 困难 |
| 报告头部计数器 | 仅保留「总共分析项目」「分析失败项目」；移除 `after_stars_count`、`analyzed_count` |
| 采集阶段计数器 | 保留 `merged_count`、`after_history_count` |
| 剔除报告格式 | 分两节：`## 剔除已分析项目` 与 `## 剔除 star 不足项目` |
| 方案选择 | 方案 A：Star 门禁内嵌现有分析子 Agent（不新增子 Agent 类型） |

## 3. 方案对比（摘要）

| 方案 | 说明 | 结论 |
|------|------|------|
| A | 分析子 Agent 访问页面后先读 Star，不满足则 `skipped_low_stars` | **采用** |
| B | Step 2 拆为轻量预检 + 深度分析两个子 Agent | 复杂度高、收益有限 |
| C | 采集阶段用 GitHub API 批量取 Star | 违背 agent-browser 优先原则 |

## 4. Step 0：计数器清理

**变更前：**

```
merged_count、after_history_count、after_stars_count、analyzed_count
```

**变更后：**

```
merged_count、after_history_count
```

- `after_stars_count`：删除（Star 过滤不再发生在采集阶段）。
- `analyzed_count`：删除（仅在 Step 0 初始化处提及，从未接入报告逻辑；最终报告由 Step 4 实时统计 `success` / `failed` 数量）。

## 5. Step 1：采集阶段

### 5.1 删除 Step 1.3（Star 数量过滤）

采集子 Agent 流程变为：

1. **1.1** 趋势榜采集（不变）
2. **1.2** MemPalace 历史过滤（不变）
3. **1.4** 输出候选列表（原编号，内容调整）

### 5.2 `excluded_urls` 数据结构

采集阶段由主 Agent / 采集子 Agent 初始化：

```json
{
  "history_analyzed": [],
  "star_insufficient": []
}
```

- Step 1.2 将 MemPalace 命中的 URL 填入 `history_analyzed`。
- `star_insufficient` 在采集阶段保持空数组，由 Step 2 主 Agent 追加。

### 5.3 Step 1.4 采集结果摘要

```markdown
## 采集结果

- merged_count: X
- after_history_count: Y
- final_urls:
  - https://github.com/owner1/repo1
- excluded_urls:
  - history_analyzed:
    - https://github.com/owner3/repo3
  - star_insufficient: （空，待 Step 2 填充）
```

### 5.4 提前终止条件

- **变更前：** `after_stars_count == 0` → 跳第 4 步
- **变更后：** `after_history_count == 0` → 跳第 4 步（仍输出剔除分类与执行困难汇总；跳过第 3 步 MemPalace 写入）

### 5.5 debug 落盘

- **删除：** `TMP_DIR/collect/filtered_stars.json`
- **保留：** `filtered_history.json`（`removed` 字段对应 `history_analyzed`）
- **可选新增：** `TMP_DIR/collect/excluded_urls.json`（记录分类剔除列表全生命周期快照）

## 6. Step 2：串行分析 + Star 门禁

### 6.1 分析子 Agent 执行顺序

```
1. /usr/sbin/agent-browser 访问 https://github.com/<owner>/<repo>
2. 读取 star 数
   - star ≥ 5000 → 继续步骤 3
   - star < 5000 或无法可靠解析 → 返回 skipped_low_stars，不继续
3. 从 README、About、仓库描述等公开页面信息提取（原有逻辑）
```

### 6.2 `analysis_status` 取值

| status | 含义 | 报告 | MemPalace |
|--------|------|------|-----------|
| `success` | 正常完成分析 | 计入「总共分析项目」 | Step 3 写入 |
| `failed` | 分析失败 | 计入「分析失败项目」，输出失败块 | 不写入 |
| `skipped_low_stars` | Star 不足或无法解析 | 不输出项目块 | 不写入 |

### 6.3 `skipped_low_stars` 子 Agent 返回格式

```markdown
## 执行结果

- analysis_status: skipped_low_stars
- url: https://github.com/<owner>/<repo>
- stars: 1234（无法解析时写「未知」）

## 执行困难

（无法解析 star 时上报 [warning]，stage 为 `2_analyze`；无困难时写「无」）
```

主 Agent 收到后：

1. 将 URL 追加到 `excluded_urls.star_insufficient`
2. 不拼接项目报告块
3. 继续下一个 URL

### 6.4 困难上报 stage

- **删除：** `1.3_stars`
- Star 相关困难统一使用 `2_analyze`

## 7. Step 4：报告格式变更

### 7.1 报告头部（不变，实时统计）

```markdown
# GitHub Trending 日报

生成时间: YYYY.MM.DD（本地时区）
总共分析项目：xx 个    ← analysis_status == success 的数量
分析失败项目：yy 个    ← analysis_status == failed 的数量
```

`skipped_low_stars` 不计入上述两项。

### 7.2 剔除部分（替换原「## 剔除分析项目」）

```markdown
## 剔除已分析项目

（MemPalace 历史命中；无则写：无）

- https://github.com/owner1/repo1

## 剔除 star 不足项目

（Star < 5000 或无法解析；无则写：无）

- https://github.com/owner2/repo2
```

规则：

- 每节只列 URL，不加额外说明文字
- 两节始终输出（为空时写「无」）
- **不含** Step 2 `failed` 项目（失败项目仍在正文以失败块展示）

## 8. 连带修改清单

| 位置 | 变更 |
|------|------|
| 困难上报 `stage` 枚举（第 52 行附近） | 删除 `1.3_stars` |
| Step 0 计数器初始化 | 仅 `merged_count`、`after_history_count` |
| Step 1.3 整节 | 删除 |
| Step 1.4 `excluded_urls` | 改为分类结构 |
| 异常处理表「过滤后名单为空」 | 改为 `after_history_count == 0` |
| 原设计 spec 目录结构中的 `filtered_stars.json` | 标记为已废弃（本 spec 生效后） |

## 9. 不在本次范围

- 不修改 Star 阈值（仍为 5000）
- 不引入 GitHub API 取 Star
- 不将 Step 2 改为并行
- 不修改 MemPalace 读写时机
- 不修改分析报告正文格式（`success` / `failed` 块）

## 10. 验收标准

1. 采集阶段不再对候选 URL 逐个访问仓库页读 Star（仅访问 OSS Insight 与 GitHub Trending 两个榜单页）。
2. 每个进入 Step 2 的 URL 最多加载一次仓库页；Star 不满足时无 README 深挖。
3. 最终报告可区分「已分析剔除」与「star 不足剔除」两类 URL。
4. 报告头部无 `after_stars_count`；「总共分析项目」「分析失败项目」统计正确。
5. `skipped_low_stars` 项目不写入 MemPalace，不出现在正文分析块中。
