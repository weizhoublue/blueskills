# Design Spec: GitHub Trend Skill — MemPalace 替换为 history.txt

## 1. 背景与问题

当前 `plugins/news/skills/github-trend/SKILL.md` 使用 **MemPalace MCP** 完成两项职责：

1. **Step 1.2 历史过滤**：`mempalace_search` 查询 URL 是否已分析，命中则剔除。
2. **Step 3 写入记录**：`mempalace_diary_write` 将分析成功的 URL 写入 MemPalace。

这带来以下问题：

- MemPalace MCP 需要启动与连通性校验（Step 0 最多等待 1 分钟），增加失败面与执行延迟。
- 读写依赖外部 MCP 服务，不如本地文件操作简单、可预测。
- 用户无法直接查看或编辑历史记录。

## 2. 已确认的产品决策

| 决策项 | 选择 |
|--------|------|
| 历史存储方式 | 本地文本文件，每行一个 URL |
| 默认文件路径 | 主 Agent 启动 skill 时 **CWD** 下的 `history.txt` |
| 路径覆盖 | 用户可在提示词中指定，如「历史文件用 `./my-history.txt`」 |
| 文件不存在 | **终止流程**，Step 4 输出失败报告（用户须预先创建文件） |
| 读取方式 | `grep -Fxq "$url" "$HISTORY_FILE"` 整行精确匹配 |
| 写入范围 | 仅**分析成功**的项目（与现 MemPalace 行为一致） |
| 写入时机 | Step 3 批量追加（Step 2 全部完成后，禁止分析过程中写入） |
| 写入方式 | `echo "$url" >> "$HISTORY_FILE"` |
| URL 格式 | `https://github.com/<owner>/<repo>` 小写，每行一个，无空行/注释 |
| 变更范围 | 仅修改 `plugins/news/skills/github-trend/SKILL.md` |

## 3. 方案对比

| 方案 | 说明 | 结论 |
|------|------|------|
| A | `grep`/`echo` 替换 MemPalace，保留现有四步结构 | **采用** |
| B | 去掉 Step 1.2，在 Step 2 分析前逐条 grep | 可能多余浏览器访问，结构变更大 |
| C | Step 0 读入内存做字符串匹配 | 不符合 grep 要求，大文件占上下文 |

## 4. 配置与变量

### 4.1 新增全局变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `HISTORY_FILE` | `<CWD>/history.txt` | 历史记录文件路径；用户提示词可覆盖 |

### 4.2 Step 0 变更

**新增**：

1. 解析 `HISTORY_FILE`（默认 CWD 下 `history.txt`；用户提示词指定时使用用户路径）。
2. 校验 `HISTORY_FILE` **必须存在**；不存在则跳 Step 4 输出失败报告并终止。

**删除**：

- Step 0 第 3 点「确认 MemPalace MCP 可用」整段。

**不变**：

- 获取当前真实时间、检查 `agent-browser`、创建 `TMP_DIR` 等逻辑保持原样。

### 4.3 移除内容

- 「### MemPalace MCP 使用」整节（含 `mempalace_search`、`mempalace_diary_write` 及固定参数说明）。
- 全流程中所有 MemPalace MCP 引用与连通性校验。

## 5. Step 1.2：history 历史过滤

**章节重命名**：`1.2 MemPalace 历史过滤` → `1.2 history 历史过滤`

对每个采集到的 URL（已小写、去重）串行执行：

```bash
grep -Fxq "$url" "$HISTORY_FILE"
```

| 退出码 | 含义 | 归类 |
|--------|------|------|
| `0` | 命中 | `## 剔除已分析项目` |
| `1` | 未命中 | `## 待分析项目` |
| 其他 | grep 异常 | 记入 `## 采集困难与统计`，该 URL 暂归入待分析 |

**约束**：

