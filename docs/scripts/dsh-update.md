<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# dsh update — 本体与插件一键更新

- 源码：`dotfiles/mutable/agents/dsh/.local/libexec/dsh-update`
- 部署：`~/.local/libexec/dsh-update`（mutable，改源即时生效；经 `dsh update` 分发触达）
- 调用方：`dsh update` 子命令分发

## 用法

```bash
dsh update            # 交互确认后更新本体 + web profile 插件
dsh update --check    # 只检查（0=已最新，1=有更新），不修改
dsh update -y|--yes   # 跳过确认
dsh update --restart  # 完成后 dsh web --reauth 重启服务
```

## 依赖

`pnpm`、`python3`（package.json 解析）、`git`（github: 锁 commit 依赖的 `ls-remote` 查询）、`npm`（registry 版本探测）。

## 工作原理

- **更新目标**：插件清单从 `profiles/web/package.json` 的 dependencies 动态读取（全量保序）。三类源码：
  - `npm`（registry 版本可比）：选版**不跟 latest tag**——dsh 全是 preview 版本，发布者把 latest 停在保守位；按通道稳定性 `latest → next → beta → alpha` 取第一个高于当前的版本，来源通道打印供核对。
  - `github:<owner>/<repo>#<sha>`（锁 commit）：`git ls-remote` 查上游 HEAD，换 commit 前先把 `pnpm-workspace.yaml` 里 `allowBuilds` 的旧 key 迁到新 commit——**key 绑定 commit，不迁则 prepare 不放行**。
  - `git+`/`git@`/`file:`/`link:` 等其余锁定源码：只列出提醒，人工确认后升级。
- **精确版本兜底**：两侧 `pnpm-workspace.yaml` 的 `saveExact: true` 作用于一切 `pnpm add` 通道，命令行仍带 `-E` 双保险——pnpm 默认写 `^`，那是 dsh-context 0.47 静默升到不兼容版本的成因。显式 `pnpm add <pkg>@<ver>` 时 pnpm 自动把 24h 冷却期内的版本写进 `minimumReleaseAgeExclude`，冷却豁免不用手写。
- **lockfile 回源**：部署侧 lockfile 是真实文件（pnpm Rust 端拒写软链 lockfile），每次 pnpm 跑完自动拷回仓库源，git 里始终是可复现的锁；源目录从包内 `$0` 反推。
- 更新后须重启 `dsh web` 生效（host 半边不热载）；`--restart` 调 `dsh web --reauth`。
- `--check` 纯探测（不碰任何文件），退出码可作 CI/脚本判断。

## 设计决策与不变量

- **`pnpm add` 更新而不手改 package.json**：版本号来源单一（pnpm 的 registry 解析），手写会与 lockfile/saveExact 脱钩。
- **allowBuilds 迁移在换 commit 之前**：`pnpm-workspace.yaml` 的 `allowBuilds` key 形如 `<pkg>@<sha>`，绑定旧 commit；直接换 spec 后 prepare 会被冷却/门禁拦掉。
- **`grep | head` 管道必须 `|| true`**：`set -euo pipefail` 下无匹配时 grep 返回 1，曾导致 `migrate_allow_builds` 在「已是新 key」的正常场景中途退出、连带 `--restart` 到不了重启路径（本次修复，见变更记录）。

## 故障排查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `--check` 报有更新但更新失败 | 目标版本仍在 24h `minimumReleaseAge` 冷却 | 等待或显式豁免（pnpm 自动写 `minimumReleaseAgeExclude`） |
| 插件 `prepare` 被拦 | allowBuilds key 还绑旧 commit | 检查 `pnpm-workspace.yaml`，手动迁 key |
| 更新后 web 仍是旧版 | host 不热载 | `dsh web --reauth` 或加 `--restart` |

## 变更记录

- 2026-09-29（修复）：`migrate_allow_builds` 的 `new_key=$(grep … | head -1)` 补 `|| true`——旧代码在 `allowBuilds` 无需迁移时因 pipefail 提前退出，使 `--restart`/`--yes` 后续步骤（含 lockfile 回源与 `dsh web --reauth`）整段跳过。
