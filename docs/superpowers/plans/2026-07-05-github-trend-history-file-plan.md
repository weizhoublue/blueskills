# GitHub Trend history.txt Replacement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `github-trend` skill 的历史去重与记录从 MemPalace MCP 改为 CWD 下 `history.txt` 文件的 `grep`/`echo` 操作。

**Architecture:** 仅修改 `plugins/news/skills/github-trend/SKILL.md` 编排指令。新增 `HISTORY_FILE` 全局变量；Step 0 校验文件存在；Step 1.2 用 `grep -Fxq` 过滤；Step 3 用 `echo >>` 批量追加；移除全部 MemPalace 引用。

**Tech Stack:** Claude Code plugin SKILL.md、agent-browser CLI、shell（grep/echo）

**Spec:** [docs/superpowers/specs/2026-07-05-github-trend-history-file-design.md](../specs/2026-07-05-github-trend-history-file-design.md)

## Global Constraints

- 默认 `HISTORY_FILE` = 主 Agent 启动 skill 时 CWD 下的 `history.txt`；用户提示词可覆盖（如「历史文件用 `./my-history.txt`」）
- `HISTORY_FILE` 不存在 → Step 0 终止流程，Step 4 输出失败报告
- 读取：`grep -Fxq "$url" "$HISTORY_FILE"` 整行精确匹配
- 写入：仅分析成功项目；Step 3 批量 `echo "$url" >> "$HISTORY_FILE"`；禁止 Step 2 完成前写入
- URL 格式：`https://github.com/<owner>/<repo>` 小写，每行一个
- 禁止 MemPalace MCP；禁止用其他方式修改 history 文件
- 变更范围：仅 `plugins/news/skills/github-trend/SKILL.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `plugins/news/skills/github-trend/SKILL.md` | Modify | 唯一实现目标：全局变量、工具规范、Step 0–4 编排、执行原则 |
| `docs/superpowers/specs/2026-07-05-github-trend-history-file-design.md` | Reference | 设计依据（已完成） |

---

### Task 1: 新增 `HISTORY_FILE` 并更新 debug 产物说明

**Files:**
- Modify: `plugins/news/skills/github-trend/SKILL.md:18-24`

**Interfaces:**
- Produces: 全局变量 `HISTORY_FILE`；`TMP_DIR` 说明中 `history_result.md` 替代 `mempalace_result.md`

- [ ] **Step 1: 在「配置与全局变量」节追加 `HISTORY_FILE` 说明**

在 `TMP_DIR` 段落之后（第 22 行后）插入：

```markdown
`HISTORY_FILE`: 历史记录文件路径。默认为主 Agent 启动 skill 时**当前工作目录（CWD）**下的 `history.txt`。用户如在提示词中指定历史文件路径（如「历史文件用 `./my-history.txt`」「history 文件 `/path/to/history.txt`」），则使用用户指定路径。
```

- [ ] **Step 2: 更新 `TMP_DIR` debug 产物列表**

将第 24 行：

```
**`TMP_DIR` 仅用于 `debug=true` 时保存中间产物**（`collect_result.md`、`analyze_result.md`、`mempalace_result.md` 及各项目详情文件）。
```

改为：

```
**`TMP_DIR` 仅用于 `debug=true` 时保存中间产物**（`collect_result.md`、`analyze_result.md`、`history_result.md` 及各项目详情文件）。
```

- [ ] **Step 3: 验证 `HISTORY_FILE` 已写入**

```bash
rg -n "HISTORY_FILE" plugins/news/skills/github-trend/SKILL.md
```

Expected: 至少 1 处匹配（本 Task 新增）；Task 4 完成后应 ≥ 3 处。

- [ ] **Step 4: 验证 debug 产物无 `mempalace_result`**

```bash
rg -n "mempalace_result" plugins/news/skills/github-trend/SKILL.md
```

Expected: 仍有匹配（Step 3 节尚未改）；Task 4 完成后应零匹配。

- [ ] **Step 5: Commit**

```bash
git add plugins/news/skills/github-trend/SKILL.md
git commit -m "refactor(news): add HISTORY_FILE variable to github-trend skill"
```

---

### Task 2: 替换「MemPalace MCP 使用」为「history 文件使用」

**Files:**
- Modify: `plugins/news/skills/github-trend/SKILL.md:61-93`

**Interfaces:**
- Produces: `### history 文件使用` 章节，含 grep 读取与 echo 写入规范