- 必须严格完成本步骤，不允许跳过。
- 不再因 MemPalace 不可用而终止；MemPalace 相关失败条件全部移除。
- `grep -F` 固定字符串匹配，`-x` 整行匹配，避免部分匹配误判。

**`collect_result.md` 输出格式不变**，仅数据来源从 MemPalace 改为文件 grep。

## 6. Step 3：写入 history

**章节重命名**：`第 3 步：写入 MemPalace` → `第 3 步：写入 history`

由主 Agent 执行（不委派子 Agent）：

1. 从 `analyze_result.md` 的 `## 分析报告` 提取分析成功的 URL 列表。
2. 对每个 URL 串行追加：

```bash
echo "$url" >> "$HISTORY_FILE"
```

3. 生成 `history_result.md` 文本（替代原 `mempalace_result.md`）。若 `debug=true`，落盘至 `TMP_DIR/history_result.md`。

```markdown
## 写入摘要
成功写入 history 的项目：
- https://github.com/owner1/repo1

## 写入困难与统计
（写入失败、权限问题等）
```

**写入约束**（与现 MemPalace 一致）：

- 仅分析成功的项目写入。
- 禁止写入分析失败、Star 不足项目。
- 禁止在 Step 2 完成前写入（避免 skill 未跑完即标记为已分析，导致下次被误过滤）。

## 7. Step 4：报告整合

**「执行困难与调试统计」** 调整：

- 移除 MemPalace 相关描述。
- 改为：`history 文件操作失败、CLI 操作失败等`。
- 困难与统计拼接来源：`collect_result.md` + `analyze_result.md` + `history_result.md`。

**「剔除已分析项目」** 含义不变：来自 Step 1.2 中 grep 命中的 URL。

## 8. 错误处理

| 场景 | 行为 |
|------|------|
| `HISTORY_FILE` 不存在（Step 0） | 终止流程，Step 4 输出失败报告，说明需先创建该文件 |
| `grep` 异常（Step 1.2） | 记入采集困难与统计，该 URL 暂归入待分析 |
| `echo >>` 失败（Step 3） | 记入 `history_result.md` 写入困难，Step 4 报告中体现；不终止，报告仍正常输出 |
| 待分析列表为空 | 跳过 Step 2、Step 3，直接 Step 4 输出「今日无新项目」 |
| `agent-browser` 不可用 | 不变，终止流程 |

## 9. debug 产物变更

| 变更前 | 变更后 |
|--------|--------|
| `TMP_DIR/mempalace_result.md` | `TMP_DIR/history_result.md` |

`TMP_DIR` 说明中 `mempalace_result.md` 引用同步替换为 `history_result.md`。

## 10. 执行原则补充

- 历史去重与记录**仅通过 `HISTORY_FILE` 完成**，禁止使用 MemPalace MCP。
- `grep` 用于读取判断，`echo >>` 用于写入；禁止用其他方式修改 history 文件。
- URL 写入前必须小写规范化，与文件中已有格式一致。

## 11. 用户首次使用

因「文件不存在则终止」，用户需预先创建 history 文件：

```bash
touch history.txt
```

或在提示词中指定已有路径，例如：`历史文件用 /path/to/my-history.txt`

## 12. 变更范围与不在范围内

**修改**：

- `plugins/news/skills/github-trend/SKILL.md`

**不修改**：

- `README.md` 及其他插件 skill
- 既有 design/plan 文档（作为历史记录保留）

## 13. 验收标准

1. SKILL.md 中无 MemPalace MCP 相关引用。
2. Step 0 校验 `HISTORY_FILE` 存在，不存在则终止。
3. Step 1.2 使用 `grep -Fxq` 做历史过滤，输出 `collect_result.md` 格式不变。
4. Step 3 使用 `echo >>` 批量追加分析成功的 URL，生成 `history_result.md`。
5. Step 4 报告整合引用 `history_result.md`，困难统计不含 MemPalace 描述。
6. 分析失败、Star 不足项目不写入 history 文件。
