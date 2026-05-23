<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: MIT
-->

# Superpowers for Crush

让 [Superpowers](https://github.com/obra/superpowers) 技能库在 [Crush](https://crush.sh) 中生效。

## 原理

Superpowers 的 `skills/` 目录与 Crush 的 skill 格式完全兼容（YAML frontmatter + Markdown body）。

- **技能加载**：Crush 从 `~/.config/agents/skills/` 扫描含 `SKILL.md` 的目录
- **自动触发**：Crush 按 `description` 字段匹配决定何时激活 skill
- **`using-superpowers`** skill 负责在对话中注入"技能优先检查"纪律

## 安装步骤

```bash
bash tools/crush-superpowers/install.sh
```

脚本会：
1. 检查命名冲突（与已有 skill 同名则中止）
2. 将 14 个 skill 复制到 `~/.config/agents/skills/`（保留原始名称）

## 验证

重启 Crush 后发送：

```
Let's make a react todo list
```

agent 应该**先触发 brainstorming skill**，询问设计细节，而不是直接写代码。

## 更新

```bash
bash tools/crush-superpowers/install.sh   # 覆盖复制
```

## 卸载

```bash
cd ~/.config/agents/skills
rm -rf brainstorming dispatching-parallel-agents executing-plans \
      finishing-a-development-branch receiving-code-review \
      requesting-code-review subagent-driven-development \
      systematic-debugging test-driven-development using-git-worktrees \
      using-superpowers verification-before-completion writing-plans \
      writing-skills
```

## 技术细节

- Crush 要求 `name` 字段与目录名完全一致（所以不加前缀）
- 使用复制而非 symlink（Crush 的 fastwalk 虽然跟随 symlink，但复制更可靠）
- 部分第三方 skill（docx-cn, openai-whisper 等）因 YAML frontmatter 格式问题无法被 Crush 解析，这是它们自身的问题
