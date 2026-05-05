---
name: kb-curator
description: 知识库策展 — 空闲时（夜间）自动运行的知识库维护。从多源对话记录中提取经验、分析卡片健康度、识别空白、补充缺失内容
version: "3.0.0"
when_to_use: |
  Use when the user wants to review, curate, or optimize the knowledge base,
  especially during idle/idle-time maintenance.
  Triggers: "检查知识库", "筛选经验", "补充知识库", "清理知识库",
  "知识库还缺什么", "curate kb", "知识库健康检查", "知识库维护",
  "整理知识库", "review knowledge base", "找重复卡片", "补齐空白",
  "知识库质量", "优化知识库", "clean up kb", "audit knowledge base",
  "夜间策展", "自动策展", "跑一次知识库维护", "nightly curation",
  "提取今天的对话", "从对话中提取经验"
allowed-tools:
  - Bash(kb:*)
  - Bash(python3:*)
  - Bash(grep:*)
  - Read
  - Glob
---

# 知识库策展（空闲时运行）

在空闲时段（夜间/无人交互时）自动维护知识库：提取多源对话 → 分析健康度 → 识别空白 → 补充经验。

> 定位：这是 **后台批处理** skill，适合在用户离开键盘时运行，不依赖用户实时交互，策展完成后输出总结报告即可。如需实时交互式记录经验，使用 `self-improving` skill。

## 工具

| 脚本                               | 用途                                                         |
| ---------------------------------- | ------------------------------------------------------------ |
| `scripts/extract-conversations.py` | **第一步**：从 OpenCode/Crush/Codex/Claude Code 提取昨日对话 |
| `scripts/analyze_kb.py`            | 知识库健康分析（分布、重复、质量）                           |
| `scripts/find_gaps.py`             | 知识空白检测（缺失组合、陈旧卡片）                           |
| `references/curation-guide.md`     | 策展工作流和补充策略                                         |

## 夜间自动策展流水线

每次策展按以下顺序执行，**禁止进行任何需要用户手动干预的行为（如提问等）**，全程自行执行：

### 第一步：提取昨日对话

从所有 AI 编程工具中提取昨天的对话记录，转为 Org-mode 文件供后续分析。

```bash
# 提取所有数据源的昨日对话（默认输出到 ./conversations/YYYY-MM-DD/）
python3 scripts/extract-conversations.py

# 只提取特定来源
python3 scripts/extract-conversations.py -s claude
python3 scripts/extract-conversations.py -s codex
python3 scripts/extract-conversations.py -s crush

# 指定日期
python3 scripts/extract-conversations.py --date 2026-04-30

# 指定输出目录
python3 scripts/extract-conversations.py -o ~/Documents/Org/conversations/2026-04-30
```

**支持的数据源**：

| 来源        | 存储位置                                             | 格式   |
| ----------- | ---------------------------------------------------- | ------ |
| OpenCode    | `~/.local/share/opencode/opencode-stable.db`         | SQLite |
| Crush       | `~/.config/crush/.crush/crush.db` + 项目级 `.crush/` | SQLite |
| Claude Code | `~/.claude/transcripts/*.jsonl`                      | JSONL  |
| Codex       | `~/.codex/sessions/` + 项目级 `.codex/sessions/`     | JSONL  |

### 第二步：健康诊断

```bash
# 全面健康检查
python3 scripts/analyze_kb.py --quality --duplicates

# 知识空白检测（60天陈旧阈值）
python3 scripts/find_gaps.py --stale-days 60
```

### 第三步：筛选与补充

```bash
# 查看昨日对话中有价值的经验片段
grep -rl "fix\|bug\|error\|解决\|修复" ./conversations/$(date -d yesterday +%Y-%m-%d)/ | head -10

# 了解知识库现有标签分布，避免创建碎片化新类别
kb fields --category
kb fields --tech

# 按类别筛选卡片
kb list --category guix

# 全文搜索关键词
kb search "Guix"
```

### 第四步：写入经验

```bash
# 写入新经验卡片（管道输入）
kb add --title "简短标题" --category emacs --tech emacs-lisp --type debug --owner ai --summary "一句话总结" --stdin <<'EOF'
** 任务描述
说明要做什么、为什么。

** 执行过程
1. 分析与排查
2. 修复方案
3. 验证结果

** 关键发现
*** 重要经验教训
EOF
```

### 第五步：重整与收尾

```bash
kb reindex     # 重建索引
kb lint --fix  # 自动修复格式问题
```

如果同一主题已有 3 张以上卡片，或近期新增 5 张以上同类卡片，执行一次 focused consolidation：合并重复、修补过时内容，并把稳定结论晋升为 pattern。目标是减少未来检索噪音，而不是增加总结字数。

## 策展原则

知识库卡片应遵循以下写入标准：

### 应记录的（值得保存）

- **用户偏好和纠正**：用户反复指出的问题、偏好 → 减少未来纠正成本
- **非显而易见的 bug**：排查 \> 2 步才定位根因的问题
- **环境特定陷阱**：涉及特定软件环境生态的特殊行为
- **更好的方案**：事后发现比初始实现更优的解法

### 不应记录的（无需保存）