- [ ] **Step 1: 删除「### MemPalace MCP 使用」整节（第 61–93 行）**

- [ ] **Step 2: 在原位置插入「### history 文件使用」**

```markdown
### history 文件使用

`HISTORY_FILE` 用于**读取**历史记录（去重）、**追加**已分析仓库 URL。

**读写时机（强约束）**
- **读取**：仅第 1.2 步历史过滤时，对每个 URL 执行 `grep -Fxq "$url" "$HISTORY_FILE"`
- **写入**：仅第 3 步、第 2 步全部分析完成之后、保存最终报告与 stdout 输出**之前**，由主 Agent 对**分析成功**的项目执行 `echo "$url" >> "$HISTORY_FILE"`
- **禁止**在采集阶段或分析完成前写入 history 文件（避免 skill 未跑完即标记为已分析，导致下次被误过滤）

**文件格式**
- 每行一个 URL：`https://github.com/<owner>/<repo>`（小写）
- 禁止空行、注释或其他格式

**常见操作**

1. **查询是否已分析**（去重用，Step 1.2）：
   ```bash
   grep -Fxq "https://github.com/owner/repo" "$HISTORY_FILE"
   ```
   - 退出码 `0`：命中，归入「剔除已分析项目」
   - 退出码 `1`：未命中，归入「待分析项目」
   - 其他退出码：grep 异常，记入采集困难与统计，该 URL 暂归入待分析

2. **追加已分析记录**（仅 Step 3，且该项目 Step 2 分析成功时）：
   ```bash
   echo "https://github.com/owner/repo" >> "$HISTORY_FILE"
   ```
   **分析失败的项目禁止写入。Star 不足的项目禁止写入。**
```

- [ ] **Step 3: 验证 MemPalace 工具章节已移除**

```bash
rg -n "mempalace_search|mempalace_diary_write|MemPalace MCP 使用" plugins/news/skills/github-trend/SKILL.md
```

Expected: 无匹配

- [ ] **Step 4: 验证 history 章节存在**

```bash
rg -n "history 文件使用|grep -Fxq|echo.*HISTORY_FILE" plugins/news/skills/github-trend/SKILL.md
```

Expected: 至少 3 处匹配

- [ ] **Step 5: Commit**

```bash
git add plugins/news/skills/github-trend/SKILL.md
git commit -m "refactor(news): replace MemPalace section with history file usage in github-trend"
```

---

### Task 3: 更新 Step 0 初始化（校验 HISTORY_FILE，移除 MemPalace 检查）

**Files:**
- Modify: `plugins/news/skills/github-trend/SKILL.md:100-107`

**Interfaces:**
- Consumes: `HISTORY_FILE`（Task 1）
- Produces: Step 0 第 3 点改为 history 文件存在性校验

- [ ] **Step 1: 替换 Step 0 第 3 点**

将第 104 行：

```
3. **确认 MemPalace MCP 可用，刚启动时，该 mcp 需要启动时间，可尝试等待最多 1 min。如果不可用，直接跳到第 4 步，输出一份失败原因解释报告，并终止整个流程**
```

改为：

```
3. **解析并校验 `HISTORY_FILE`**：默认 CWD 下 `history.txt`；用户提示词指定路径时使用用户路径。文件**必须存在**；若不存在，直接跳到第 4 步，输出失败原因解释报告（说明用户须预先创建 history 文件，如 `touch history.txt`），并终止整个流程。
```

- [ ] **Step 2: 验证 Step 0 无 MemPalace**

```bash
rg -n "MemPalace" plugins/news/skills/github-trend/SKILL.md | rg "第 0 步|100|101|102|103|104|105|106|107" || true
rg -n "MemPalace" plugins/news/skills/github-trend/SKILL.md
```

Expected: Step 0 区域内（约 100–107 行）无 MemPalace；全文件 MemPalace 匹配数应减少（Step 1.2/3/4 尚未改时仍可能有残留）

- [ ] **Step 3: 验证 HISTORY_FILE 校验文案存在**

```bash
rg -n "解析并校验.*HISTORY_FILE|touch history.txt" plugins/news/skills/github-trend/SKILL.md
```

Expected: 至少 1 处匹配

- [ ] **Step 4: Commit**

```bash
git add plugins/news/skills/github-trend/SKILL.md
git commit -m "refactor(news): validate HISTORY_FILE in github-trend step 0"
```

---

### Task 4: 更新 Step 1.2 与 Step 3 流程

**Files:**
- Modify: `plugins/news/skills/github-trend/SKILL.md:117-120`
- Modify: `plugins/news/skills/github-trend/SKILL.md:180-196`

**Interfaces:**
- Consumes: `HISTORY_FILE`、history 文件使用规范（Task 2）
- Produces: Step 1.2 grep 过滤；Step 3 echo 写入 + `history_result.md`

- [ ] **Step 1: 替换 Step 1.2 标题与正文**

将 `#### 1.2 MemPalace 历史过滤` 及第 117–120 行正文替换为：

