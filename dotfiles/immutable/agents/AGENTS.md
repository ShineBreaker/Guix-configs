# Agent 资产配置（Crush + 共享 anchors 基础设施）

经 Guix Home（stow layout）部署到 `~/.config/`：`crush/` → Crush 配置 + hooks + bin；`agents/` → 共享基础设施（context、anchors）。

## 目录结构

<!-- structor:begin depth=2 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
agents/
├── .config/
│   ├── agents/
│   └── crush/
└── .gitignore
```

<!-- /structor -->

## 共享决策核架构

`anchors.json`（规则）+ `anchors-lib.sh`（协议无关的加载/合并库：分层 ratchet 合并，数组并集、映射近层覆盖远层）+ `gate-core.sh`（决策核：冻结命令归一化匹配、`--dry-run` 豁免仅限 blue 前缀、frozen_paths/globs、部署位置保护、敏感信息判定，以 stdout 行协议输出 `BLOCK`/`SENSITIVE`/`AUTO_ALLOW`/`REWRITTEN`/提示）。四方适配器（pi-gate TS、crush 两 bash hook、zcode 两 bash hook、hermes gate py 插件）**只做协议转换**——规则与判定语义双单一真相源，修一处四方同步生效。

**分层职责**：

- 全局 `~/.config/agents/anchors.json`（meta-frozen）：跨 workspace 通用约束——`sudo`、`interactive_commands`、`sensitive_patterns`
- 项目级 `<root>/.agents/anchors.json`（agent 可写，ratchet 加码）：仓库专属——`frozen_commands`/`frozen_paths`/`redirect_conventions`/`path_hints`/`human_only_actions` 等
- gate-core.sh 硬编（恒定生效）：rm 破坏性防护、git 写操作限制、`~/.config`/`~/.local` 部署位置保护、只读命令白名单

改通用约束→全局 anchors.json；改仓库规则→项目级；改判定语义→gate-core.sh。

## Skills — askill 声明式管理

askill 脚本本体由 `dotfiles/mutable/agents/skills/` 包部署（`.local/bin/askill`）；第三方 skills 锁真身也在该包（Stow 单文件直链 skills-lock.json，npx 写锁即写仓库源）：

- `askill add <repo> -s <name>` / `update` / `install` / `remove` / `list`
- 工作区 = 部署位 `~/.config/agents/skills/`（npx cwd；版本冻结由 git 提交承担）
- `~/.config/agents/skills/.agents/skills/` 是 npx 暂存区；锁外目录（自建 skill）不经 askill
- 已知坑：`heygen-com/hyperframes` 仓库过大，git clone 必被 TLS 掐断且 LFS 内容被剥离；用 `gh api repos/heygen-com/hyperframes/tarball/main` 解出 `skills/` 拷入暂存区再 `askill sync`
