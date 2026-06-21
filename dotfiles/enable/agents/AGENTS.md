# Agent 资产配置

本目录集中管理本仓库用到的所有 Agent 相关配置：Pi Agent、Crush、共享的 KB / loopctl 基础设施、跨 agent 技能集（submodule）。统一通过 Guix Home 的 `home-dotfiles-service-type`（stow layout）部署到 `~/.config/`、`~/.local/` 等路径。

## 部署模型

```
dotfiles/enable/agents/      → Guix Home (stow layout) → 实际路径
├── .config/
│   ├── pi/                   → ~/.config/pi/         # Pi Agent 核心配置
│   ├── crush/                → ~/.config/crush/      # Crush 配置 + hooks + bin
│   ├── agents/               → ~/.config/agents/     # 共享基础设施（context, skills, skillsets, mcp-servers）
│   └── loopctl/              → ~/.config/loopctl/    # 跨 agent 循环框架
└── .local/
    ├── bin/                  → ~/.local/bin/         # 启动脚本（pi、pi-acp、pi-update、kb、loopctl 等）
    └── share/pi/             → ~/.local/share/pi/    # 辅助脚本 + npm 依赖
```

`.gitignore` 排除 `.agents/workfile`、`.pi-lens`、`node_modules`、`__pycache__`。文档类的 `AGENTS.md` / `README.md` 由 `home-dotfiles-service-type` 的 `excluded` 规则排除，不会进入 `~`。

## Pi Agent（`.config/pi/`）

```
.config/pi/
├── agents/                  # Subagent 定义（YAML frontmatter + Markdown system prompt）
│   ├── scout.md
│   ├── researcher.md
│   ├── planner.md
│   ├── oracle.md
│   ├── worker.md
│   ├── reviewer.md
│   └── visual.md
├── extensions/              # 本地扩展（TypeScript，Pi 启动时加载）
│   ├── atelier/                 # subagent 执行器 + plan-review-gate + worker/planner 上下文注入
│   ├── custom-shortcuts/        # 快捷键覆盖（Shift+Tab → /plannotator）
│   ├── global-context/          # 全局上下文注入（before_agent_start hook）
│   └── default-timeout/         # 默认超时调整
├── prompts/                 # Prompt 模板（chain 定义）
│   ├── design-review-implement.md
│   ├── implement-and-review.md
│   ├── implement.md
│   ├── parallel-research.md
│   ├── parallel-workers.md
│   ├── research-and-implement.md
│   └── scout-and-plan.md
├── APPEND_SYSTEM.md         # 主 agent 最小公共基础
├── settings.json            # 核心配置（见下方归属表）
├── models.json              # 自定义 provider/模型定义
├── keybindings.json         # 快捷键绑定
├── lsp.json                 # LSP 配置（@narumitw/pi-lsp 读取）
├── mcp.json                 # MCP 服务器（context-mode、kb-mcp）
├── npm/                     # npm 相关
└── plannotator.json         # plannotator 扩展配置
```

### npm 扩展包（`settings.json` → `packages`）

- `npm:context-mode`
- `npm:pi-mcp-adapter`
- `npm:pi-web-access`
- `npm:@plannotator/pi-extension`
- `npm:pi-powerline-footer`
- `npm:pi-hashline-edit`
- `npm:@narumitw/pi-lsp`
- `npm:pi-code-review`
- `npm:pi-gitnexus`
- `npm:@ff-labs/pi-fff`
- `npm:pi-cache-graph`
- `npm:@juicesharp/rpiv-todo`
- `npm:@juicesharp/rpiv-btw`
- `npm:@juicesharp/rpiv-ask-user-question`

修改 `settings.json` 同步更新本节清单。

### 关键 settings 字段

| 字段                               | 用途                                                                                                     |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `defaultProvider` / `defaultModel` | 默认 zai / glm-5.1                                                                                       |
| `compaction`                       | 上下文压缩策略                                                                                           |
| `retry`                            | 失败重试（baseDelay / maxRetries / maxRetryDelayMs）                                                     |
| `packages`                         | npm 扩展清单                                                                                             |
| `skills`                           | skills 加载路径（`~/.config/agents/skills/*`）                                                           |
| `powerline`                        | 状态栏配置（preset: default, path.mode: abbreviated）                                                    |
| `atelier`                          | subagent 运行配置（poll / panePrefix / keepResults / timeoutMs / maxTasks / maxConcurrency / tier 路由） |
| `globalContext`                    | 全局上下文注入（contextDir、extraFiles、字节预算）                                                       |

### MCP（`mcp.json`）

- `context-mode` — 直接调用 `context-mode` 命令

### 本地扩展