```markdown
#### 1.2 history 历史过滤

对每个采集 URL（已小写、去重）串行执行 `grep -Fxq "$url" "$HISTORY_FILE"`。命中（退出码 0）的 URL 记入 `collect_result.md` 的 `## 剔除已分析项目`；未命中（退出码 1）的记入 `## 待分析项目`；grep 异常（其他退出码）记入 `## 采集困难与统计`，该 URL 暂归入待分析。

**必须严格完成本步骤，不允许跳过。**
```

- [ ] **Step 2: 替换 Step 3 整节（第 180–196 行）**

将 `### 第 3 步：写入 MemPalace` 整节替换为：

```markdown
### 第 3 步：写入 history

由主 Agent 执行（不委派子 Agent）。
1. 主 Agent 提取 `analyze_result.md` 中 `## 分析报告` 下的成功项目 URL 列表。
2. 对每个 URL 串行执行 `echo "$url" >> "$HISTORY_FILE"`（URL 须小写规范化）。
3. 生成并返回 `history_result.md` 文本。若 `debug=true`，落盘至 `TMP_DIR/history_result.md`。

    ```markdown
    ## 写入摘要
    成功写入 history 的项目：
    - https://github.com/owner1/repo1

    ## 写入困难与统计
    （写入失败、权限问题等，由主 Agent 自由发挥编写）
    ```

**必须严格完成本步骤，不允许跳过。若 `echo >>` 失败，在第 4 步报告中体现 history 写入失败，但不终止流程。**
```

- [ ] **Step 3: 验证 Step 1.2 / Step 3 无 MemPalace**

```bash
rg -n "MemPalace|mempalace" plugins/news/skills/github-trend/SKILL.md
```

Expected: 无匹配（若 Step 4 尚未执行，可能仅剩 Step 4 / 执行原则中的 MemPalace）

- [ ] **Step 4: 验证 grep/echo 命令存在**

```bash
rg -n "grep -Fxq|echo.*>>.*HISTORY_FILE|history_result\.md" plugins/news/skills/github-trend/SKILL.md
```

Expected: 至少 4 处匹配

- [ ] **Step 5: Commit**

```bash
git add plugins/news/skills/github-trend/SKILL.md
git commit -m "refactor(news): use grep/echo for history in github-trend steps 1.2 and 3"
```

---

### Task 5: 更新 Step 4 报告整合与执行原则

**Files:**
- Modify: `plugins/news/skills/github-trend/SKILL.md:223-225`
- Modify: `plugins/news/skills/github-trend/SKILL.md:229-237`

**Interfaces:**
- Consumes: `history_result.md`（Task 4）
- Produces: Step 4 困难统计文案；执行原则中 history 约束

- [ ] **Step 1: 更新 Step 4「执行困难与调试统计」段落**

将第 223–225 行：

```
    ## 执行困难与调试统计
    如遇 MemPalace 操作失败、CLI 操作失败等事件
    按顺序拼接 collect_result.md、analyze_result.md、mempalace_result.md 中的困难与统计内容
```

改为：

```
    ## 执行困难与调试统计
    如遇 history 文件操作失败、CLI 操作失败等事件
    按顺序拼接 collect_result.md、analyze_result.md、history_result.md 中的困难与统计内容
