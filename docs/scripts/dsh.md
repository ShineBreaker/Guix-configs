<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# dsh — DeepSeek Harness CLI wrapper（含 `dsh tui`）

- 源码：`dotfiles/mutable/agents/dsh/.local/bin/dsh`、`dotfiles/mutable/agents/dsh/.local/libexec/dsh-tui`
- 部署：`~/.local/bin/dsh`（mutable，改源即时生效）
- 调用方：终端直接调用；`dsh web`/`dsh update`/`dsh tui` 分发到同包 libexec（见 `dsh-web.md`、`dsh-update.md`）；桌面入口经 `dsh web` 拉起

## 用法

```bash
dsh                # CLI 透传
dsh --install      # 安装 CLI（_cli 里 pnpm install）
dsh update|web|tui # Guix 增强子命令 → libexec/{dsh-update,dsh-web,dsh-tui}
```

`tui` 子命令透传全部参数给 launcher：`version` / `doctor` / `safe` / `update` / `--resume`。

## 依赖

`pnpm`（安装/更新）、`node`（dsh-tui 本体）、CLI 本体在 `$DSH_HOME/_cli/node_modules/.bin/dsh`。

## 工作原理

### dsh wrapper

- 本体经 pnpm 装在 `$DSH_HOME/_cli`（源只托管 `package.json` + `pnpm-workspace.yaml`，`node_modules`/lock 是部署侧运行时产物；uv tool 的 PyPI wheel 因 SEA 闭包缺包两度翻车已弃）。
- `DSH_HOME` 在脚本内注入（niri 会话环境不经 fish conf.d，语义同 conf.d 的 `10-dsh.fish`）。
- **拦截即覆写**：上游原生也有 `dsh update` / `dsh web`，首参分发把这两个名字遮蔽为 Guix 增强版。原生行为经 CLI 本体直调：`$_cli_bin update|web`（libexec 内部本就直调，无递归）。`tui` 上游没有同名子命令，无覆写问题。
- CLI 缺失时：交互终端问一句再装；非交互（desktop 入口 stdin 是 `/dev/null`）只提示 `dsh --install`，不静默联网装。
- **profile 断链自愈**（`_relink_profile`）：`dsh plugin` 的 bundles 写入和 0.1.7 起 UI 设置编辑（`cordis.patch.yml`）都走原子替换（临时文件 + rename），会把 profile 配置文件的 stow 软链换成独立文件——dependencies 进仓库源、bundles 只落部署侧。自愈分三个文件（`package.json`、`pnpm-workspace.yaml`、`cordis.patch.yml`）：断链则内容写回源再重建软链；`pnpm-lock.yaml` 反向同步（部署侧必须是真实文件，pnpm 的 Rust 端拒绝写软链 lockfile）。每次 CLI 调用结束兜底检测一遍（plugin 分支之外也兜，因为断链源不止 plugin）；`dsh web` 路径由 dsh-web 起服务前自检。源目录从 `$0` 反推（stow 布局内自洽，不从部署侧软链推导——pnpm 会把文件原地写成实体文件，链接随时不在）。
- `_cli` 的 lockfile 同理每次 pnpm 操作后自动拷回仓库源，保证 git 里是可复现的锁。

### dsh-tui launcher

- 上游 `dsh-tui` 的 bin 是双态设计：profile 内 `node_modules/@deepseek-harness-tui/dsh-tui/bin/dsh-tui.js` 那份是完整逻辑，全局 npm 安装的那份只是找到 profile 副本后委托的瘦壳。本脚本跳过瘦壳直 exec profile 内完整副本（`DSH_TUI_BIN` 可覆盖，测试用），等价于上游一键安装结果。
- launcher 独有子命令只在这一层，`dsh --profile dsh-tui` 触达不了；一包一入口规则下不新增 `dsh-tui`/`dst` 两个 bin，挂靠 `dsh tui` 是唯一合规形态。

## 设计决策与不变量

- **分发必须排在 CLI 缺失检查之前**：`dsh-update` 自身能装 CLI，`dsh-web` 的缺 CLI 报错也更友好——先检查会拦截掉这两条自举路径。
- `dsh web`/`dsh tui`/`dsh update` 用 `exec` 分发，wrapper 不残留在进程树上。
- TUI 交互要求真实 TTY（agent 会话里跑会在 ink 的 `setRawMode` 上 EIO，属预期）。

## 故障排查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `dsh tui` 报 127 | profile 内 launcher 副本缺失 | `dsh plugin --profile dsh-tui add @deepseek-harness-tui/dsh-tui@<版本>` |
| 改完 `package.json` 部署侧不生效 | stow 软链被原子写断 | 下次 `dsh` 调用自动归源重建；或 `ls -la ~/.local/share/dsh/profiles/web/` 抽查 |
| TUI 整条消失（dump-config 条目骤减） | `compatibility.json` 被删 | 恢复该文件（见包 AGENTS.md「compat 门」） |

## 变更记录

无破坏性改动（本次重构只压缩注释；`dsh update --restart` 曾到不了重启路径的缺陷在 `dsh-update` 修复，见其文档变更记录）。
