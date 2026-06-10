# Pi Agent 系统配置

本目录通过 Guix Home 的 `home-dotfiles-service-type` 部署到 `~/.config/` 和 `~/.local/`（不可变，构建时复制到 store）。

## 概述

当前目录承载一套 Agent 系统：

- **全局上下文**（`~/.config/agents/context/`）— 被 OpenCode / Crush / Pi 共同引用的统一指引
- **Skills 体系**（`~/.config/agents/skills/`）— kb-curator、self-improving、pack-guix（KB 操作已迁出为 `kb-mcp` 工具集，见下）

## 目录结构

```
agents/
├── .config/
│   ├── agents/
│   │   ├── context/         # 01-language.md, 02-ultilities.md（全局指令）
│   │   └── skills/          # kb-curator, self-improving, pack-guix（KB 操作走 mcp-servers/kb-mcp/）
│   └── crush/               # Crush superpowers 配置（bin/、hooks/、crush.json）
│
└── .local/
    └── bin/                 # kb、pi、pi-acp、pi-update 入口脚本
```

## 知识库体系

该目录内建完整的知识库（KB）系统，用于记录和检索 AI 助手的工作经验：

### 核心组件

| 组件                   | 位置                                    | 说明                                           |
| ---------------------- | --------------------------------------- | ---------------------------------------------- |
| `kb-mcp` MCP 工具集    | `.config/agents/mcp-servers/kb-mcp/`    | 12 个 `kb_*` 工具（MCP），KB 查询/写入主入口   |
| `kb-curator` skill     | `.config/agents/skills/kb-curator/`     | 夜间策展、KB 健康检查                          |
| `self-improving` skill | `.config/agents/skills/self-improving/` | 经验信号检测与记录                             |
| `kb` 命令（CLI 兜底）  | `.local/bin/kb`                         | 不支持 MCP 的环境用 `kb list` / `kb search` 等 |

> **迁移说明**：原 `knowledge-base` skill（路径 `.config/agents/skills/knowledge-base/`）已删除，KB 操作整体迁出为 `kb-mcp` MCP 工具集。`pi-mcp-adapter` 在 mcp.json 中注册 `kb-mcp` 即可在所有 MCP 客户端（Pi / Crush / Claude Code 等）里自动发现 12 个 `kb_*` 工具。CLI 仍保留 `kb` 子命令作为兜底。

### 经验卡片类型

| 类型       | 触发信号                    | 说明               |
| ---------- | --------------------------- | ------------------ |
| `mistake`  | 用户纠正（"不对，应该是…"） | 记录错误与正确做法 |
| `debug`    | 排查 >2 步、环境差异        | 踩坑过程与解决方案 |
| `config`   | 配置陷阱、非默认组合        | 跨工具集成经验     |
| `refactor` | 发现更优方案                | 重构决策与收益     |
| `note`     | 知识空白、文档过时          | 待研究或注意事项   |
| `ascended` | 同一问题被纠正 ≥2 次        | 全面检索最强方案   |

### 使用流程

```bash
# 查询经验
kb search "任务关键词"
kb search "任务关键词/"工具/"框架"

# 写入经验（由 self-improving skill 自动触发）
kb search "去重" → kb add → kb lint --fix

# 查看字段规范
kb fields

# 更新用户偏好（写入 MEMORY.org feedback 节）
kb memory --add --type feedback --title "偏好描述" --stdin <<EOF
正文
EOF
```

### 知识库文件

- 卡片存储：`~/.local/share/kb/cards/`（由 `kb add` 管理）
- 模板：`configs/org/templates/`（experience/troubleshooting/decision/learning）
- Org 集成：`configs/org/org-knowledge.el`

### 触发规则

对话中出现以下信号时**必须**触发 `self-improving` skill：

- 用户表示任务完成（"可以用了"、"一切正常工作"）
- 用户纠正 AI 错误
- 发现非显而易见的 bug 或更优方案
- 跨工具集成踩坑

## 关键约定

- **加载顺序**：`01-language.md` → `02-ultilities.md`（AI 助手在最外层 AGENTS.md 中可同步注入）
- **Skills 引用**：`~/.config/agents/skills/` 中的 SKILL.md 被各类 Agent 引用

## 修改约束

- 修改全局上下文文件（`01-language.md`、`02-ultilities.md`）时，需同步影响所有引用方
- 新增 skill 时，先在既有 kb-curator/self-improving 的 SKILL.md 中看模式；新增 MCP 工具集时参考 `mcp-servers/kb-mcp/` 的薄壳设计
- `~/.local/bin/` 下的入口脚本是 Guix Home 部署目标，不要直接编辑——改 `dotfiles/immutable/agents/.local/bin/` 中的源文件