| 扩展                | Hook / 作用                                                                                   |
| ------------------- | --------------------------------------------------------------------------------------------- |
| `atelier/`          | 注册 `subagent` 工具与 `/agentname` 快捷命令、plan-review-gate、worker/planner 上下文动态注入 |
| `custom-shortcuts/` | `onTerminalInput` 拦截 Shift+Tab 改为 `/plannotator`                                          |
| `global-context/`   | `before_agent_start` 注入 contextDir + extraFiles，受字节预算限制                             |
| `default-timeout/`  | 默认超时调整                                                                                  |

### Loop 体系（loopctl）

跨 agent 长期迭代循环（接力棒模型）通过 `.config/loopctl/` 与 `.local/bin/loopctl` 管理：

```text
/loop <name> start --task '...' --adapter pi   # 创建 loop
/loop <name> step                              # 跑一轮
/loop <name> status                            # 查看状态
/loop list --all                               # 列出所有 loop
/run-plan                                      # 计划执行（内部走 loop 框架）
```

Adapter 声明式配置见 `.config/loopctl/adapters/`。新增 agent = 复制 `_TEMPLATE.json` 改 5–10 字段。

### 启动脚本（`.local/bin/`）

| 脚本                  | 作用                                                               |
| --------------------- | ------------------------------------------------------------------ |
| `pi`                  | Pi Agent 主入口（设置 PI\_\* 环境变量 + 按需 pnpm install + exec） |
| `pi-acp`              | 自动 commit 推送工具                                               |
| `pi-update`           | Pi Agent 更新脚本                                                  |
| `kb`                  | 知识库 CLI（只读查询）                                             |
| `loopctl`、`loop_lib` | 循环框架                                                           |

### 辅助脚本（`.local/share/pi/scripts/`）

| 脚本                   | 作用                                                        |
| ---------------------- | ----------------------------------------------------------- |
| `subagent-wrapper.sh`  | subagent 执行包装：解析 frontmatter、构造 pi 命令、捕获输出 |
| `extract-pi-result.py` | Pi JSON 流解析器                                            |
| `read-crush-key.sh`    | 从 crush.json 读取 provider API key                         |

### Crush（`.config/crush/`）

```
.config/crush/
├── crush.json              # Crush 核心配置
├── bin/                    # Crush 辅助脚本
└── hooks/                  # Crush hook 脚本
```

### 共享 Agent 基础设施（`.config/agents/`）

```
.config/agents/
├── context/                # 全局上下文（global-context 扩展读取）
│   ├── 01-language.md
│   └── 02-ultilities.md
├── skills/                 # 本仓库自维护 skills
│   ├── emacs-config/
│   ├── knowledge-base/
│   └── pack-guix/
└── skillsets/              # 上游 skills 集（均为 git submodule）
    ├── agent-skills/       # github.com/addyosmani/agent-skills
    ├── emacs-skills/       # github.com/xenodium/emacs-skills
    ├── mattpocock-skills/  # github.com/mattpocock/skills
    └── pi-skills/          # github.com/badlogic/pi-skills
```

### Hermes（`.local/share/hermes/`）

> 实现位置：`source/nix/configuration/programs/hermes.nix` 装 hermes-agent `full` + `desktop` 输出；`source/information.scm` 的 `%data-dirs` 加 `.local/share/hermes` 保证 bind-mount 持久化。

Hermes Agent（[hermes-agent.nousresearch.com](https://hermes-agent.nousresearch.com)）—— Nous Research 出品的 self-improving AI agent，CLI / TUI / Web Dashboard / Desktop 共用同一份 config、sessions、skills 与 memory。**nix flake install** 装 `full` 变体（含所有 providers、messaging platform libraries、voice）+ 独立的 `desktop` 输出。

## 修改约束

- **pi 扩展必须是单文件 `index.ts`**：Guix Home stow 逐文件软链接到 `/gnu/store/`，导致 jiti 的相对路径 `import` 断裂。
- **修改 `agents/*.md`**：直接编辑；frontmatter 中的 `model` 必须使用已配置或 Pi 内置可用的 provider/model；保留 scout/researcher 的 deepseek 路由
- **修改 `agents/*.md` 的 `thinking`**：仅对确认支持 thinking 的模型设置
- **修改 `settings.json` / `mcp.json` / `models.json`**：必须同步更新本文件相应表格
- **修改 `extensions/`**：当前为直接加载的 TypeScript 文件，修改后重启 Pi Agent 会话并用 `pi --help` / 语法检查验证
- **新增 npm 包**：加入 `settings.json` 的 `packages` 数组，并在本文件记录其配置项
- **删除 npm 包**：同步从 `settings.json` 移除其配置项，并更新本文件
- **修改 hermes `config.yaml` / `SOUL.md`**：直接编辑 `dotfiles/enable/agents/.local/share/hermes/`；新增运行时目录（`skills/` 等）由 hermes 自管理，**不要**在 dotfile 仓库内创建空目录（stow 软链接会导致 git 污染）。改后必须 `blue home` 让 dotfile stow 重建软链接。
