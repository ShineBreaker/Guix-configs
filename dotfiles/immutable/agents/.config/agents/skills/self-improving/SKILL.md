---
name: self-improving
description: Use when detecting experience signals during conversation, writing lessons to KB, or encountering "记录下来", "save this", "/ascended", user corrections, non-obvious bugs, knowledge gaps, or better solutions.
---

# Self-Improvement

在对话中检测经验信号，通过 `kb` CLI 写入知识库。

> CLI 操作细节见 `knowledge-base` skill。本 skill 只关注 **何时/为何** 记录、**怎么写** 以及 **维护流程**。

## 任务前预检

<critical>
开始任何非平凡任务前，必须先执行 `kb list --category <category> --all` 读取对应领域标题索引；每次都必须做。标题列表不足以定位时，再执行 `kb search` 正文预检。
</critical>

```bash
kb list --category <相关类别> --all
kb get <明显相关的卡片ID>
kb search "<当前任务的关键技术 工具 症状>" --context 2
kb search "<错误信息或症状>"
kb profile
```

预检第一步是 category 标题索引：先看该领域有哪些历史经验，再决定是否 `kb get` 读取全文。`kb search` 默认是多关键词相关度检索，只作为标题索引后的正文补充；使用 2-5 个稳定关键词（技术名、工具名、错误短语、配置名），必要时加 `--all-terms` 收窄；只有确实需要正则时才用 `--regex`。

**必须预检**：调试/排障、配置修改、已使用过的技术栈、与之前类似的问题。
**可跳过**：全新领域开发、简单编辑、有明确文档的标准操作。

**结果处理**：高相关 → 作为上下文参考；低相关/空 → 静默继续；矛盾 → 以较新/经验证的为准。

## 检测触发器

完整触发器列表见 `references/triggers.md`。

| 信号类型       | 推荐 type  | 关键词/信号                      |
| -------------- | ---------- | -------------------------------- |
| 修正           | `debug`    | "不对，应该是…"、"你搞错了…"     |
| 知识空白       | `research` | 未知信息、过时文档、API 行为不符 |
| 非显而易见错误 | `debug`    | 排查 >2 步、环境差异             |
| 更好方案       | `refactor` | 更优写法、更简路径               |
| 配置陷阱       | `config`   | 跨工具集成踩坑、非默认组合       |

**防误触发**：用户描述报错但不纠正你、普通 review 无可复用经验 → 不触发。

## 记忆信号（写入 MEMORY.org）

| 信号类型 | 记忆类型  | 关键词/信号                          | 写入命令                                        |
| -------- | --------- | ------------------------------------ | ----------------------------------------------- |
| 偏好表达 | feedback  | "我喜欢..."、"不要..."、"停..."      | `kb memory --add --type feedback`               |
| 行为纠正 | feedback  | 用户纠正了你的工作方式（非技术错误） | `kb memory --add --type feedback`               |
| 习惯模式 | feedback  | 同一偏好出现 ≥2 次                   | `kb memory --add --type feedback`               |
| 项目决策 | project   | 不可从代码推导的项目级决策/状态      | `kb memory --add --type project --project <id>` |
| 外部指针 | reference | 外部系统/文档/资源的位置信息         | `kb memory --add --type reference`              |

**MEMORY vs KB 边界**：

- "你怎么做"（风格/流程/工具选择偏好）→ MEMORY
- "你做错了"（事实/技术错误）→ KB
- 两者可能并存：同一事件同时写入 MEMORY 和 KB

**防误触发**：

- 技术性纠正（"正则写错了"、"参数传反了"）→ 只写 KB，不写 MEMORY
- 普通确认（"好的"、"行"）→ 不触发任何系统

## 写入时机

**必须写入**：非显而易见的 bug（排查 >2 步）、环境特殊行为、配置踩坑、用户纠正。

**不必写入**：语法拼写修正、文档有明确答案、一次性操作、已有经验覆盖、用户仍在纠正中。

## 写入流程

1. `kb search` 去重
2. 矛盾检测 — 新发现是否与已有卡片/pattern 矛盾
3. `kb fields` 查看标签，优先复用
4. `kb add` 写入卡片（CLI 用法见 `knowledge-base` skill）
5. `kb lint` 校验格式
6. 传播联动 — 检查受影响的 pattern/卡片
7. `kb connect` 建立关联链接
8. `kb profile --add` 更新画像（如涉及偏好/项目变化）

### MEMORY 写入流程

1. 判断信号类型（偏好/行为纠正/习惯 → feedback，项目决策 → project，外部指针 → reference）
2. `kb memory --add --type <type> [--project <id>] --title "标题" --stdin <<EOF`
   正文
   EOF
