<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# tmux 入口脚本速查 — 会话选择、附着收敛、窗口跳转与快捷键速查

`dotfiles/immutable/terminal/.config/tmux/scripts/` · immutable → `~/.config/tmux/scripts/`（改后须 `blue home`） · `tmux.conf` 键位绑定与 `conf.d/99-selector.fish`

本篇的四个脚本构成一条调用链：`session-selector` 弹菜单并输出选择 → `conf.d/99-selector.fish` 消费并清洗会话名 → `attach-entry` 四步收敛进会话 → `sidebar-toggle follow` 建侧栏（见 [sidebar-toggle.md](sidebar-toggle.md)）。

## session-selector

统一的 tmux / herdr / 普通 shell 会话选择器，用 fzf 列出候选、输出**一行到 stdout**。

### 输出契约

| stdout 输出                                       | 含义                                 |
| ------------------------------------------------- | ------------------------------------ |
| `tmux\|default`                                   | 进 tmux 主会话 `main`（不存在则建）  |
| `tmux\|new`                                       | 新建会话（消费方 prompt 输入语义名） |
| `tmux\|<name>`                                    | attach 命名会话                      |
| `herdr\|default` / `herdr\|new` / `herdr\|<name>` | herdr 同构                           |
| `shell`                                           | 留普通 shell                         |
| `__header__`                                      | 误选分组标题行 → 消费方重弹          |
| 空输出                                            | ESC / 取消 → 留普通 shell            |

**分隔符 `|` 本身就是协议符**，kind 段允许含 `|`，消费方用 `string split -m 1 '|'` 只切第一刀。改任何一项（字段名、分隔符、空值语义）必须同步改 `conf.d/99-selector.fish`。

### 全容错查询

tmux 与 herdr 段各自独立探测（`command -v` + 所有查询 `2>/dev/null || true`），后端缺席时只是少一段候选，**不报错退出**。菜单恒含 `shell` 项与 `__header__` 分组标题；标题输出哨兵而非空行，用于区分「误选」与「取消」。

两条提前退出分支：

- **无任何复用器**（`has_mux == 0`，tmux 与 herdr 都没装）：直接 `echo shell` 退出，不弹只有一项的菜单。
- **`fzf` 缺失**：stderr 打 `session-selector: fzf 未安装，无法弹出选择列表`，stdout 留空，按取消语义 `exit 0`。

fzf 空结果（ESC / 取消）同样静默 `exit 0`。非 tty 时 ANSI 颜色退化为空，便于管道测试。

### 名字含分隔符的会话

生产端过滤掉名字含 `|` 的会话（tmux 与 herdr 段各有一处）：`| ` 是输出分隔符，不加过滤会让协议错位，消费端拿到的 kind 就不是原名。

### fzf 参数

`--reverse --no-multi --delimiter=$'\t' --with-nth=2.. --ansi --header="选择会话环境" --height=~60%`：行内第一列是协议 key、第二列起是显示文本，`--with-nth=2..` 只展示后者。

## attach-entry

tmux 会话统一入口，把「存在就 attach、不存在就建」收敛成固定四步：

```bash
attach-entry <session> [-n win] [-c dir] [--create]
```

| 步  | 动作                                                               | 失败处理                  |
| --- | ------------------------------------------------------------------ | ------------------------- |
| 1   | `tmux has-session -t <ses>` 预检；缺失且 `--create` 时 detached 建 | 无 `--create` 则 `exit 1` |
| 2   | `tmux set-option @sidebar_visible 1`（**session 级**）             | `\|\| true` 静默          |
| 3   | `sidebar-toggle follow` 建侧栏                                     | `\|\| true` 静默          |
| 4   | `exec tmux attach-session -t <ses>`                                | 退出码透传                |

红线：

- **绝不串联 tmux 命令链**（`a ; b ; c` 有竞态闪退），步骤分开发送。
- **第 4 步必须是 `exec`**：退出码透传是契约的一部分（`0` = 正常 detach，调用方结束；`≠0` = 调用方回选择界面），改成普通调用就丢了信号。
- 中间步骤失败**不阻断** attach，由 attach 的退出码决定回退。
- session 缺失且未给 `--create` 时**静默 `exit 1`**——没有任何报错文案，`2>/dev/null` 下的 `has-session` 失败不打印东西。
- 非法参数（缺 `-n`/`-c` 的值、给多个裸 session、给未知旗标）→ usage + `exit 2`。
- 预检用 `has-session` 而非直接 `new-session`：`new-session` 遇重复名的退出码不可靠。

## window-jump

跨 session 模糊跳转窗口：`tmux list-windows -a` 收集全部会话的窗口 → fzf 选择 → 同 session 走 `select-window`，异 session 走 `switch-client -t <session>:<index>`。

调用方是 `tmux.conf` 的 `bind f display-popup -E -w 80% -h 60% -b rounded`——**必须经 `display-popup` 运行**，它需要交互 TTY，独立调用会阻塞在 fzf 上等输入。

列表行格式（tab 分隔）：

```
#{session_name}  #{window_index}  #{window_name}  #{pane_current_path}  #{window_panes}
```

显示侧把路径压成 basename、`window_panes` 渲染成 `pane`/`panes`，当前 session 的窗口前缀 `[当前]`，异 session 的后缀 `← <session>`；`--with-nth=1` 只展示第一列，解析时再按 tab 切出 session 与 index。

无可跳转窗口时 `tmux display-message "没有可跳转的窗口"` + `exit 0`；ESC 取消同样静默 `exit 0`。

## which-key

快捷键速查 popup。无参数、无状态、无副作用，实体是一串 `printf` 拼出的静态文案，末尾 `read -n 1` 等按键。调用方是 `tmux.conf` 的 `bind \? run-shell "bash ~/.config/tmux/scripts/which-key"`。

单条命令：

```bash
tmux display-popup -E -w 70% -h 64% -b rounded "printf … && read -n 1"
```

`-E` 使 popup 内命令结束后自动关闭。**文案与 `tmux.conf` 的实际绑定是手工同步关系，没有自动对账**——改键位必须同时改这份速查表。
