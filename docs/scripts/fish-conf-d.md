<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# fish conf.d — 启动初始化碎片

- 源码：`dotfiles/immutable/terminal/.config/fish/conf.d/*.fish`
- 部署：`~/.config/fish/conf.d/`（immutable，改后需 `blue home`）
- 调用方：fish 每次启动按字母序加载全部 `conf.d/*.fish`；**数字前缀是唯一的排序契约**

## 总览

| 文件 | 作用 |
| ---- | ---- |
| `00-load-functions.fish` | 提前 source `functions/*.fish`（fish 惰性 autoload 会让 conf.d 互调内部函数错过时机） |
| `01-guix.fish` | 登录 shell 经 `fenv` 继承 `~/.profile`（guix profile 环境） |
| `05-java.fish` | JDK 切换器 `__set_jdk` + 启动回放（路径缓存 > 记录版本 > 默认 25） |
| `05-path.fish` | Nix profile + PNPM_HOME + `~/.local/bin` 路径注册 |
| `10-github-token.fish` | `gh auth token` 动态导出 `GITHUB_TOKEN`/`GH_TOKEN` |
| `10-settings.fish` | alias/abbr 集中登记（cat→bat、find→fd、grep→rg、rm -i 等） |
| `20-greeting.fish` | 首个 prompt 前跑 fastfetch + lolcat 格言 |
| `99-command-not-found.fish` | `fish_command_not_found` → `guix locate` 找包 → `guix shell` 执行；`try` 命令 |
| `99-selector.fish` | foot/kitty 顶层终端弹会话选择器（tmux+herdr+shell） |

## 各文件要点

### 00-load-functions.fish

`XDG_CONFIG_HOME` 缺省回退 `$HOME/.config`。逐文件 `source`（字母序 glob）。没有它，`05-java.fish` 里直接调用的 `__set_jdk` 尚未被 autoload。

### 01-guix.fish

`status --is-login` + `__fish_login_config_sourced` 守卫保证只跑一次。`fenv source ~/.profile` 后 `set -e fish_function_path[1]` 移除 fenv 注入的路径。

### 05-java.fish

定义 `JDK_VERSION_FILE`/`JDK_PATH_FILE`/`JDK_DEFAULT_VERSION`（25）三个全局变量与 `__set_jdk`：

- `__set_jdk <ver>`：校验纯数字 → `guix build openjdk@<ver>` 取 `-jdk` 输出 → 设 `JAVA_HOME` + `fish_add_path` → 写两个记录文件。
- 启动回放优先级：`$JDK_PATH_FILE`（直接读缓存路径）> `$JDK_VERSION_FILE`（重建路径）> 默认版本。

### 05-path.fish

`fenv . hm-session-vars.sh` 继承 home-manager 会话变量；`fish_add_path -a` 追加 `$XDG_STATE_HOME/nix/profile/bin` 与 `~/.local/bin`；`PNPM_HOME` 手动前置 `PATH`。

### 10-github-token.fish

单一事实源是 gh CLI 登录凭据：每次启动 `command gh auth token` 动态读取，不落盘新 secret。gh 缺失/未登录时静默跳过。

### 10-settings.fish

纯 alias/abbr 表，无逻辑。`abbr`（展开为完整命令）用于 git/系统操作，alias（原名屏蔽）用于工具替换（`cat`→`bat`、`ls`→`eza` 等，原命令经 `catr`/`command` 仍可达）。

### 20-greeting.fish

`--on-event fish_prompt` 注册后自我 `functions -e`，只跑一次。`GUIX_ENVIRONMENT`（guix shell 内）或 `CONTAINER_ID`（distrobox 内）任一存在即跳过——`or`/`and` 链是刻意写法。

### 99-command-not-found.fish

`fish_command_not_found`：`guix locate <cmd>` 取首个含 `/bin/` 的包 → 从 `$history[1]` 取回整条原始命令行拆分后经 `guix shell <pkg> --` 执行。

- **关键 hack 与已知限制**：fish 的 not-found handler 拿不到原始参数，只能拆 `$history[1]`，复杂引号参数会被二次拆分。
- 找不到包时回落 `__fish_default_command_not_found_handler`。
- 另有 `try <cmd> [args]`：显式入口，`$argv` 完整透传无此限制。

### 99-selector.fish

foot/kitty 顶层终端（`$TERM ∈ foot xterm-kitty`、无 `TMUX`、无 `HERDR_ENV`、无 `CONTAINER_ID`）弹会话选择器；selector 缺失时直接进 `tmux main`（带侧栏），不闪退裸 shell。

输出协议（消费 `~/.config/tmux/scripts/session-selector` 的单行 stdout）：

| 输出 | 含义 |
| ---- | ---- |
| `tmux\|default` | 进 tmux `main`（不存在则建） |
| `tmux\|new` | prompt 输入语义名后新建 |
| `tmux\|<name>` | attach 命名会话（name 可含 `\|`，`-m 1` 只切第一刀） |
| `herdr\|default`/`new`/`<name>` | herdr 同构 |
| `shell` | 留普通 shell |
| `__header__` | 误选标题行 → 重弹 |
| 空 | ESC/取消 → 留普通 shell |

- tmux 侧统一走 `attach-entry`（detached 创建 → session 级 `@sidebar_visible 1` → follow 建侧栏 → exec attach 退出码透传），不串联 `;` 命令链、不用 `exec`（attach 失败要回选择界面）。
- mux 退出码 ≠ 0 回选择界面重选（容错：协议不兼容/session 损坏/socket 异常不闪退裸 shell）；= 0（含用户主动退出 TUI）结束。
- 会话名清洗：非法字符→`_`、限长 20、纯数字加 `s_` 前缀（tmux 拒绝纯数字名）。
- fish 陷阱：正则行末锚 `$` 在单引号字符串里是字面量，须写 `"^[0-9]+\$"`。

## 变更记录

- 2026-09-29：全部注释压缩外移到本文件；新增 `01-guix.fish` 守卫说明、各文件 doc 指针（行为不变）。