3. feedback 类型：自动分配 F 序号，插入 MEMORY.org `* feedback` 节
4. project 类型：自动追加到 memories/projects/<name>.org 对应节
5. reference 类型：自动分配 R 序号，插入 MEMORY.org `* reference` 节

### 增量更新原则

- **任务完成后立即触发** — 不要累积多个任务后再统一总结，趁热记录
- **小步快跑** — 一个任务一张卡片，不要把多个不相关经验塞进一张卡片
- **即时回顾** — 写入后快速浏览相关卡片，确认新经验是否与已有知识形成有效连接

### `mistake` 卡片必须覆盖

1. 原始问题
2. 用户纠错反馈链
3. 这次错在哪里
4. 最终正确处理
5. 下次自检
6. 不确定结论标注 `(推测)`/`(单源)`，可能过时标注验证日期

### `note` 卡片必须覆盖

1. 事项内容
2. 为什么值得长期保留
3. 适用场景和边界
4. 后续行动

## 写入规范

### 写入前决策

1. `kb search` 去重 — 已有卡片覆盖时补充修正，不新建重复卡
2. **优先复用已有标签** — `kb fields` 查看现有 category/tech，只有全新领域才创建新类别
3. 项目私有细节只写必要上下文；可泛化规则晋升到 `patterns.org`
4. 卡片保存完整过程，pattern 保存紧凑规则；二者可共存，pattern 必须引用卡片 ID

写入质量规范详见 `self-improving/references/writing-guide.md`。

AI-First 卡片规则详见 `self-improving/references/ai-first-rules.md`。

### Entry type 映射

| 来源语义     | `--entry`  | 推荐 type             | 推荐 owner      |
| ------------ | ---------- | --------------------- | --------------- |
| 用户纠错     | `mistake`  | `debug` / `config`    | `collaborative` |
| 长期注意事项 | `note`     | `workflow` / `config` | `ai`            |
| 飞升模式复盘 | `ascended` | `debug` / `workflow`  | `collaborative` |

`--stdin` 内容若包含 `**` 小节则按完整 Org 正文写入，否则自动生成模板。

### 子章节规则

`kb add` 自动生成一级标题；`--stdin` 中从二级标题开始写。

## 模式归纳

同类经验 ≥3 次 → 晋升为 pattern。晋升不删除原卡片。

**模式结构**（≤5 行）：

```org
** <结论性标题>
   <一句话声明式规则>。
   适用：<场景>
   例外：<反例或边界条件>
   参考：<经验卡片 ID>
```

**模式即时修补**：使用 pattern 时发现过时/不完整/有误，必须立即修补，不要等待用户提醒。

## 回顾机制

定期（建议每月）执行以下回顾：

1. **知识内化检查** — 浏览最近 10 张卡片，问自己：这些经验是否已成为默认行为？
2. **模式有效性** — 检查 patterns.org 中的模式，是否有已被新实践推翻的？
3. **连接补全** — 扫描孤立卡片（无 connect 链接），评估是否需要建立关联
4. **画像更新** — 检查 profile.org 是否反映当前真实偏好和项目状态

回顾可手动执行，也可由 `kb-curator` skill 在后台策展时一并完成。

## 飞升模式

同一问题被纠正 ≥2 次仍无法解决 → 进入飞升模式。详细步骤见 `references/ascended-mode.md`。

核心：全面检索知识源 → 筛出最接近经验 → 解释失败原因 → 给出最强方案 → 写入经验卡片。

## 用户画像维护

### 触发条件

- `profile.org` 的 `#+date` 距离当前日期超过 **7 天**
- 经验写入流程第 8 步中发现用户的**偏好变化**或**活跃项目变更**

### 分类体系

固定 5 个一级分类：

- **身份** — 用户名、系统环境等
- **偏好** — 编程语言、编辑器、包管理器、沟通风格等
- **习惯** — 工作流、常用工具组合等
- **活跃项目** — 正在维护的仓库/系统
- **目标** — 长期或短期目标

### CLI 操作

```bash
kb profile                                 # 概览
kb profile <分类名>                        # 查看指定分类
kb profile --add "目标" --text "..."       # 追加条目
echo "- 新内容" | kb profile --set "偏好"  # 覆盖分类
```

### 更新步骤

1. **查看当前状态**
   ```bash
   kb profile
   ```
2. **追加或覆盖**
   - 少量新增 → `kb profile --add "<分类>" --text "..."`
   - 整类重写 → `echo "..." | kb profile --set "<分类>"`
3. **更新日期**
   手动将 `profile.org` 顶部的 `#+date` 改为当前日期
4. **确认写入**
   ```bash
   kb profile
   ```

### 校验清单

- [ ] 日期已更新为当前日期
- [ ] 5 个分类结构完整
- [ ] 新增/修改内容正确写入对应分类
- [ ] 无格式错误（`kb lint` 不影响 profile，但建议手动检查）
