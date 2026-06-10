# Pi Agent 系统配置

本目录是 Pi Agent 的配置源文件，通过 GNU Stow 部署到 `~/.config/pi/`、`~/.local/share/pi/` 等 XDG 路径。

## 部署模型

```
dotfiles/mutable/agents/      → GNU Stow → 实际路径
├── .config/pi/               → ~/.config/pi/          (配置 + 扩展 + agent)
├── .local/bin/               → ~/.local/bin/          (启动脚本: pi, pi-acp, pi-update)
├── .local/share/pi/          → ~/.local/share/pi/     (辅助脚本 + npm 依赖)
├── .stow-local-ignore        → stow 排除规则
└── .gitignore                → git 排除规则（具体见同目录 .gitignore）

LSP 配置：`~/.config/pi/lsp.json`。
```

`.stow-local-ignore` 排除了 `AGENTS.md`、`.gitignore`、`npm` 目录——这些不会进入 `~`。

**修改后无需重新 stow**（符号链接直接生效），除非新增文件需要 `stow -R pi`。

## 目录结构

```
.config/pi/
├── agents/          # Subagent 定义（YAML frontmatter + Markdown system prompt）
│   ├── scout.md        快速侦察员 (deepseek-v4-flash, thinking: low)
│   ├── researcher.md   文档检索专家 (deepseek-v4-pro, thinking: medium)
│   ├── planner.md      战略规划师 (GLM-5.1, no thinking override)
│   ├── oracle.md       架构顾问 (GLM-5.1, no thinking override)
│   ├── worker.md       自主深度工作者 (GLM-5.1, no thinking override)
│   ├── reviewer.md     无情审查者 (GLM-5.1, no thinking override)
│   └── visual.md       视觉分析员 (GLM-5V-Turbo, 视觉模型)
├── extensions/      # 本地扩展（TypeScript，Pi 启动时加载）
│   ├── atelier/           tmux 分屏 subagent 执行器 + plan-review-gate + worker/planner 上下文注入
│   ├── custom-shortcuts/ 快捷键覆盖（Shift+Tab → /plannotator）
│   └── global-context/  全局上下文注入（before_agent_start hook）
├── prompts/         # Prompt 模板（chain 定义）
│   ├── implement.md              scout(thorough) → planner → worker → reviewer
│   ├── implement-and-review.md   worker → reviewer → worker (fix)
│   ├── scout-and-plan.md         scout → planner
│   └── design-review-implement.md scout(thorough) → planner → oracle → worker → reviewer
├── APPEND_SYSTEM.md # 主 agent 最小公共基础：角色身份说明（worker/planner 上下文由 atelier 按模式动态注入）
├── settings.json    # 核心配置（见下方归属表）
├── models.json      # 自定义 provider/模型定义（zai provider）
├── keybindings.json # 快捷键绑定（当前仅清空默认 app.thinking.cycle）
├── lsp.json         # LSP 配置（@narumitw/pi-lsp 读取，详见 `getAgentDir()`）
└── plannotator.json # plannotator 扩展配置（planning phase 工具白名单）
```

## 环境变量

| 变量                          | 值                           | 用途             |
| ----------------------------- | ---------------------------- | ---------------- |
| `PI_CODING_AGENT_DIR`         | `$XDG_CONFIG_HOME/pi`        | Agent 配置目录   |
| `PI_CODING_AGENT_SESSION_DIR` | `$XDG_DATA_HOME/pi/sessions` | Session 存储目录 |

## settings.json 配置归属

### npm 扩展包清单

当前安装的 packages（`settings.json` → `packages` 数组）：

- `npm:context-mode`、`npm:pi-mcp-adapter`、`npm:pi-web-access`
- `npm:@plannotator/pi-extension` — 规划模式扩展
- `npm:pi-powerline-footer`、`npm:pi-hashline-edit`
- `npm:@narumitw/pi-lsp` — configurable LSP（配置：~/.config/pi/lsp.json）
- `npm:pi-code-review` — 事后 review checklist 自动注入
- `npm:pi-gitnexus` — 知识图谱注入（callers/callees/blast radius）替代 pi-lens 的 cascade
- `npm:@ff-labs/pi-fff`、`npm:pi-cache-graph`
- `npm:@juicesharp/rpiv-todo`、`npm:@juicesharp/rpiv-btw`

### Loop 体系（loopctl）

通过 `.agents/workfile/loops/drivers/loopctl` 管理跨 agent 长期迭代循环（接力棒模型）。每轮 agent 独立进程，上下文完全清空。

| 命令                                           | 用途                         |
| ---------------------------------------------- | ---------------------------- |
| `/loop <name> start --task '...' --adapter pi` | 创建 loop                    |
| `/loop <name> step`                            | 跑一轮                       |
| `/loop <name> status`                          | 查看状态                     |
| `/loop list --all`                             | 列出所有 loop                |
| `/run-plan`                                    | 计划执行（内部走 loop 框架） |

Adapter 声明式配置见 `.agents/workfile/loops/drivers/adapters/`。加新 agent = 复制 `_TEMPLATE.json` 改 5-10 字段。

### npm:pi-powerline-footer

