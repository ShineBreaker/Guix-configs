# Agent 资产配置

本目录集中管理本仓库用到的 Agent 相关配置：Crush、共享的 anchors 基础设施。统一通过 Guix Home 的 `home-dotfiles-service-type`（stow layout）部署到 `~/.config/`。

## 目录结构

<!-- structor:begin depth=4 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
agents/
├── .config/
│   ├── agents/
│   │   ├── context/
│   │   │   ├── 01-language.md
│   │   │   ├── 02-subagents.md
│   │   │   ├── 03-packages.md
│   │   │   ├── 04-git.md
│   │   │   └── 05-tools.md
│   │   ├── anchors-lib.sh
│   │   ├── anchors.json
│   │   └── gate-core.sh
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
├── .local/
│   └── bin/
│       └── askill
└── .gitignore
```

<!-- /structor -->

## 部署模型

```
dotfiles/immutable/agents/   → Guix Home (stow layout) → 实际路径
└── .config/
    ├── crush/                → ~/.config/crush/      # Crush 配置 + hooks + bin
    └── agents/               → ~/.config/agents/     # 共享基础设施（context, anchors）
```

`.gitignore` 排除 `.agents/workfile`、`node_modules`、`__pycache__`。`AGENTS.md` / `README.md` 由 `home-dotfiles-service-type` 的 `excluded` 规则排除，不会进入 `~`。

### Crush（`.config/crush/`）

`crush.json` + `bin/` + `hooks/`。`hooks/` 两个脚本（`bash-gate.sh` / `edit-gate.sh`）是纯协议适配器：调用共享决策核 `~/.config/agents/gate-core.sh` 完成全部判定（见下「共享基础设施」）。

### 共享基础设施（`.config/agents/`）

`anchors.json`（规则）+ `anchors-lib.sh`（协议无关的加载/合并库）+ `gate-core.sh`（决策核）。lib 完成分层 ratchet 合并（全局 + 项目级，数组并集、映射近层覆盖远层、`sensitive_patterns` 按 `pattern` 去重）；core 承载全部判定语义（冻结命令归一化匹配、`--dry-run` 豁免仅限 blue 前缀、frozen_paths 双路径解析、frozen_globs 实装、部署位置保护、敏感信息、改写与提示），以 stdout 行协议（`BLOCK` / `SENSITIVE` / `AUTO_ALLOW` / `REWRITTEN` / 提示类）输出。三方适配器（pi-gate TS、crush 两 bash hook、zcode 两 bash hook）只做协议转换——anchors.json 与判定语义双单一真相源，修一处三方同步生效。

**分层职责**：

- **全局 `~/.config/agents/anchors.json`**（meta-frozen）：跨所有 workspace 的通用 agent 约束 — `sudo`、`interactive_commands`（vi/less/man… 出现即禁）、`sensitive_patterns`（sk-/密码/私钥/AWS/GitHub token）
- **项目级 `<root>/.agents/anchors.json`**（agent 可写，ratchet 加码）：仓库专属 — `frozen_commands` / `frozen_paths` / `redirect_conventions` / `path_hints` / `human_only_actions` / `anchor_measurements`
- **代码底层（gate-core.sh 硬编，恒定生效）**：rm 破坏性防护、git 写操作限制（commit 需 -m / 禁 add -p / 禁 rebase -i）、~/.config/ 和 ~/.local/ 部署位置保护、只读命令白名单

调整通用约束改全局 anchors.json；仓库规则改项目级；判定语义改 gate-core.sh——pi-gate / crush / zcode 三方同步生效。

### Skills — 第三方 agent skills 声明式管理（askill）

本包仅含 `askill` 管理脚本（`.local/bin/askill`，部署为 `~/.local/bin/askill`）。第三方 skills 的锁真身在 `dotfiles/mutable/agents/skills/`（Stow 单文件直链到 `~/.config/agents/skills/skills-lock.json`，npx 写锁即写仓库源，git diff 直接可见）：

- `askill add <repo> -s <name>` / `askill update` / `askill install` / `askill remove` / `askill list`
- 工作区 = 部署位置 `~/.config/agents/skills/`（npx cwd；`computedHash` 基线，ref 跟踪最新，版本冻结由 git 提交承担）
- `~/.config/agents/skills/.agents/skills/` 为 npx 暂存区；锁外目录（agenote/emacs 等自建 skill）不经 askill 触碰
- 已知坑：`heygen-com/hyperframes` 仓库过大，git clone 必被 TLS 掐断且 LFS 内容被剥离；更新该源用 `gh api repos/heygen-com/hyperframes/tarball/main` 解出 `skills/` 后拷入暂存区，再 `askill sync`
