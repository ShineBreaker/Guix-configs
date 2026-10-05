<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# devin — Devin CLI 入口与 manifest 直装子命令

源码 `dotfiles/mutable/agents/devin/.local/bin/devin` · 部署 `~/.local/bin/devin`（mutable，改源即时生效）；安装树 `~/.local/share/agents/devin/`（`--install` 生成，不进仓库） · 调用方：终端直接调用

wrapper 自办安装与更新：按官方 manifest 下载 bundle、校验 sha256、解包进 agent 安装根，上游交互式自更新被遮蔽。数据与凭据不搬家，仍在 `~/.local/share/devin`（沿用历史安装，无需重新登录）。

## 用法

```bash
devin                       # 上游 TUI（未安装时先引导安装）
devin --install             # 安装 / 更新到官方 latest（幂等）
devin update [--force]      # 同 --install；--force 连当前版本一起重装
devin help <子命令>          # 上游帮助（`devin update --help` 是本入口用法）
```

## 布局

| 路径                               | 内容                                            | 管理者                                     |
| ---------------------------------- | ----------------------------------------------- | ------------------------------------------ |
| `~/.local/bin/devin`               | 入口 wrapper                                    | stow（源 `dotfiles/mutable/agents/devin`） |
| `$AGENTS_ROOT/devin/<版本>/`       | 安装树（`bin/`、`share/`、`distribution` 标记） | `devin --install`                          |
| `$AGENTS_ROOT/devin/current`       | 指向当前版本目录的软链                          | `devin --install`                          |
| `~/.local/share/man/man1/devin*.1` | man 页软链（跟随版本，约 190 条）               | `devin --install`                          |
| `~/.local/share/devin/`            | 会话、日志、插件、`credentials.toml`            | 上游运行时，不搬家                         |
| `~/.config/devin/config.json`      | 上游用户配置（模型偏好、`org_id`、主题）        | 上游运行时，运行期会改写，不进仓库         |

`AGENTS_ROOT` 默认 `~/.local/share/agents`，与 dsh / pi / minimax-code 的安装树同层（见 `dotfiles/mutable/AGENTS.md` 的「Agent 运行时安装根」）。

## 实现与约束

- **目录形态对齐官方 install.sh**：`<根>/<版本>/{bin,share,distribution}` 加 `<根>/current` 软链，只把根从 `$XDG_DATA_HOME/devin/cli/_versions` 换成 `$AGENTS_ROOT/devin`；`distribution` 写 `curl-bash`（与官方安装器同值），让安装树对上游工具仍是合法安装形态。
- **先落 staging 再 `mv` 就位**：下载或 sha256 校验失败都不碰现有树（staging 建在同一根下，`mv` 不跨设备；EXIT trap 清 staging 与临时 tarball）。
- **拦截即覆写**：上游 `devin update` 是交互式自更新（无 TTY 直接退出 130），其工作根固定为 `$XDG_DATA_HOME/devin/cli/_versions`（实测：该目录下会生成 `_update.lock`），与本包的 `$AGENTS_ROOT/devin` + stow 入口错位，故遮蔽为 manifest 直装；原生行为直调 `$AGENTS_ROOT/devin/current/bin/devin update` 触达。
- **不 pin 版本**：bundle 自带全部运行时、无依赖图，`--install` 跟 `current/manifest.json` 的 latest 即可；仓库只留入口，不留版本号，换机装机不重放旧版本。
- **首跑引导安装**：`current/bin/devin` 不可执行时，TTY 下交互确认后安装、非 TTY 直接安装；`credentials.toml` 缺失时提示 `devin setup` 登录。
- **man 链 `ln -sfn` 原地改指**：man 链指向 `current/` 路径，换版只改 `current`，全部 man 链自动跟随，无需清理旧链。
- **sha256 取自 manifest**：与官方 install.sh 同源同校验，不信任传输层。

## 排障

| 现象                                         | 原因                           | 处理                                                                             |
| -------------------------------------------- | ------------------------------ | -------------------------------------------------------------------------------- |
| `--install` 报 sha256 校验失败               | 下载被截断或篡改               | 重跑；仍失败查网络 / 代理                                                        |
| `~/.local/bin/devin` 变成指向 XDG 路径的软链 | 走了上游原生命令而非本 wrapper | `blue stow --restow agents/devin` 恢复                                           |
| `devin: 安装树缺失`                          | 新机未安装，或被手工清掉安装树 | 跑 `devin --install`                                                             |
| 要卸载                                       | —                              | `blue stow --delete agents/devin`，删 `$AGENTS_ROOT/devin`；数据目录按需手动清理 |
