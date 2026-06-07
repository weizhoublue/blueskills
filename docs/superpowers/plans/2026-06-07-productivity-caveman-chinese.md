# productivity / caveman-chinese 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `productivity` 插件与 `caveman-chinese` skill：约束当次中文输出为更短、更直接表达；支持显式改写与风格双模式。

**Architecture:** 单文件 `SKILL.md`（≤80 行）承载全部规则；`plugin.json` + marketplace 注册；无 sub-agent、无脚本、无 `examples.md`。验收靠 `wc`/`rg` 结构校验 + 3 段人工试写。

**Tech Stack:** Claude Code marketplace、plugin manifest、`SKILL.md`（YAML frontmatter + Markdown 表）。

**Reference:** [`docs/superpowers/specs/2026-06-07-productivity-caveman-chinese-design.md`](../specs/2026-06-07-productivity-caveman-chinese-design.md)

**Conventions:**

- Plugin 内 SKILL **正文中文**；frontmatter `name` 英文 kebab-case，`description` 中文且 ≤150 字。
- 无 pytest；用 **`wc -l`** + **`rg`** 做结构校验。
- skill 正文须践行自身压缩原则（短句、表格式、无废话）。

---

## 文件结构（决策已锁定）

| 路径 | 职责 | Task |
|------|------|------|
| `.claude-plugin/marketplace.json` | 注册 `productivity` | 1 |
| `plugins/productivity/.claude-plugin/plugin.json` | 插件 manifest | 1 |
| `plugins/productivity/skills/caveman-chinese/SKILL.md` | 唯一规则文件 | 2 |
| `docs/superpowers/specs/2026-06-07-productivity-caveman-chinese-design.md` | 标记已实现 | 3 |

---

## Task 1: Marketplace 与 plugin manifest

**Files:**

- Modify: `.claude-plugin/marketplace.json`
- Create: `plugins/productivity/.claude-plugin/plugin.json`

- [ ] **Step 1: 创建目录**

```bash
mkdir -p plugins/productivity/.claude-plugin plugins/productivity/skills/caveman-chinese
```

- [ ] **Step 2: 写入 `plugins/productivity/.claude-plugin/plugin.json`**

```json
{
  "name": "productivity",
  "displayName": "Productivity",
  "version": "0.1.0",
  "description": "中文表达压缩；caveman-chinese skill",
  "keywords": ["writing", "chinese", "concise", "productivity"],
  "license": "MIT"
}
```

- [ ] **Step 3: 在 `marketplace.json` 的 `plugins` 数组末尾追加**

```json
    {
      "name": "productivity",
      "source": "./plugins/productivity",
      "description": "Chinese expression compression via /productivity:caveman-chinese; concise output style and explicit rewrite mode."
    }
```

- [ ] **Step 4: JSON 校验**

```bash
python3 -c "
import json
m=json.load(open('.claude-plugin/marketplace.json'))
names=[p['name'] for p in m['plugins']]
assert 'productivity' in names
p=json.load(open('plugins/productivity/.claude-plugin/plugin.json'))
assert p['name']=='productivity'
print('OK', names)
"
```

Expected: `OK` 且列表含 `productivity`

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/marketplace.json plugins/productivity/.claude-plugin/plugin.json
git commit -m "feat(productivity): add plugin manifest and marketplace entry"
```

---

## Task 2: caveman-chinese SKILL.md

**Files:**

- Create: `plugins/productivity/skills/caveman-chinese/SKILL.md`

- [ ] **Step 1: 写入完整 `SKILL.md`（不得增删区块；可微调措辞但须 ≤80 行）**

```markdown
---
name: caveman-chinese
description: 压缩中文表达。触发：/productivity:caveman-chinese、压缩、精简、简短、去冗余、caveman。仅当次回复。
---

本文件正文须践行下文全部压缩原则。

## 调用场景

**适用**
- 用户要简短中文输出
- 用户提交中文正文要求改写

**不适用**
- 用户未触发本 skill

## 双模式

| 模式 | 判定 | 输出 |
|------|------|------|
| 改写 | 用户提交待处理正文 | 仅压缩后全文，零说明 |
| 风格 | 无待改写正文 | 当次回复全文按规则写 |

持续：仅当次回复。

## 表达原则

| # | 规则 | 操作 |
|---|------|------|
| 1 | 禁低信息量词 | 删：相关、具体、详细、完整、主要、整体、一些、很多、比较、其实、显然、可以看到、我们发现 |
| 2 | 禁口语 | 删：我觉得、感觉、就是说、换句话说、怎么说呢、从我的角度看、这里想表达的是 |
| 3 | 长短语改短 | 进行检查→检查；进行处理→处理；产生影响→影响 |
| 4 | 去重复 | 同一事实/原因/后果/结论只写一次 |
| 5 | 句式压缩 | 解释句→判断句；长条件句→「条件 + 结果」 |

## 保真（HARD-GATE）

