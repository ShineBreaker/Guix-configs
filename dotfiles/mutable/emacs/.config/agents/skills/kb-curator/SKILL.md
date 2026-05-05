---
allowed-tools:
- "Bash(kb:\\*)"
- "Bash(python3:\\*)"
- "Bash(grep:\\*)"
- Read
- Glob
description: |
  知识库策展 — 空闲时（夜间）自动运行的知识库维护。从多源对话记录中提取经验、 分析卡片健康度、识别空白、补充缺失内容。 Triggers: "检查知识库", "筛选经验", "补充知识库", "清理知识库", "知识库还缺什么", "curate kb", "知识库健康检查", "知识库维护", "整理知识库", "review knowledge base", "找重复卡片", "补齐空白", "知识库质量", "优化知识库", "clean up kb", "audit knowledge base", "夜间策展", "自动策展", "跑一次知识库维护", "nightly curation", "提取今天的对话", "从对话中提取经验"
name: kb-curator
version: 3.0.0
---

# 知识库策展（空闲时运行）

在空闲时段（夜间/无人交互时）自动维护知识库：提取多源对话 → 分析健康度 → 识别空白 → 补充经验。

<critical>
定位：这是后台批处理 skill，**禁止任何提问等任何需要用户手动处理的操作**，所有任务完成之后输出总结报告即可。
如需实时交互式记录经验，使用 `self-improving` skill。
</critical>

## 工具

| 脚本                               | 用途                                                         |
|------------------------------------|--------------------------------------------------------------|
| `scripts/extract-conversations.py` | **第一步**：从 OpenCode/Crush/Codex/Claude Code 提取昨日对话 |
| `scripts/analyze_kb.py`            | 知识库健康分析（分布、重复、质量）                           |
| `scripts/find_gaps.py`             | 知识空白检测（缺失组合、陈旧卡片）                           |
| `references/curation-guide.md`     | 策展工作流和补充策略                                         |

## 夜间自动策展流水线

每次策展按以下顺序执行，**禁止进行任何需要用户手动干预的行为（如提问等）**，全程自行执行：

### 第一步：提取昨日对话

从所有 AI 编程工具中提取昨天的对话记录，转为 Org-mode 文件供后续分析。

