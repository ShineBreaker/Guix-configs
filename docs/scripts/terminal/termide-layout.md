<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# termide — VSCode 风格 tmuxifier 会话布局（Explorer | Editor / Terminal）

`dotfiles/immutable/terminal/.config/tmuxifier/layouts/termide.session.sh` · immutable → `~/.config/tmuxifier/layouts/termide.session.sh`（改后须 `blue home`） · `tmuxifier load-session termide`

建 `main` 窗口后横向拆出 Explorer 栏，主区纵向拆成 Editor（上）与 Terminal（下），各 pane `send-keys` 启动 `broot` / `hx` / shell。整体包在 tmuxifier 的 `session_root` + `initialize_session` 守卫里，**只有会话被新建时才搭布局**。

## 环境变量

| 变量                      | 默认                  | 含义                                     |
| ------------------------- | --------------------- | ---------------------------------------- |
| `TERMIDE_SESSION_NAME`    | `${session:-termide}` | 会话名                                   |
| `TERMINAL_IDE_ROOT`       | `$PWD`                | 工作根目录（不存在时回落 `$PWD`）        |
| `TERMIDE_SIDEBAR_WIDTH`   | `24`                  | Explorer 栏宽                            |
| `TERMIDE_TERMINAL_HEIGHT` | `12`                  | 底部终端高                               |
| `TERMIDE_EDITOR`          | `hx`                  | 编辑器命令                               |
| `TERMIDE_FILE_MANAGER`    | `broot`               | Explorer 命令                            |
| `TERMIDE_SHELL`           | `${SHELL:-/bin/sh}`   | 终端 shell                               |
| `TERMIDE_DEBUG`           | 空                    | 非空时把 `[termide] …` 调试输出到 stderr |

## 尺寸分流

**宽高不是原始数字，脚本自己做百分比 / 整数分流**（旧文档说「语义由 tmuxifier 上下文决定」，与源码不符）。`sanitize_size` 接受两种形态，各自落到不同的 `split-window` 旗标：

| 输入形态        | 校验                          | `split-window` 旗标 |
| --------------- | ----------------------------- | ------------------- |
| `N%`（1–99）    | 超出范围则回落默认值          | `-p <N>`            |
| 纯整数（≥ 1）   | 非正数则回落默认值            | `-l <N>`            |
| 其他 / 非法回落 | sidebar `25%`、terminal `20%` | 仍走上面的分流      |

分流逻辑收敛在 `sanitize_size`（校验 + 回落）与 `split_pane`（选旗标）两处；两种形态都能混用，百分比按父 pane 尺寸解析。

## 设计决策与不变量

- **绕过 tmuxifier 的 `new_window`**：它的内部 `set-option -t` **缺 session 前缀**，client 不在目标 session 时报 `no such window`。本脚本改用原生命令，且**所有 tmux 命令都显式带 `session:` 前缀**。
- **命令缺失走 `command -v` 探测降级**：找不到命令只 warn 并把 pane 留 idle，不报错退出，保证最小环境也能起布局。
- **`@no_sidebar 1` 是与 `sidebar-toggle` 的联动契约**：本窗口自带 Explorer 栏，置此标记后 sidebar 的 follow / toggle 会跳过它（见 [sidebar-toggle.md](sidebar-toggle.md)）。同时 `allow-rename off` 锁住窗口名。
- **pane 身份写回窗口选项**，供外部查询：`@termide_root`、`@termide_sidebar_pane`、`@termide_editor_pane`、`@termide_terminal_pane`。
- pane 标题 `Explorer` / `Editor` / `Terminal`，窗口 `pane-border-status top`；布局完成后选中 Editor。
- Terminal pane 的 shell 只在 `TERMIDE_SHELL` 与当前 `$SHELL` **不同**时才 `exec` 替换，默认值下不重复 exec。
