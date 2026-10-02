# agents/minimax-code — MiniMax Code CLI 部署包

MiniMax Code CLI（npm 包 `@minimax-ai/code`，上游命令 `mcode`）的 Guix 部署包：映射到 `$HOME`，经 GNU Stow 逐文件软链（`--no-folding`），改源即时生效。**只托管入口 wrapper 与安装清单，不托管配置层**——上游登录态/sessions 由其 CLI 按 XDG 惯例自管。

本篇讲**包内布局与关键约束**。命令、旗标与故障排查见 [docs/scripts/minimax-code.md](../../../../docs/scripts/minimax-code.md)；安装树聚合根的通用接入配方见 `dotfiles/mutable/AGENTS.md`「Agent 运行时安装根」（本包是其范本之一）。

## 目录与文件布局

| 路径                                                   | 说明                                                                                                                       |
| ------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| `.local/bin/mcode`                                     | 唯一入口：注入 `AGENTS_ROOT`；首跑/`--install` 自动 `pnpm install`；`tools` 子命令分发上游第二 bin；manifest/lockfile 回源 |
| `.local/share/agents/minimax-code/package.json`        | 安装清单：锁 `@minimax-ai/code` 精确版本（stow 软链到部署侧 `~/.local/share/agents/minimax-code/`）                        |
| `.local/share/agents/minimax-code/pnpm-workspace.yaml` | pnpm 12 三项策略：`minimumReleaseAge: 0` + `saveExact: true` + `allowBuilds`（理由见「关键约束 2」）                       |
| `.local/share/agents/minimax-code/pnpm-lock.yaml`      | lockfile 副本：部署侧真实文件的回源记录（stow ignore 不链出，wrapper 每次安装/调用后同步）                                 |

## 关键约束

### 1. 上游硬性 node 范围

`engines: node >=22.19 <23 || >=24 <27`——node 23 无预编译 SQLite 运行时。postinstall `verify-native-install.mjs` 会在安装时自检 node 版本与 glibc/ABI 兼容（Node 24 = ABI 137 → glibc >= 2.29）并对 better-sqlite3 做 `:memory:` 冒烟。Guix profile 现为 v24.18.0，满足。换 node 前先核这条区间。

### 2. 两个 pnpm 12 策略坑（装不上与跑不了都源于此）

- **`minimumReleaseAge: 0`**——pnpm 12 默认 24h 供应链冷却，会把**发布不满一天的新版本静默排除出解析**（不报错，表现为装不上或装成旧版）。0.6.2 发布当天即装时踩中。
- **`allowBuilds: {'@minimax-ai/code': true, better-sqlite3: true}`**——不批 build scripts 则 better-sqlite3 的原生绑定缺失，`--version`/`--help` 都正常但**一开会话就炸**。上游新增原生依赖时，把安装输出的 `Ignored build scripts:` 名单抄进 `allowBuilds` 再 `mcode --install`。

### 3. 升级走仓库源，不走上游自更新

`mcode update` 只换 `node_modules`，manifest 不同步回源，会让部署侧与仓库源分叉。升级流程固定为：改仓库源 `package.json` 版本 → `mcode --install` → 验证 → 提交（lockfile 由 wrapper 自动回源）。

### 4. 一包一入口

上游有两个 bin（`mcode` / `mcode-tools`），后者经 `mcode tools` 分发直调，不占第二个 `~/.local/bin` 文件。注意分发位置在安装检查之后：未安装时走统一的安装引导，不直接 127。`toolbox check` 合规（准入规则见 `dotfiles/mutable/AGENTS.md`）。

## 验证

```bash
mcode --version                        # 0.6.2（无回源噪音输出）
mcode tools --help                     # 第二 bin 分发可达
find ~/.local/share/agents/minimax-code -xtype l    # 无断链
git status --short                     # lockfile/package.json 已回源，只含预期文件
```
