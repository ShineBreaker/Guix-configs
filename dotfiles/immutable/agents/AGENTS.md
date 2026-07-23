# Agent 资产配置

本目录集中管理本仓库用到的所有 Agent 相关配置：Pi Agent、Crush、共享的 KB / loopctl 基础设施、跨 agent 技能集（submodule）。统一通过 Guix Home 的 `home-dotfiles-service-type`（stow layout）部署到 `~/.config/`、`~/.local/` 等路径。

## 目录结构

<!-- structor:begin depth=4 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
agents/
├── .config/
│   ├── agents/
│   │   ├── context/
│   │   │   ├── 01-language.md
│   │   │   └── 02-ultilities.md
│   │   └── anchors.json
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
│   │   │   └── opencode.json
│   │   └── docs/
│   │       ├── examples/
│   │       ├── README.md
│   │       ├── adapter.md
│   │       └── extract.md
│   ├── omp/
│   │   ├── extensions/
│   │   │   ├── agenote-hooks/
│   │   │   ├── global-context/
│   │   │   └── pi-gate/
│   │   ├── .gitignore
│   │   ├── APPEND_SYSTEM.md
│   │   ├── config.yml
│   │   ├── global-context.json
│   │   ├── mcp.json
│   │   └── models.yml
│   └── opencode/
│       ├── commands/
│       │   ├── plannotator-annotate.md
│       │   ├── plannotator-archive.md
│       │   ├── plannotator-last.md
│       │   └── plannotator-review.md
│       ├── scripts/
│       │   └── update-plugins.sh
│       ├── dcp.jsonc
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
dotfiles/immutable/agents/   → Guix Home (stow layout) → 实际路径
├── .config/
│   ├── crush/                → ~/.config/crush/      # Crush 配置 + hooks + bin
│   ├── agents/               → ~/.config/agents/     # 共享基础设施（context, skills）
│   └── loopctl/              → ~/.config/loopctl/    # 跨 agent 循环框架
└── .local/
    ├── bin/                  → ~/.local/bin/         # 启动脚本（kb、loopctl 等）
    └── share/                → ~/.local/share/       # applications/hermes.desktop、hermes 运行时数据
```

`.gitignore` 排除 `.agents/workfile`、`node_modules`、`__pycache__`。文档类的 `AGENTS.md` / `README.md` 由 `home-dotfiles-service-type` 的 `excluded` 规则排除，不会进入 `~`。

### Loop 体系（loopctl）

跨 agent 长期迭代循环，通过 `.config/loopctl/` 与 `.local/bin/loopctl` 管理。Adapter 定义在 `adapters/`：`claude-code` / `codex` / `crush` / `omp` / `opencode`。新增 agent = 复制 `_TEMPLATE.json`。

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

- **loopctl adapter**：改 `adapters/<name>.json` 后用 `loopctl adapter test <name>` 验证
