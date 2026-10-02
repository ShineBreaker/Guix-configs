<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# fish completions — Tab 补全清单与同步规则

`dotfiles/immutable/terminal/.config/fish/completions/*.fish` · immutable → `~/.config/fish/completions/`（改后须 `blue home`） · fish 的 Tab 补全

**准入规则**：在 `tools/`、`.local/bin/` 或 `functions/` 新增可执行入口 / 函数时，**必须**在同一改动里写 `complete -c <name>`；CLI 变更时同提交更新补全。规则由 `dotfiles/mutable/AGENTS.md` 与 `dotfiles/immutable/terminal/AGENTS.md` 强制，`toolbox check` 阻断级执法。

例外：`blue`（动态跟随仓库）、`denv`（独立维护，但仍有补全文件）。

下表是补全目录的**唯一对账面**，新增或删除补全文件时同提交更新。

## 清单

| 补全文件                          | 服务命令                        | 内容与 CLI 对照                                                                 |
| --------------------------------- | ------------------------------- | ------------------------------------------------------------------------------- |
| `appimage-run.fish`               | `appimage-run`（子模块工具）    | 8 个子命令 + 各自旗标；应用名从 `*/meta.scm` 动态列出                           |
| `askill.fish`                     | `askill`                        | 子命令 `add/update/install/remove/sync/list`；技能名从 `skills-lock.json` 读    |
| `blue.fish`                       | `blue`                          | 例外：动态跟随仓库自身的命令清单                                                |
| `cua-driver.fish`                 | `cua-driver`（外部包）          | 23 个子命令 + `--json`/`--help` + `update --apply` 等                           |
| `denv.fish`                       | `denv`                          | 例外：独立维护；覆盖 `init/load/remove/status/doctor` 与全部旗标                |
| `git-resign.fish`                 | `git-resign`                    | 单参数 `<base-ref>`，补 `HEAD~N` 候选                                           |
| `hermes.fish`                     | `hermes`                        | 首行 source 上游 `hermes completion fish`；追加本仓库 `update --branch/--check` |
| `jbuild.fish`                     | `jbuild`                        | 动态补 `src/*.java` 的 basename                                                 |
| `jdk.fish`                        | `jdk`                           | `set` / `current` 子命令；`set` 补版本候选 `8 11 17 21 25`                      |
| `jrun.fish`                       | `jrun`                          | 动态补 `bin/*.class` 的 basename                                                |
| `keepassxc-credential-setup.fish` | `keepassxc-credential-setup`    | `status` / `init` / `update` / `callers` 四个子命令                             |
| `nixgpu-update.fish`              | `nixgpu-update`                 | 脚本不解析参数，补全文件只有一条 `complete -f`（无旗标可补）                    |
| `quicktui-server.fish`            | `quicktui-server`（外部二进制） | 两层子命令；`serve` 补旗标。上游无补全，清单摘自 `--help`                       |
| `retry.fish`                      | `retry`                         | 参数即被重试命令（`__fish_complete_subcommand`）                                |
| `run.fish`                        | `run`                           | `__run_complete` 按目录构建文件转发 `complete -C`（maak / blue / just）         |
| `screen-off.fish`                 | `screen-off`                    | 可选秒数候选 `3 5 10 30`                                                        |
| `secrets.fish`                    | `secrets`、`tools/secrets`      | 全部子命令 + `--dry-run`（须置于子命令前）+ 名称动态补全                        |

`git-resign` / `jbuild` / `jrun` 三个补全与函数同处 `functions/` 目录，登记在 [fish-functions.md](fish-functions.md)；`niri-app-switcher` 与 `niri-quake-toggle` **不登记**补全（无参数 CLI，见 [misc-scripts.md](misc-scripts.md)）。
