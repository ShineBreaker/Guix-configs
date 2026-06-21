# Agent 资产配置

本目录集中管理本仓库用到的所有 Agent 相关配置：Pi Agent、Crush、共享的 KB / loopctl 基础设施、跨 agent 技能集（submodule）。统一通过 Guix Home 的 `home-dotfiles-service-type`（stow layout）部署到 `~/.config/`、`~/.local/` 等路径。

## 目录结构

<!-- structor:begin -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
agents/
├── .config/
│   ├── agents/
│   │   ├── context/
│   │   │   ├── 01-language.md
│   │   │   └── 02-ultilities.md
│   │   └── skills/
│   │       ├── emacs-config/
│   │       ├── knowledge-base/
│   │       └── pack-guix/
│   ├── crush/
│   │   ├── bin/
│   │   │   ├── bash-language-server
│   │   │   ├── context7-mcp
│   │   │   ├── filesystem-mcp
│   │   │   ├── mcp-server-memory
│   │   │   ├── mcp-server-sequential-thinking
│   │   │   ├── typescript-language-server
│   │   │   ├── vscode-css-language-server
│   │   │   ├── vscode-eslint-language-server
│   │   │   ├── vscode-html-language-server
│   │   │   ├── vscode-json-language-server
│   │   │   └── vscode-markdown-language-server
│   │   ├── hooks/
│   │   │   ├── bash-gate.sh
│   │   │   └── edit-gate.sh
│   │   └── crush.json
│   └── loopctl/
│       ├── adapters/
│       │   ├── README.md
│       │   ├── _TEMPLATE.json
│       │   ├── claude-code.json
│       │   ├── codex.json
│       │   ├── crush.json
│       │   ├── omp.json
│       │   └── opencode.json
│       └── docs/
│           ├── examples/
│           ├── README.md
│           ├── adapter.md
│           └── extract.md
├── .local/
│   ├── bin/
│   │   ├── kb_lib/
│   │   │   ├── __pycache__/
│   │   │   ├── viz/
│   │   │   ├── __init__.py
│   │   │   ├── cards.py
│   │   │   ├── core.py
│   │   │   └── lint.py
│   │   ├── loop_lib/
│   │   │   ├── extract/
│   │   │   ├── templates/
│   │   │   ├── tests/
│   │   │   ├── adapter-cmds.sh
│   │   │   ├── agent.sh
│   │   │   ├── common.sh
│   │   │   ├── log.sh
│   │   │   ├── prompt.sh
│   │   │   └── state.sh
│   │   ├── kb
│   │   └── loopctl
│   └── share/
│       ├── applications/
│       │   └── hermes.desktop
│       └── hermes/
└── .gitignore
```

<!-- /structor -->

## 部署模型

```
dotfiles/enable/agents/      → Guix Home (stow layout) → 实际路径
├── .config/
│   ├── crush/                → ~/.config/crush/      # Crush 配置 + hooks + bin
│   ├── agents/               → ~/.config/agents/     # 共享基础设施（context, skills, mcp-servers）
│   └── loopctl/              → ~/.config/loopctl/    # 跨 agent 循环框架
└── .local/
    ├── bin/                  → ~/.local/bin/         # 启动脚本（kb、loopctl 等）
    └── share/                → ~/.local/share/       # applications/hermes.desktop、hermes 运行时数据
