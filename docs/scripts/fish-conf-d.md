<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# fish conf.d — 启动初始化碎片

`dotfiles/immutable/terminal/.config/fish/conf.d/*.fish` · immutable → `~/.config/fish/conf.d/`（改后须 `blue home`） · fish 每次启动按字母序加载全部碎片

**数字前缀是唯一的排序契约**——fish 本身只按文件名字母序加载，前缀是人为约定的执行顺序，改名即改序。

| 文件                        | 作用                                                        |
| --------------------------- | ----------------------------------------------------------- |
| `00-load-functions.fish`    | 提前 source `functions/*.fish`（**必须存在**，见下）        |
| `01-guix.fish`              | 登录 shell 经 `fenv` 继承 `~/.profile`（guix profile 环境） |
| `05-java.fish`              | JDK 切换器 `__set_jdk` 与启动回放，细节见 fish-functions.md |
| `05-path.fish`              | Nix profile + `PNPM_HOME` + `~/.local/bin` 路径注册         |
| `10-github-token.fish`      | `gh auth token` 动态导出 `GITHUB_TOKEN` / `GH_TOKEN`        |
| `10-settings.fish`          | alias / abbr 集中登记（纯表，无逻辑）                       |
| `20-greeting.fish`          | 首个 prompt 前跑 fastfetch + lolcat 格言                    |
| `99-command-not-found.fish` | `fish_command_not_found` → `guix locate` → `guix shell`     |
| `99-selector.fish`          | foot/kitty 顶层终端弹会话选择器                             |

## 00-load-functions.fish

**这个文件必须存在。** fish 对 `functions/` 是惰性 autoload，但 `conf.d/` 之间会**互调函数内部实现**（典型如 `05-java.fish` 的启动回放直接调 `__set_jdk`）——等 autoload 会错过初始化时机。

`XDG_CONFIG_HOME` 缺省回退 `$HOME/.config`；逐文件 `source`（字母序 glob），目录不存在时静默跳过。

## 01-guix.fish

`status --is-login` + `not set -q __fish_login_config_sourced` 是**双守卫**，保证 `~/.profile` 只被 source 一次。source 完立刻 `set -e fish_function_path[1]`——fenv 会把自己的路径插到 `fish_function_path` 首位，不删会盖掉本包的 `functions/`。

## 20-greeting.fish

`--on-event fish_prompt` 注册后在函数体第一行**自我 `functions -e`**，故整个欢迎输出只在首个 prompt 跑一次。

`set -q GUIX_ENVIRONMENT; or set -q CONTAINER_ID; and return` 是刻意的 `or` / `and` 链：guix shell 内（`GUIX_ENVIRONMENT`）或 distrobox 内（`CONTAINER_ID`）任一成立即跳过欢迎输出。

## 99-command-not-found.fish

`fish_command_not_found`：`guix locate <cmd>` 取首个含 `/bin/` 的包 → 执行 `guix shell <pkg> -- <cmd>…`。找不到包时回落 fish 自带的 `__fish_default_command_not_found_handler`。

**`$history[1]` 是关键 hack，也是已知限制**：fish 的 not-found handler 拿不到用户输入的原始参数，只能从 `$history[1]` 取回整条命令行再按空格重拆——**复杂引号参数会被二次拆分**。参数需要原样保留时用脚本里的另一个函数 `try <cmd> [args...]`，它是显式入口，`$argv` 完整透传，无此限制；找不到包时返回 `127`。

## 99-selector.fish

会话选择器的消费端。**触发条件**：交互 shell 且 `$TERM ∈ {foot, xterm-kitty}`，同时**没有** `TMUX`、**没有** `HERDR_ENV=1`、**没有** `CONTAINER_ID`——即只在 foot / kitty 的顶层终端弹。selector 脚本缺失（如 `blue home` 未跑）时直接进 `tmux main`，不闪退裸 shell。

消费端行为：

- **输出协议与字段含义见 [tmux-scripts.md](tmux-scripts.md) §session-selector**（唯一出处，本篇不重复）。
- `string split -m 1 '|'` **只切第一刀**，其余段用 `string join '|'` 重新拼回——kind 段本身允许含 `|`。
- `__header__` → `continue` 重弹；空输出与 `shell` → `return` 留普通 shell。
- **退出码语义**：mux 命令返回 ≠ 0（协议不兼容、session 损坏、socket 异常）→ 打提示后回选择界面重选；= 0（含用户主动退出 TUI）→ 结束。
- tmux 侧一律经 `attach-entry`，不走裸 `tmux` 命令。

会话名清洗（`__selector_make_session_name`）：空输入回落到 cwd 的 basename；非法字符 `[^a-zA-Z0-9_-]` 一律换成 `_`；截断到 20 字符；结果为空时用 `default`。

**fish 陷阱**：正则行末锚 `$` 在单引号字符串里是**字面量**，判断纯数字必须写双引号 `"^[0-9]+\$"`——tmux 拒绝纯数字 session 名，所以要给它们加 `s_` 前缀。
