<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# mcode — MiniMax Code CLI 入口

源码 `dotfiles/mutable/agents/minimax-code/.local/bin/mcode` · 部署 `~/.local/bin/mcode`（mutable，改源即时生效） · 调用方：终端直接调用

只做四件事：注入 `AGENTS_ROOT`、首跑或 `--install` 时 `pnpm install`、把 `tools` 分发到上游第二 bin、把 manifest 与 lockfile 回源。依赖 `pnpm` 与 `node`（上游硬性要求 `>=22.19 <23 || >=24 <27`）。本包不托管配置层，上游登录态与 sessions 由其 CLI 按 XDG 惯例自管。

## 用法

```bash
mcode [args...]        # 透传 @minimax-ai/code
mcode --install        # 无人值守安装 CLI 并回源
mcode tools [args...]  # 上游第二 bin mcode-tools（host-managed Connector tools）
```

CLI 缺失时交互终端先问一句（`[y/N]`，拒绝则退出码 130），非交互直接装；缺 pnpm 或缺 `package.json` 报错退出。安装树在 `$AGENTS_ROOT/minimax-code`（默认 `~/.local/share/agents/minimax-code`），`node_modules` 是部署侧产物；`pnpm-workspace.yaml` 承载 pnpm 12 策略，`package.json` 与 `pnpm-lock.yaml` 在仓库留副本，lockfile 被 `.stow-local-ignore` 剪枝（pnpm 拒写软链 lockfile），由 wrapper 回源。

## 实现与约束

- **两个 pnpm 12 策略坑的处置**：`pnpm-workspace.yaml` 里 `minimumReleaseAge: 0` 与 `allowBuilds`（`@minimax-ai/code`、`better-sqlite3`）都要在位，缺一个就装得上但跑不起来（成因见 `dotfiles/mutable/agents/minimax-code/AGENTS.md`）。上游新增原生依赖时，把 pnpm 输出的 `Ignored build scripts:` 名单照抄进 `allowBuilds` 再 `mcode --install`。
- **`sync_to_source` 回源**：`package.json`、`pnpm-workspace.yaml` 被 pnpm 原子写换成实体文件时，内容归源并重建软链；`pnpm-lock.yaml` 只回拷内容、仓库副本缺失时新建。`--install` 后与每次调用尾部各跑一次，`cmp` 有差才动。通用配方与不变量见 `dotfiles/mutable/AGENTS.md`「新增 pnpm 系 agent 的完整配方」，本篇不复述。
- **上游第二 bin 非遮蔽**：`mcode-tools` 与主 CLI 同包发布，按一包一入口不单独占 `~/.local/bin`，经 `mcode tools` 分发直调。
- **升级走仓库源，不走上游自更新**：改仓库 `package.json` → `mcode --install` → 验证 → 提交（lockfile 自动回源）。上游 `update` 不回源 manifest，不要用它（成因见包内 AGENTS.md）。
- **无 fish 补全**：上游未提供 completion 生成命令，不虚构补全文件。本篇只留「做什么」，「为什么」单向指回 `dotfiles/mutable/agents/minimax-code/AGENTS.md`，两处不各写一遍论证。

## 排障

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 安装输出 `Ignored build scripts: ...` | pnpm 12 默认拦 build scripts | 名单抄进 `pnpm-workspace.yaml` 的 `allowBuilds` 后 `mcode --install` |
| 开会话报 SQLite binding 缺失 | 绑定没建成（build 被拦或 ABI 不匹配） | `mcode --install` 重装；postinstall 会给 ABI/glibc 诊断 |
| postinstall 报 Unsupported Node.js | node 不在 `>=22.19 <23 \|\| >=24 <27` | 换 node |
| 仓库 manifest / lockfile 不回源 | 只在部署侧裸跑过 pnpm | 跑 `mcode --install` 或任意 `mcode` 命令触发回源 |
| `mcode update` 后行为异常 | 上游自更新不过本 wrapper | 以仓库源为真源：手动改 `package.json` + `--install`，核对 `mcode --version` |