```

> **oh-my-pi (OMP)** 不再从此目录部署。它是 Guix 频道 `jeans` 的 `oh-my-pi-bin`（v16.1.6）单 ELF 二进制，由 `guix-home` 的 `home-packages` 直接暴露为 `omp` 命令。运行时配置（settings/agents/prompts 等）走 OMP 自身约定路径，本仓库不再托管。

`.gitignore` 排除 `.agents/workfile`、`node_modules`、`__pycache__`。文档类的 `AGENTS.md` / `README.md` 由 `home-dotfiles-service-type` 的 `excluded` 规则排除，不会进入 `~`。

## oh-my-pi / OMP（Guix 包 `oh-my-pi-bin`）

OMP（[can1357/oh-my-pi](https://github.com/can1357/oh-my-pi)）是 Pi 的 batteries-included fork：单 ELF 二进制（≈530 MB，内嵌 Bun runtime + native addons），覆盖 IDE 集成、40+ providers、32 内置工具、13 LSP、27 DAP、原生 subagent、web 搜索、浏览器自动化等。

**包来源**：jeans 频道 `jeans/packages/tools.scm::oh-my-pi-bin`，已被 `source/config.org` 的 `home-packages` 收纳（line 1144）。`guix-home` rebuild 后通过 `/home/brokenshine/.guix-home/profile/bin/omp` 暴露。

### 路径与运行时约定

| 路径                                   | 用途                                                          |
| -------------------------------------- | ------------------------------------------------------------- |
| `$PI_CONFIG_DIR` (`$XDG_CONFIG_HOME/pi/omp`) | OMP 自身约定的配置文件目录（providers、agents、skills 等） |
| `$PI_CODING_AGENT_DIR` (`$XDG_CONFIG_HOME/pi`) | 兼容 Pi 的主目录，OMP 作为 fork 通常仍识别                |
| `$PI_CODING_AGENT_SESSION_DIR` (`$XDG_DATA_HOME/pi/sessions`) | 会话持久化目录                                       |

以上三条 env 在 `source/config.org` 的 XDG session-variables 块声明（line 1838-1841），由 `guix-home` 在 shell 启动时注入。

### 自定义配置的边界

> **本仓库不托管 OMP 配置源**——理由：OMP 是单二进制、内置完整扩展生态，"batteries-included" 的精神就是让用户少操心配置工程。需要在 `~/.config/pi/omp/` 下放自定义文件（providers / agents / skills 等）时，由用户本地维护，**不进仓库**。

如确实需要把 OMP 的某类配置工程化（如自定义 provider 列表、agents 模板），建议：

1. 在 `dotfiles/enable/agents/.config/omp/`（新增）下放配置源
2. 在 `dotfiles-services` 的 `(packages ...)` 列表里加 `"omp"`
3. `blue home` 部署

但默认不做——保持仓库精简。

### Loop 体系（loopctl）

跨 agent 长期迭代循环（接力棒模型）通过 `.config/loopctl/` 与 `.local/bin/loopctl` 管理：

```text
/loop <name> start --task '...' --adapter omp    # 创建 loop
/loop <name> step                                # 跑一轮
/loop <name> status                              # 查看状态
/loop list --all                                 # 列出所有 loop
/run-plan                                        # 计划执行（内部走 loop 框架）
```

Adapter 声明式配置见 `.config/loopctl/adapters/`。当前内置：`claude-code` / `codex` / `crush` / **omp** / `opencode`。新增 agent = 复制 `_TEMPLATE.json` 改 5–10 字段。

### 启动脚本（`.local/bin/`）

| 脚本          | 作用                              |
| ------------- | --------------------------------- |
| `kb`          | 知识库 CLI（只读查询）            |
| `loopctl`     | 跨 agent 循环框架入口             |

OMP 自身通过 Guix profile 直接以 `omp` 命令暴露，不需要 wrapper。

### Crush（`.config/crush/`）

```
.config/crush/
├── crush.json              # Crush 核心配置
├── bin/                    # Crush 辅助脚本
└── hooks/                  # Crush hook 脚本
```

### Hermes（`.local/share/hermes/`）

> 实现位置：`source/nix/configuration/programs/hermes.nix` 装 hermes-agent `full` + `desktop` 输出；`source/information.scm` 的 `%data-dirs` 加 `.local/share/hermes` 保证 bind-mount 持久化。

Hermes Agent（[hermes-agent.nousresearch.com](https://hermes-agent.nousresearch.com)）—— Nous Research 出品的 self-improving AI agent，CLI / TUI / Web Dashboard / Desktop 共用同一份 config、sessions、skills 与 memory。**nix flake install** 装 `full` 变体（含所有 providers、messaging platform libraries、voice）+ 独立的 `desktop` 输出。

## 修改约束

- **OMP 自身配置**：OMP 是 Guix 包，不在本仓库 dotfiles 范围。如需自定义 OMP（providers/agents/skills 等），直接编辑 `~/.config/pi/omp/` 下文件，**不进仓库**。除非未来需要把某类配置工程化（如团队共享的 provider 列表），再单独建 `dotfiles/enable/agents/.config/omp/` 子目录并加到 `dotfile-services` 的 `packages` 列表。
- **修改 hermes `config.yaml` / `SOUL.md`**：直接编辑 `dotfiles/enable/agents/.local/share/hermes/`；新增运行时目录（`skills/` 等）由 hermes 自管理，**不要**在 dotfile 仓库内创建空目录（stow 软链接会导致 git 污染）。改后必须 `blue home` 让 dotfile stow 重建软链接。
- **修改 `adapters/omp.json`**：loopctl 调 OMP 的协议配置。改字段前先跑 `loopctl adapter test omp` 验证（如果 OMP 当前 CLI 参数不兼容 `args_template`，会立即暴露）。