- 保留原意、条件、因果、结论、关键细节
- 压缩 ≠ 总结
- 代码、函数名、路径、配置键、API 名、URL、栈、报错原文 — 零改动

## 压缩范围

| 压 | 不压 |
|----|------|
| 段落、标题、列表、表格单元格中文 | fenced code block、反引号内 |
| 说明性引用中文 | 路径、栈、报错原文、技术标识 |

混合中英文：只压中文叙述。

## 边界

- 改写模式代码为主：只压代码外中文
- 丢条件/结论：补回后再输出
- 说明性引用可压；技术标识不动

## 自检

1. 禁词表 + 口语表
2. 条件、因果、结论齐全
3. 代码块、路径、标识符原样

## 样例

| 前 | 后 |
|----|-----|
| 它的主要作用就是对用户输入进行检查 | 检查用户输入 |
| 我们可以看到，当配置缺失时会产生影响 | 配置缺失时功能失效 |
| 其实这个问题主要是因为没有进行处理 | 未处理导致此问题 |
```

- [ ] **Step 2: 行数与关键词校验**

```bash
wc -l plugins/productivity/skills/caveman-chinese/SKILL.md
# Expected: ≤80 行

rg -n '双模式|HARD-GATE|改写|风格|自检' plugins/productivity/skills/caveman-chinese/SKILL.md
# Expected: 每关键词至少 1 处命中

rg -n 'examples\.md|sub-agent|subagent' plugins/productivity/skills/caveman-chinese/ || echo "OK: no examples.md or agents"
# Expected: OK

test ! -f plugins/productivity/skills/caveman-chinese/examples.md && echo "OK: no examples.md"
# Expected: OK: no examples.md
```

- [ ] **Step 3: frontmatter description 长度校验**

```bash
python3 -c "
import re
text=open('plugins/productivity/skills/caveman-chinese/SKILL.md').read()
m=re.search(r'^description:\s*(.+)$', text, re.M)
assert m, 'missing description'
desc=m.group(1).strip()
assert len(desc)<=150, f'description too long: {len(desc)}'
print('OK description chars:', len(desc))
"
```

Expected: `OK description chars:` 且 ≤150

- [ ] **Step 4: Commit**

```bash
git add plugins/productivity/skills/caveman-chinese/SKILL.md
git commit -m "feat(productivity): add caveman-chinese skill"
```

---

## Task 3: 人工验收与 spec 状态

**Files:**

- Modify: `docs/superpowers/specs/2026-06-07-productivity-caveman-chinese-design.md`

- [ ] **Step 1: 人工试写（改写模式）**

用以下 3 段输入，在 Claude Code 中 `/productivity:caveman-chinese` 触发改写模式，确认输出**仅压缩正文、零说明**：

**输入 A（纯叙述）：**

```text
其实我们可以看到，当用户没有进行相关配置的时候，主要会产生一些比较严重的影响，我们需要对其进行详细的检查。
```

期望要点：保留「未配置」「严重影响」「需检查」；无禁词；无前言后语。

**输入 B（Markdown）：**

```markdown
## 主要功能说明

- 它的主要作用就是对用户输入进行详细的检查
- 当配置缺失时，我们可以看到系统会产生影响
```

期望要点：标题与列表项中文已压缩；结构保留。

**输入 C（含代码）：**

````markdown
调用 `checkConfig()` 进行检查。当路径 `/etc/app.yaml` 不存在时，其实会产生影响。

```go
func checkConfig() error { ... }
```
````

期望要点：`checkConfig()`、`/etc/app.yaml`、fenced block 原样；外围中文已压缩。

- [ ] **Step 2: 更新 spec §8 验收标准 checkbox 与状态**

将 spec 顶部状态改为：

```markdown
**状态：** 已实现
```

将 §8 四项 checkbox 改为 `[x]`。

- [ ] **Step 3: 最终结构校验**

```bash
test -f plugins/productivity/.claude-plugin/plugin.json
test -f plugins/productivity/skills/caveman-chinese/SKILL.md
python3 -c "import json; json.load(open('.claude-plugin/marketplace.json')); json.load(open('plugins/productivity/.claude-plugin/plugin.json'))"
wc -l plugins/productivity/skills/caveman-chinese/SKILL.md
echo "ALL CHECKS PASSED"
```

Expected: `ALL CHECKS PASSED`；`SKILL.md` ≤80 行

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-06-07-productivity-caveman-chinese-design.md
git commit -m "docs: mark productivity caveman-chinese spec implemented"
```

---

## Spec 覆盖自检

| Spec 要求 | 对应 Task |
|-----------|-----------|
| `plugins/productivity/` 目录 | Task 1 |
| `plugin.json` | Task 1 |
| `SKILL.md` ≤80 行、双模式/触发/保真/禁区/自检/样例 | Task 2 |
| 无 examples.md、agent、脚本 | Task 2 Step 2 |
| 3 段人工试写 | Task 3 Step 1 |
| marketplace 注册 | Task 1 |

无遗漏。