```

- [ ] **Step 2: 在「执行原则」末尾追加 history 约束**

在第 237 行（agent-browser 全路径原则）之后追加：

```markdown
- 历史去重与记录**仅通过 `HISTORY_FILE` 完成**，禁止使用 MemPalace MCP
- `grep` 用于读取判断，`echo >>` 用于写入；禁止用其他方式修改 history 文件
- URL 写入前必须小写规范化，与 history 文件中已有格式一致
```

- [ ] **Step 3: 全文件 MemPalace 清零验证**

```bash
rg -n -i "mempalace|MemPalace" plugins/news/skills/github-trend/SKILL.md
```

Expected: 无匹配

- [ ] **Step 4: 全文件 mempalace_result 清零验证**

```bash
rg -n "mempalace_result" plugins/news/skills/github-trend/SKILL.md
```

Expected: 无匹配

- [ ] **Step 5: Commit**

```bash
git add plugins/news/skills/github-trend/SKILL.md
git commit -m "refactor(news): update github-trend step 4 and principles for history file"
```

---

### Task 6: 验收对照 spec §13

**Files:**
- Verify: `plugins/news/skills/github-trend/SKILL.md`

- [ ] **Step 1: 运行验收脚本**

```bash
cd /Users/weizhoublue/Documents/git/blueskills

echo "=== 1. No MemPalace references ==="
rg -i "mempalace" plugins/news/skills/github-trend/SKILL.md && exit 1 || echo "PASS"

echo "=== 2. HISTORY_FILE in config ==="
rg -n "HISTORY_FILE" plugins/news/skills/github-trend/SKILL.md | head -5

echo "=== 3. Step 0 file existence check ==="
rg -n "必须存在|touch history.txt" plugins/news/skills/github-trend/SKILL.md

echo "=== 4. grep filter in 1.2 ==="
rg -n "1\.2 history|grep -Fxq" plugins/news/skills/github-trend/SKILL.md

echo "=== 5. echo append in step 3 ==="
rg -n "第 3 步：写入 history|echo.*HISTORY_FILE" plugins/news/skills/github-trend/SKILL.md

echo "=== 6. history_result in step 4 ==="
rg -n "history_result\.md" plugins/news/skills/github-trend/SKILL.md

echo "=== 7. Write constraints (success only, no early write) ==="
rg -n "分析失败的项目禁止写入|禁止在采集阶段或分析完成前写入" plugins/news/skills/github-trend/SKILL.md

echo "ALL CHECKS DONE"
```

Expected: 第 1 项 PASS；第 2–7 项均有匹配输出。

- [ ] **Step 2: 人工抽查 SKILL.md 结构完整性**

确认以下章节仍存在且顺序合理：
- 调用场景
- 配置与全局变量（含 `debug`、`TMP_DIR`、`HISTORY_FILE`）
- 工具使用规范（agent-browser + history 文件使用）
- 执行流程 Step 0–4
- 执行原则

- [ ] **Step 3: Commit（若有验收期微调）**

```bash
git add plugins/news/skills/github-trend/SKILL.md
git commit -m "refactor(news): finalize github-trend history.txt migration"
```

仅当 Step 1–2 发现需微调时执行；否则跳过本 commit。

---

## Spec Coverage Checklist

| Spec § | Requirement | Task |
|--------|-------------|------|
| §2 | 默认 CWD/history.txt，用户可覆盖 | Task 1, 3 |
| §2 | 文件不存在终止 | Task 3 |
| §2 | grep 读取、echo 写入、仅成功项目、Step 3 批量 | Task 2, 4 |
| §4.3 | 移除 MemPalace 整节与引用 | Task 2, 5, 6 |
| §5 | Step 1.2 grep 过滤 | Task 4 |
| §6 | Step 3 echo + history_result.md | Task 1, 4 |
| §7 | Step 4 报告整合 | Task 5 |
| §8 | 错误处理表 | Task 3, 4, 5 |
| §9 | debug 产物更名 | Task 1, 4 |
| §10 | 执行原则 | Task 5 |
| §13 | 验收标准 | Task 6 |
