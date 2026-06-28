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
│   ├── loopctl/
│   │   ├── adapters/
│   │   │   ├── README.md
│   │   │   ├── _TEMPLATE.json
│   │   │   ├── claude-code.json
│   │   │   ├── codex.json
│   │   │   ├── crush.json
│   │   │   ├── omp.json
│   │   │   ├── opencode.json
│   │   │   └── pi.json
│   │   └── docs/
│   │       ├── examples/
│   │       ├── README.md
│   │       ├── adapter.md
│   │       └── extract.md
│   └── opencode/
│       ├── commands/
│       │   ├── plannotator-annotate.md
│       │   ├── plannotator-archive.md
│       │   ├── plannotator-last.md
│       │   └── plannotator-review.md
│       ├── scripts/
│       │   └── update-plugins.sh
│       ├── .gitignore
│       ├── dcp.jsonc
│       ├── opencode-mem.jsonc
│       └── opencode.json
├── .local/
│   └── bin/
│       ├── loop_lib/
│       │   ├── extract/
│       │   ├── templates/
│       │   ├── tests/
│       │   ├── adapter-cmds.sh
│       │   ├── agent.sh
│       │   ├── common.sh
│       │   ├── log.sh
│       │   ├── prompt.sh
│       │   └── state.sh
│       └── loopctl
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

> **oh-my-pi (OMP)** 不再从此目录部署。它是 `jeans` 频道的 `oh-my-pi-bin` 单 ELF 二进制，由 `guix-home` 的 `home-packages` 暴露为 `omp` 命令。运行时配置走 OMP 自身约定路径，本仓库不托管。
>
> **pi-coding-agent** 的配置已整体迁至 `stow/pi/`（GNU Stow 直链部署），详情见 `stow/AGENTS.md` 的 pi 包条目。loopctl 适配器 `adapters/pi.json` 与 `adapters/omp.json` 共存。
>
> **知识库体系 (`kb`)** —— CLI 与 `kb_lib/` 数据层（含 `memory.py`、`viz`）在本目录 `.local/bin/`。**agenote 体系** 已改造为 MCP server + CLI shim，两者共享 `kb_lib` 数据层内核。agenote skill 与 pi 插件在 `stow/pi/`。

`.gitignore` 排除 `.agents/workfile`、`node_modules`、`__pycache__`。文档类的 `AGENTS.md` / `README.md` 由 `home-dotfiles-service-type` 的 `excluded` 规则排除，不会进入 `~`。

## oh-my-pi / OMP（Guix 包 `oh-my-pi-bin`）

OMP 是 Pi 的 batteries-included fork，单 ELF 二进制（≈530 MB），由 `jeans` 频道提供。`source/config.org` 的 `home-packages` 已收纳，通过 `omp` 命令暴露。

**路径约定**（在 `config.org` XDG session-variables 块声明）：

| 路径                                                          | 用途                         |
| ------------------------------------------------------------- | ---------------------------- |
| `$PI_CONFIG_DIR` (`~/.config/pi/omp`)                         | 配置文件目录（providers 等） |
| `$PI_CODING_AGENT_DIR` (`~/.config/pi`)                       | 兼容 Pi 的主目录             |
| `$PI_CODING_AGENT_SESSION_DIR` (`~/.local/share/pi/sessions`) | 会话持久化                   |

**本仓库不托管 OMP 配置源**——OMP 是 batteries-included 单二进制，用户本地维护 `~/.config/pi/omp/`。

### Loop 体系（loopctl）

跨 agent 长期迭代循环，通过 `.config/loopctl/` 与 `.local/bin/loopctl` 管理。Adapter 定义在 `adapters/`：`claude-code` / `codex` / `crush` / `omp` / `opencode` / `pi`。新增 agent = 复制 `_TEMPLATE.json`。

### 启动脚本

| 脚本          | 作用                                         |
| ------------- | -------------------------------------------- |
| `kb`          | 知识库 CLI                                   |
| `agenote_mcp` | agenote MCP server（FastMCP, 17 tools）      |
| `agenote_cli` | agenote CLI shim（纯 stdlib，供 hooks 调用） |
| `loopctl`     | 跨 agent 循环框架入口                        |

### Crush（`.config/crush/`）

`crush.json` + `bin/` + `hooks/`。详见 Crush 自身文档。

## 修改约束

- **OMP**：不托管在仓库内，直接编辑 `~/.config/pi/omp/` 本地维护
- **Hermes**：改 `stow/hermes/` 即生效（GNU Stow 直链），无需 `blue home`
- **loopctl adapter**：改 `adapters/<name>.json` 后用 `loopctl adapter test <name>` 验证