| 配置项      | 说明                                                  |
| ----------- | ----------------------------------------------------- |
| `powerline` | 状态栏配置（preset: default, path.mode: abbreviated） |

### 本地扩展: extensions/atelier/

| 配置项    | 说明                                                                                              |
| --------- | ------------------------------------------------------------------------------------------------- |
| `atelier` | subagent 运行配置（pollIntervalMs, panePrefix, keepResults, timeoutMs, maxTasks, maxConcurrency） |

源码：`extensions/atelier/index.ts` → `loadConfig()` 读取 `settings.atelier`。

### 本地扩展: extensions/global-context/

| 配置项          | 说明                                                                                        |
| --------------- | ------------------------------------------------------------------------------------------- |
| `globalContext` | 全局上下文注入（enabled, contextDir, extraFiles, maxFiles, maxBytesPerFile, maxTotalBytes） |

源码：`extensions/global-context/index.ts` → 读取 `settings.globalContext`。

## 扩展机制

所有扩展位于 `extensions/` 下，每个子目录含 `index.ts` 作为入口，导出 `default function(pi: ExtensionAPI)`。

### global-context（`before_agent_start` hook）

从 `$XDG_CONFIG_HOME/agents/context/` 和 `extraFiles`（含 `~/Documents/Org/profile.org`）读取 `.md` 文件，注入到每次 agent 交互的系统提示词中。有字节预算限制（默认 192KB 总量、64KB/文件、最多 8 文件）。

### custom-shortcuts（`onTerminalInput` hook）

拦截 Shift+Tab，替换为 `/plannotator` 命令提交。通过 `setEditorText` + 返回 `{ data: "\r" }` 实现，绕过 Pi 扩展 API 不走编辑器提交路径的限制。**副作用**：会清除用户当前输入，用 `setTimeout` 恢复。

### atelier

注册 `subagent` 工具和 `/agentname` 快捷命令、plan-review-gate、worker/planner 上下文动态注入。详见上方 Subagent 架构。

## 启动脚本

位于 `.local/bin/`：

| 脚本        | 作用                                                               |
| ----------- | ------------------------------------------------------------------ |
| `pi`        | Pi Agent 主入口（设置 PI\_\* 环境变量 + 按需 pnpm install + exec） |
| `pi-acp`    | 自动 commit 推送工具                                               |
| `pi-update` | Pi Agent 更新脚本                                                  |

## 辅助脚本

位于 `.local/share/pi/scripts/`：

| 脚本                   | 作用                                                        |
| ---------------------- | ----------------------------------------------------------- |
| `subagent-wrapper.sh`  | subagent 执行包装：解析 frontmatter、构造 pi 命令、捕获输出 |
| `extract-pi-result.py` | Pi JSON 流解析器：提取最终 assistant 文本 + 元数据          |
| `read-crush-key.sh`    | 从 crush.json 读取 provider API key                         |

### .local/share/pi/package.json

Pi 的 npm 依赖声明（`@earendil-works/pi-*`），通过 `pnpm install` 安装。

## 共享 Agent 基础设施

本目录不直接包含共享 agent 基础设施（全局上下文、skills、知识库），但 Pi Agent 运行时会消费以下路径：

| 组件                   | 位置（~/.config/agents/） | 说明                                           |
| ---------------------- | ------------------------- | ---------------------------------------------- |
| `kb-mcp` MCP 工具集    | `mcp-servers/kb-mcp/`     | 12 个 `kb_*` 工具（MCP），KB 查询/写入主入口   |
| `kb-curator` skill     | `skills/kb-curator/`      | 夜间策展、KB 健康检查                          |
| `self-improving` skill | `skills/self-improving/`  | 经验信号检测与记录                             |
| `kb` 命令（CLI 兜底）  | `~/.local/bin/kb`         | 不支持 MCP 的环境用 `kb list` / `kb search` 等 |
| `context/`             | `context/`                | 01-language.md, 02-ultilities.md（全局指令）   |

> **迁移说明**：原 `knowledge-base` skill 已删除，KB 操作整体迁出为 `kb-mcp` MCP 工具集。`pi-mcp-adapter` 在 mcp.json 中注册 `kb-mcp` 即可在所有 MCP 客户端里自动发现 12 个 `kb_*` 工具。CLI 仍保留 `kb` 子命令作为兜底。

## 修改约束

- **修改 agents/\*.md**：直接编辑，frontmatter 中的 `model` 必须使用已配置或 Pi 内置可用的 provider/model；保留 scout/researcher 的 deepseek 路由
- **修改 agents/\*.md 的 `thinking`**：仅对确认支持 thinking 的模型设置；zai 当前不要设置
- **修改 settings.json**：必须同步更新本文件的配置归属表
- **修改 models.json**：仅记录自定义 provider；内置 provider（如 deepseek）不要重复定义
- **修改 extensions/**：当前为直接加载的 TypeScript 文件，修改后重启 Pi Agent 会话并用 `pi --help` / 语法检查验证
- **新增 npm 包**：加入 settings.json 的 `packages` 数组，并在本文件记录其配置项
- **删除 npm 包**：同步从 settings.json 移除其配置项，并更新本文件
