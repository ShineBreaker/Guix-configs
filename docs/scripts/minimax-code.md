<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# mcode — MiniMax Code CLI 入口

- 源码：`dotfiles/mutable/agents/minimax-code/.local/bin/mcode`
- 部署：`~/.local/bin/mcode`（mutable，改源即时生效）
- 调用方：终端直接调用；`mcode tools` 分发上游第二 bin（见下）

## 用法

```bash
mcode [args...]        # 透传 @minimax-ai/code（init/exec/acp/login/plugin/update 等）
mcode --install        # 安装 CLI（$AGENTS_ROOT/minimax-code 里 pnpm install）
mcode tools [args...]  # 上游第二 bin mcode-tools（host-managed Connector tools）
```

## 依赖

`pnpm`（安装）、`node`（上游硬性要求 `>=22.19 <23 || >=24 <27`，本机 v24.18.0）。CLI 本体经 pnpm 装在 `$AGENTS_ROOT/minimax-code/node_modules/.bin/mcode`（`AGENTS_ROOT` 默认 `~/.local/share/agents`，各 agent 安装树聚合根）。

## 工作原理

- **安装树与配置分层**：CLI 本体项目在聚合根 `~/.local/share/agents/minimax-code/`；上游自身的配置（登录态、sessions）由其 CLI 按 XDG 惯例自管，本包不托管配置层。
- **stow 形态**：源里 `package.json` 与 `pnpm-workspace.yaml` 经 stow 软链到部署侧；`pnpm-lock.yaml` 仓库留副本但被 `.stow-local-ignore` 剪枝（pnpm 拒写软链 lockfile，部署侧必须真实文件），由 wrapper 回源同步。
- **回源**（`sync_to_source`）：`package.json`/`pnpm-workspace.yaml` 被 pnpm 原子写（临时文件 + rename）换成实体文件后，内容归源并重建软链；`pnpm-lock.yaml` 只回拷内容、仓库副本缺失时新建（首装即此路径生成）。`--install` 后与每次调用尾部各跑一次，cmp 有差才动。
- **上游第二 bin**：`mcode-tools` 与主 CLI 同包发布，按一包一入口不单独占 `~/.local/bin`，经 `mcode tools` 分发直调（上游原生 bin，非遮蔽）。

## 设计决策与不变量

- **`minimumReleaseAge: 0`**：0.6.2 发布当天即装，pnpm 12 默认 24h 供应链冷却会把发布不满一天的新版本**静默**排除出解析（表现为装不上或装成旧版）。
- **`allowBuilds`**：`better-sqlite3` 的原生绑定下载 + `@minimax-ai/code` 的 postinstall 原生校验（`verify-native-install.mjs`：校验 node 版本范围、glibc/ABI 兼容，并对 better-sqlite3 做 `:memory:` 冒烟）。不批 = 装得上但一开会话就 SQLite 绑定缺失。Node 24 = ABI 137 → glibc >= 2.29（Guix 满足）。
- **尾部回源**：CLI 的 `plugin`/`update` 子命令可能自举改写 manifest/lockfile，下次调用即归源；cmp 短路，无漂移时零开销。
- **无 fish 补全**：上游未提供 completion 生成命令（与 dsh/pi 一致），不虚构补全文件。

## 故障排查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 安装输出 `Ignored build scripts: ... better-sqlite3` | pnpm 12 默认拦 build scripts | 名单已固化在 `pnpm-workspace.yaml` 的 `allowBuilds`；若上游新增原生依赖，照抄名单后 `mcode --install` |
| 开会话报 SQLite binding 缺失 / `better_sqlite3.node` 找不到 | 绑定没建成（build 被拦或 ABI 不匹配） | `mcode --install` 重装；postinstall 校验会给出 ABI/glibc 诊断 |
| 仓库 lockfile/package.json 不回源 | 只在部署侧裸跑过 pnpm | 跑 `mcode --install` 或任意 `mcode` 命令触发回源 |
| postinstall 报 Unsupported Node.js | node 不在 22.19+/24-26 | 上游硬性范围，换 node（guix profile 现为 v24.18.0） |
| `mcode update` 升级后行为异常 | 上游自更新不过本 wrapper | 自更新只换 node_modules；manifest 仍以仓库源为真源，`mcode --version` 与仓库 `package.json` 不一致时以手动改源 + `--install` 为准 |

## 变更记录

- 2026-10-02：首次安装 0.6.2（发布当日，`minimumReleaseAge: 0` 与 `allowBuilds` 两个 pnpm 12 策略坑同场踩平；lockfile 首装即回源生成）。
