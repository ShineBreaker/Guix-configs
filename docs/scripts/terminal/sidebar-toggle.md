<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# sidebar-toggle — tmux 侧边栏 pane 生命周期与事件适配器

`dotfiles/immutable/terminal/.config/tmux/scripts/sidebar-toggle` · immutable → `~/.config/tmux/scripts/sidebar-toggle`（改后须 `blue home`） · `tmux.conf` 的键位与 hook、鼠标绑定、`attach-entry` 的 follow 步骤

Bash 侧**只管 pane 的生命周期**（创建、销毁、floating pane 调整）；渲染与点击交互全在长驻 Guile daemon `sidebar-render.scm daemon`（见 [tmux-sidebar.md](tmux-sidebar.md)），两者经每 pane 独有的 FIFO 通信。

## 用法

```bash
sidebar-toggle [toggle|follow|resized|signal|click|toggle-group|layout-changed]
```

无参默认 `toggle`；非法动作打 usage + `exit 2`。

| 动作             | 语义                                           | 前置条件                     |
| ---------------- | ---------------------------------------------- | ---------------------------- |
| `toggle`         | 按 `@sidebar_visible` 开 / 关当前 session 侧栏 | —                            |
| `follow`         | session 变化后按需建立 / 更新侧栏 pane         | `@sidebar_visible` 为 1      |
| `resized`        | 客户端尺寸变化后防抖并校正宽度                 | `@sidebar_visible` 为 1      |
| `signal`         | 事件 → FIFO 轻量通知，催 daemon 重渲染         | —                            |
| `click`          | 鼠标事件转发 FIFO（y / 坐标 / pane / client）  | 恰好 5 个参数，否则 `exit 2` |
| `toggle-group`   | 折叠 / 展开当前分组                            | —                            |
| `layout-changed` | 窗口布局变化后的侧栏对齐                       | —                            |

hook 里的调用都走 `run-shell -b`，静默无输出。

## 调用方

| 调用方              | 动作                                             |
| ------------------- | ------------------------------------------------ |
| `bind B`            | 无参 → `toggle`                                  |
| `bind G`            | `toggle-group`                                   |
| `bind T` / `bind D` | 写 `@sidebar_window_title` / `_desc` 后 `signal` |
| `MouseDown1Pane`    | `click`，随后 `signal`                           |
| `attach-entry`      | `follow`                                         |

13 个 `set-hook`：

| hook                                                                         | 动作             |
| ---------------------------------------------------------------------------- | ---------------- |
| `after-select-pane`、`window-renamed`、`session-renamed`、`window-unlinked`  | `signal`         |
| `after-new-window`、`after-new-session`、`client-session-changed`            | `follow`         |
| `after-select-window`、`client-attached`、`client-detached`、`client-active` | `follow`         |
| `window-layout-changed`                                                      | `layout-changed` |
| `client-resized`                                                             | `resized`        |

## 宽度策略

初始宽度归 `tmux.conf` 所有（`set -g @sidebar_width 32`）。本脚本**只读 `@sidebar_width`，绝不写回**——曾把竞态造成的假偏离持久化回去，污染全局宽度。

三条对账规则：

1. **手动拖拽豁免**：窗口宽度未变（`@sidebar_last_window_width` 与当前 `window_width` 相等）且侧栏实际宽度在 **12–80** 之间偏离配置值时，视为用户手动拖拽，**保持现状但不回写 `@sidebar_width`**；超出该区间说明状态异常，按配置宽度拉回。
2. **窗口变了就拉回**：窗口尺寸与记录不符时按配置宽度 `resize-pane`，并更新 `@sidebar_last_window_width`。
3. **窗口只放大不缩小**：`sync_window_to_client` 扫全 server 所有 window，只在 `window_width < client_width`（高同理）时下发 `-x` / `-y`。切到后台 window 再 follow 已经太晚，所以不能只看当前 window。

client 尺寸按 `list-clients -a` 的行内 `session_id` **分别取 max**——不能回落「最近活跃 client」，后台 session 会拿错尺寸；手机 detach 残留的小尺寸行也不能拖累桌面，故只取 max 不取 min。无 client 的 session 直接跳过。

`client-resized` 逐帧连发，`resized` 走防抖：按窗口写 `@sidebar_resized_ts` 时间戳，`sleep 0.15` 后核对时间戳未被后续事件覆盖，只执行最后一次。这是为了避免 `resize-pane` 与 tmux 自身的挤压互搏出可见抽动。

## 设计决策与不变量

- **FIFO 路径双端同步**：每 pane 独有 `${XDG_RUNTIME_DIR:-/tmp}/tmux-sidebar-$UID-$pane_id.fifo`，文件名**必须与 `sidebar-render.scm` 的 `fifo-path` 一致**。写走 `exec {fd}<>` 非阻塞打开（O_RDWR，避免 daemon 已退出时 hook 阻塞在 open），无 reader 时静默跳过。
- **`@sidebar_visible` 是 session 级**：读取走 `show-option -qv`（session 优先），清理只 `list-panes -s` 清本 session，不能越权关别人的侧栏。默认全局值为 `0`（纯净），只有用户终端入口才显式 opt-in 为 1。
- **`flock -n 9` 取不到锁直接丢弃**：保证 hook 风暴下同窗口的 pane 操作串行；事件本身幂等可重发，丢弃无损失。锁键含 socket 名与 window id，无 `TMUX` 的裸调用按 default socket 处理。写类动作（`signal` / `click` / `toggle-group`）在锁外执行故可重入，改 pane 的动作在锁内。
- **解析 tmux 格式串一律用 `|` 分隔，不用空白或 tab**：`start_command` 可能含分隔符，且空的 `@no_sidebar` 在 IFS-tab 下会丢字段导致错位。
- **创建失败必须回滚**：`split-window` 失败（无普通窗格，或 tmux 低于 **3.3a+** 缺 `-b -f`）时把 `@sidebar_visible` 回滚为 `0`。回滚必须与置 1 同为 session 级（不带 `-g`），否则残留的 1 会让 follow hook 无限重试 split 刷屏。
- **`@no_sidebar 1` 的窗口跳过侧栏**：termide 布局给自家 Explorer 栏留位，见 [termide-layout.md](termide-layout.md)。
- 重复创建出的多个侧栏 pane 会被清掉，只留第一个。pane 消失不等于 `exec` 出的 daemon 已死，销毁时须显式 `kill -TERM` 再 `kill-pane`。