``` bash
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
|-------------|------------------------------------------------------|--------|
| OpenCode    | `~/.local/share/opencode/opencode-stable.db`         | SQLite |
| Crush       | `~/.config/crush/.crush/crush.db` + 项目级 `.crush/` | SQLite |
| Claude Code | `~/.claude/transcripts/*.jsonl`                      | JSONL  |
| Codex       | `~/.codex/sessions/` + 项目级 `.codex/sessions/`     | JSONL  |

### 第二步：健康诊断

``` bash
# 全面健康检查
python3 scripts/analyze_kb.py --quality --duplicates

# 知识空白检测（60天陈旧阈值）
python3 scripts/find_gaps.py --stale-days 60
```

#### 增强诊断维度

除了现有的分布/重复/质量检查，额外关注：

- **矛盾检测**：同类卡片中是否存在互相矛盾的结论？`kb search <关键词>` 检查同一主题的多张卡片
- **概念空白**：多张卡片引用的技术/工具是否有独立覆盖？高频出现但无专门卡片的主题需补充
- **陈旧声明**：超过 60 天且包含时效性内容（版本、API、配置方法）但未标注验证日期的卡片
- **孤立卡片**：无任何其他卡片/pattern 引用的卡片 → 检查是否值得保留或应补充关联
- **模式覆盖缺口**：已有 3 张以上同类卡片但仍无对应 pattern 的主题

### 第三步：矛盾调和

扫描已有知识库中的矛盾并处理：

``` bash
# 搜索同一主题的多张卡片
kb search "<关键词>"

# 查看同类卡片的结论是否一致
kb list --category <类别> --type debug
```

矛盾处理规则：

- **明确矛盾**（同一条件下两个相反结论）→ 保留较新的/经验证的，旧卡片添加「已过时」标注
- **场景差异**（不同条件下分别成立）→ 在两张卡片中互相引用，注明各自适用场景
- **时间演化**（旧方案被新方案取代）→ 更新旧卡片标注「已被 \<新卡片ID\> 取代」
- **歧义未决** → 保留双方，标注 `(存疑)` 待下次验证

### 第四步：自发综合

扫描已有卡片，发现尚未被显式连接的模式：

1.  **跨卡片模式**：同一概念在不同 category 的卡片中出现 ≥2 次 → 考虑创建 pattern 或补充已有 pattern
2.  **概念演化**：同一主题有多张卡片按时间排列 → 检查是否反映了认知演进，是则在最新卡片中补充演化脉络
3.  **孤立模式**：pattern 引用的卡片已不存在或已过时 → 修补或标注 pattern
4.  **缺失关联**：卡片之间有隐含联系但无互相引用 → 补充 `[[file:...]]` 链接

### 第五步：筛选与补充

``` bash
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

### 第六步：写入经验

``` bash
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

### 第七步：传播联动

写入新卡片后，检查并更新关联内容：

``` bash
# 检查是否有受影响的 pattern
kb patterns --get | grep -i "<相关关键词>"

# 检查同类卡片是否需要更新
kb search "<相关关键词>"
```

联动规则：

- 新卡片推翻旧结论 → 更新旧卡片或添加勘误
- 同类卡片累计 ≥3 张 → 晋升为 pattern
- 新卡片补充了已有 pattern 的边界条件 → 修补 pattern
- pattern 引用的卡片已过时 → 标注 pattern 并引用新卡片

### 第八步：重整与收尾

``` bash
kb reindex     # 重建索引
kb lint --fix  # 自动修复格式问题
```

如果同一主题已有 3 张以上卡片，或近期新增 5 张以上同类卡片，执行一次 focused consolidation：合并重复、修补过时内容，并把稳定结论晋升为 pattern。目标是减少未来检索噪音，而不是增加总结字数。

## 策展原则

详细写作规范、质量标准和补充策略见 `references/curation-guide.md`。

**应记录**：用户偏好和纠正、非显而易见的 bug（排查 \>2 步）、环境特定陷阱、更好的方案。

**不应记录**：任务进度和 TODO、语法错误和拼写修正、纯流水账、已有经验完全覆盖的情况。

**维护理念**：过时卡片是负担不是资产、矛盾必须处理、卡片之间应有链接、每次策展后输出总结（提取 N 对话 / M 候选 / K 新卡 / C 矛盾调和）。

## 策展工作流（交互模式）

当用户主动触发策展时，按以下流程执行：

1.  **提取对话**：`extract-conversations.py` → 将昨日对话保存到 `~/Documents/Org/conversations/`
2.  **诊断**：`analyze_kb.py --quality --duplicates` → 获取健康报告
3.  **空白检测**：`find_gaps.py --stale-days 60` → 识别缺失内容
4.  **矛盾调和**：检查同类卡片的结论一致性，处理矛盾（详见矛盾调和步骤）
5.  **自发综合**：扫描跨卡片模式，发现隐含连接（详见自发综合步骤）
6.  **补充**：先用 `kb fields` 查看现有标签避免碎片化，再浏览提取的对话文件，将有价值的经验写入知识库
7.  **传播联动**：检查新写入卡片是否有受影响的 pattern 或已有卡片，执行关联更新
8.  **重整**：`kb reindex && kb lint --fix`
9.  **质量复核**：对照策展原则检查新增卡片（声明式事实、非流水账、非临时内容、自包含、时效性标注）

详细流程和补充策略见 `references/curation-guide.md`。

## 旧卡片审查清单

策展时发现以下情况应立即处理：

- [ ] 内容已过时/不再适用 → 归档或标记过期，引用替代卡片
- [ ] 只有结论没有排查过程 → 补充执行过程章节
- [ ] 标题不包含结论 → 重命名为结论性标题
- [ ] 纯流水账无经验教训 → 降级或删除
- [ ] 与已有卡片高度重复 → 合并保留质量更好的
- [ ] 已被 pattern 覆盖但仍有详细追溯价值 → 保留卡片，pattern 引用卡片 ID
- [ ] 常被检索但不在 pattern 中 → 晋升为 pattern 或修补现有 pattern
- [ ] 与同类卡片结论矛盾 → 按调和规则处理（见矛盾调和步骤）
- [ ] 缺少时效性标注但涉及版本/API/配置 → 补充验证日期
- [ ] 无其他卡片/pattern 引用 → 评估是否应补充关联或归档
- [ ] pattern 引用的卡片已不存在 → 修补 pattern 的参考链接

## 缓存式记忆整理

1.  高频复用、跨会话稳定的结论进入 `patterns.org`
2.  低频但可追溯的详细案例留在 `experiences/`
3.  过时或低质内容先标记、修补或合并，不直接删除
4.  pattern 缺少边界条件时，回链引用具体经验卡片补足依据

## 飞升模式与策展的关系

当 `self-improving` skill 进入飞升模式（同一问题被持续纠正 ≥2次）时，事后应优先写入一张复盘经验卡片。 若当时来不及写入，可以在对话提取结果中保留策展线索：

``` bash
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
|----------|----------------------------------|
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
- [ ] 代码块使用 Org mode 格式（`#+begin_src language`）
- [ ] 仅提交本次策展涉及的文件
