<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# fish completions — Tab 补全清单与同步规则

- 源码：`dotfiles/immutable/terminal/.config/fish/completions/*.fish`
- 部署：`~/.config/fish/completions/`（immutable，改后需 `blue home`）
- 同步规则（`dotfiles/mutable/AGENTS.md` + `dotfiles/immutable/terminal/AGENTS.md`）：新增可执行入口/函数时**必须**同步写 `complete -c <name>`；CLI 变更时同提交更新补全。例外：`blue`（动态跟随仓库）、`denv`（独立维护——但仍已有补全文件）。

## 清单

| 补全文件 | 服务命令 | 内容与 CLI 对照 |
| -------- | -------- | --------------- |
| `appimage-run.fish` | `appimage-run`（子模块工具） | 动态列 `~/.local/share/appimages/*/meta.scm` 里的应用名 |
| `askill.fish` | `askill` | 子命令 `add/update/install/remove/sync/list`；技能名从 `skills-lock.json` 读 |
| `blue.fish` | `blue` | 例外：动态跟随仓库（`blue` 自身命令清单） |
| `cua-driver.fish` | `cua-driver`（外部包） | 子命令 + `--json`/`--help` + `update --apply` 等 |
| `denv.fish` | `denv` | init/load/remove/status/doctor、`-l/--lang`（含别名与 `=` 形态）、`-L`、`--full`、`--no-guix`、`-f`、`--all`、`--fix` |
| `git-resign.fish` | `git-resign` | 单参数 `<base-ref>`，补 `HEAD~N` 候选 |
| `hermes.fish` | `hermes` | 首行 source 上游 `hermes completion fish`；追加本仓库 `update --branch/--check` |
| `jbuild.fish` | `jbuild` | 动态补 `src/*.java` basename |
| `jdk.fish` | `jdk` | `set`/`current` 子命令 |
| `jrun.fish` | `jrun` | 动态补 `bin/*.class` basename |
| `keepassxc-credential-setup.fish` | `keepassxc-credential-setup` | 子命令与目标 |
| `nixgpu-update.fish` | `nixgpu-update` | `--check`/`--help` 类标志 |
| `retry.fish` | `retry` | 参数即被重试命令（`__fish_complete_subcommand`） |
| `run.fish` | `run` | `__run_complete` 按目录构建文件转发 `complete -C`（maak/blue/just） |
| `screen-off.fish` | `screen-off` | 可选秒数候选 `3 5 10 30` |
| `secrets.fish` | `secrets`、`tools/secrets` | 全部子命令 + `--dry-run`（须置于子命令前）+ 名称动态补全 |

## 变更记录

- 2026-09-29：删除 `fxxk-link.fish`——`fxxk-link` 命令本体已在 `4571b096` 移除，补全文件是孤儿残留（fish 对不存在命令的补全静默无效，但属死配置）。