- **任务进度和 TODO 状态**：临时的、一次性的工作日志
- **语法错误和拼写修正**：文档已有明确答案的问题
- **纯流水账**：只有步骤没有经验教训的过程记录
- **已有经验完全覆盖的情况**：写入前先用 `kb search` 验证

### 写作风格

- **声明式事实，非指令**："Guix swap-space 需同时在 operating-system 声明" ✓ — "总是要在 operating-system 中声明 swap" ✗
- **标题包含结论**：一眼能看出解决了什么问题
- **记录坑点而非过程**：重点关注"没想到的地方"

### 维护理念

- 过时的卡片是负担，不是资产 — 发现过期内容立即标记或更新
- 知识库的价值在于减少未来用户纠正的成本
- 每次夜间策展后输出简短总结：提取了 N 个对话，发现 M 个候选经验，写入了 K 张卡片

## 策展工作流（交互模式）

当用户主动触发策展时，按以下流程执行：

1.  **提取对话**：`extract-conversations.py` → 将昨日对话保存到 `~/Documents/Org/conversations/`
2.  **诊断**：`analyze_kb.py --quality --duplicates` → 获取健康报告
3.  **空白检测**：`find_gaps.py --stale-days 60` → 识别缺失内容
4.  **补充**：先用 `kb fields` 查看现有标签避免碎片化，再浏览提取的对话文件，将有价值的经验写入知识库
5.  **重整**：`kb reindex && kb lint --fix`
6.  **质量复核**：对照策展原则检查新增卡片（声明式事实、非流水账、非临时内容）

详细流程和补充策略见 `references/curation-guide.md`。

### 从对话历史提取经验

**首选方式**：使用 `extract-conversations.py` 自动提取，而非手动 grep。

```bash
# 提取昨日所有数据源的对话
python3 scripts/extract-conversations.py -o ~/Documents/Org/conversations/$(date -d yesterday +%Y-%m-%d)

# 然后浏览提取的文件寻找有记录价值的片段
ls ~/Documents/Org/conversations/$(date -d yesterday +%Y-%m-%d)/
```

提取时遵循 **记忆分层模型**：

- **经验卡片** ← 跨会话可复用的 bug 修复、配置陷阱、方案对比（= hermes memory）
- **模式文件** ← 3 次以上同类经验的通用规则总结（= hermes skill）
- **留在对话历史** ← 任务进度、TODO、一次性操作记录（= hermes session_search）

## 旧卡片审查清单

策展时发现以下情况应立即处理：

- [ ] 内容已过时/不再适用 → 归档或标记过期
- [ ] 只有结论没有排查过程 → 补充执行过程章节
- [ ] 标题不包含结论 → 重命名为结论性标题
- [ ] 纯流水账无经验教训 → 降级或删除
- [ ] 与已有卡片高度重复 → 合并保留质量更好的
- [ ] 已被 pattern 覆盖但仍有详细追溯价值 → 保留卡片，pattern 引用卡片 ID
- [ ] 常被检索但不在 pattern 中 → 晋升为 pattern 或修补现有 pattern

## 缓存式记忆整理

1.  高频复用、跨会话稳定的结论进入 `patterns.org`
2.  低频但可追溯的详细案例留在 `experiences/`
3.  过时或低质内容先标记、修补或合并，不直接删除
4.  pattern 缺少边界条件时，回链引用具体经验卡片补足依据

## 飞升模式与策展的关系

当 `self-improving` skill 进入飞升模式（同一问题被持续纠正 ≥2 次）时，事后应优先写入一张复盘经验卡片。若当时来不及写入，可以在对话提取结果中保留策展线索：

```bash
# 飞升模式结束后，追加到对话记录中供策展分析
echo "### 飞升模式报告" >> conversations/$(date +%Y-%m-%d)/nightly-curation-notes.md
echo "- 问题：<一句话描述>" >> conversations/$(date +%Y-%m-%d)/nightly-curation-notes.md
echo "- 检索了：<知识源列表>" >> conversations/$(date +%Y-%m-%d)/nightly-curation-notes.md
echo "- 最终方案：<一句话>" >> conversations/$(date +%Y-%m-%d)/nightly-curation-notes.md
echo "- 新增经验：<若有新卡片写入>" >> conversations/$(date +%Y-%m-%d)/nightly-curation-notes.md
```

这使策展脚本能在后续自动提取飞升模式的处理结果，归纳为新模式或补充现有模式。

## 文件路径

| 用途     | 路径                             |
| -------- | -------------------------------- |
| CLI 工具 | `~/.local/bin/kb`                |
| 经验卡片 | `~/Documents/Org/experiences/`   |
| 模式文件 | `~/Documents/Org/patterns.org`   |
| 索引文件 | `~/Documents/Org/index.org`      |
| 收件箱   | `~/Documents/Org/inbox.org`      |
| 对话历史 | `~/Documents/Org/conversations/` |

## 检查清单

策展完成后确认：

- [ ] `kb reindex` 已执行
- [ ] `kb lint --fix` 无残留错误
- [ ] 新增卡片元数据完整（category/tech/type/owner）
- [ ] 新增卡片含任务描述、执行过程、关键发现三个章节
- [ ] 代码块使用 Org mode 格式（`#+begin_src` 而非 ` ``` `）
- [ ] 仅提交本次策展涉及的文件
