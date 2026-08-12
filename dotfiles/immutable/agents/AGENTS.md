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
│   │   ├── anchors-lib.sh
│   │   └── anchors.json
│   └── crush/
│       ├── bin/
│       │   ├── bash-language-server
│       │   ├── context7-mcp
│       │   ├── filesystem-mcp
│       │   ├── mcp-server-memory
│       │   ├── mcp-server-sequential-thinking
│       │   ├── typescript-language-server
│       │   ├── vscode-css-language-server
│       │   ├── vscode-eslint-language-server
│       │   ├── vscode-html-language-server
│       │   ├── vscode-json-language-server
│       │   └── vscode-markdown-language-server
│       ├── hooks/
│       │   ├── bash-gate.sh
│       │   └── edit-gate.sh
│       └── crush.json
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

| 脚本          | 作用                                                                                                                              |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `kb`          | 知识库 CLI                                                                                                                        |
| `agenote`     | 知识库 CLI（agenote card + memory 操作）。由 `uv tool install` 提供（仓库 `github.com/ShineBreaker/agenote`），**不在本 stow 包** |
| `agenote-cli` | agenote CLI shim（供 omp-hooks 扩展 execSync 调用）。同上，由 uv tool 提供                                                        |
| `loopctl`     | 跨 agent 循环框架入口                                                                                                             |

### Crush（`.config/crush/`）

`crush.json` + `bin/` + `hooks/`。`hooks/` 两个脚本（`bash-gate.sh` / `edit-gate.sh`）`source` 共享的 `~/.config/agents/anchors-lib.sh`（见下「共享基础设施」），从合并后的 anchors.json 读取冻结规则，行为对齐 pi-gate（`checkBashCommand` / `checkProtectedPath`）。

### 共享基础设施（`.config/agents/`）

`anchors.json`（规则）+ `anchors-lib.sh`（协议无关的加载/合并库）。lib 完成分层 ratchet 合并（全局 + 项目级，数组并集、映射近层覆盖远层、`sensitive_patterns` 按 `pattern` 去重）。三方消费者（pi-gate TS、crush 两 bash hook、zcode 三 bash hook）共享此 lib 与 anchors.json 单一真相源。

**分层职责**：

- **全局 `~/.config/agents/anchors.json`**（meta-frozen）：跨所有 workspace 的通用 agent 约束 — `sudo`、`interactive_commands`（vi/less/man… 出现即禁）、`bare_repl_commands`（python/node 裸调用禁）、`sensitive_patterns`（sk-/密码/私钥/AWS/GitHub token）
- **项目级 `<root>/.agents/anchors.json`**（agent 可写，ratchet 加码）：仓库专属 — `frozen_commands` / `frozen_paths` / `redirect_conventions` / `path_hints` / `human_only_actions` / `anchor_measurements`
- **代码底层（各 hook 脚本硬编，恒定生效）**：rm 破坏性防护、git 写操作限制（commit 需 -m / 禁 add -p / 禁 rebase -i）、~~/.config·~~/.local 部署位置保护

调整通用约束改全局 anchors.json；仓库规则改项目级；pi-gate / crush / zcode 三方同步生效。

## 修改约束

- **loopctl adapter**：改 `adapters/<name>.json` 后用 `loopctl adapter test <name>` 验证
