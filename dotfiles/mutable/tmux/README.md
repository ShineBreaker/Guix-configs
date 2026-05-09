# 现代终端体验设计

基于 tmux + foot + fish 打造类 zen-browser 风格的终端工作环境。

## 目标

将 tmux 从基础的窗口管理器升级为具有现代终端 IDE 体验的 workspace manager，提供直观的视觉导航、智能会话管理和高效的工作流。

## 架构

所有 tmux 相关文件集中在 `~/.config/tmux/`，遵循 XDG 规范。不使用 TPM 插件系统，通过外部脚本 + tmux hooks 实现，与现有 termide 模式保持一致。

### 语言选型

**短期实现：Guile（核心逻辑）+ Bash（生命周期胶水）的混合方案。**

| 语言      | 脚本                                          | 选择理由                           |
| --------- | --------------------------------------------- | ---------------------------------- |
| **Guile** | sidebar-render.scm, tmux-helpers.scm          | 数据采集、渲染、点击动作、Git 信息 |
| **Bash**  | sidebar-toggle, session-selector, window-jump | tmux 生命周期、fzf 管道胶水        |

当前已经将 `sidebar-data.scm` 与 `git-collector.scm` 降为兼容 wrapper，实际执行统一转发到 `sidebar-render.scm data/git`。这样避免“采集缓存”和“渲染实时状态”两套逻辑漂移，冷启动时也不再依赖旧缓存。

**Guile 性能策略（当前短期方案）：**

- 源码 `.scm` 文件放在 scripts/ 下，带 `#!/usr/bin/env guile` shebang + `!#` 入口
- 当前直接使用 `GUILE_AUTO_COMPILE=0 guile --no-auto-compile -s ...`，避免 tmux pane 中出现 Guile 编译提示
- 实时采集+缓存 fallback。`render-if-changed` 每次优先实时调用 tmux 采集数据，失败时才读取缓存。
- 如果后续性能不足，再考虑预编译 `.go` 或迁移到 Go/Rust；当前短期方案优先保持 Guix 友好和脚本可调试性

### Guix Home 集成策略

**当前方案：tmux 配置已经迁移到 mutable dotfiles。** `~/.config/tmux/tmux.conf` 指向 `dotfiles/mutable/tmux/.config/tmux/tmux.conf`，后续调试 tmux 不需要每次运行 `maak home`。

具体做法：

- 将 `dotfiles/mutable/tmux/.tmux.conf` 迁移到 `dotfiles/mutable/tmux/.config/tmux/tmux.conf`
- scripts/ 放在同一目录下，和 tmux.conf 一起通过 mutable dotfiles 暴露到 `~/.config/tmux/`
- **workspaces/ 目录例外：** 快照数据是运行时生成的，不适合放在 guix store 中。`workspaces/` 目录由 `workspace` 脚本在首次使用时自动创建于 `~/.local/share/tmux/workspaces/`（XDG_DATA_HOME 下）
- 旧的 `~/.tmux.conf` 声明从 guix home 配置中移除，改使用 `~/.config/tmux/tmux.conf`

```
dotfiles/mutable/tmux/.config/tmux/
├── tmux.conf                      # 主配置（从 .tmux.conf 迁移）
└── scripts/
    ├── sidebar-toggle             # [Bash]  侧边栏开关（创建/销毁/跟随 floating pane）
    ├── sidebar-render.scm         # [Guile] 数据采集 + 标签栏渲染 + 鼠标点击处理
    ├── sidebar-data.scm           # [Guile] 兼容 wrapper，转发到 sidebar-render.scm data
    ├── git-collector.scm          # [Guile] 兼容 wrapper，转发到 sidebar-render.scm git
    ├── workspace.scm              # [Guile] 工作区快照管理
    ├── session-selector           # [Bash]  会话选择器（fzf）
    └── window-jump                # [Bash]  模糊窗口跳转（fzf）
```

运行时数据：

```
~/.local/share/tmux/workspaces/   # 工作区快照（运行时生成）
/tmp/tmux-<socket-hash>-*         # 临时缓存/锁文件
```

Fish 集成：

```
dotfiles/mutable/tmux/.config/fish/conf.d/99-tmux.fish  # 修改现有
```

### 多 Server 支持

所有临时文件使用 tmux 的 `#{socket_path}` 计算 hash 作为隔离键（通过 `tmux display-message -p '#{socket_path}'` 获取），避免多 server 场景下的冲突，同时避免 socket 路径中的 `/` 进入文件名。

## 实施阶段

### 阶段 1：核心功能

- 功能一：标签栏基础渲染（不含分组和折叠）
- 功能二：Git 信息采集（基础版，不含 inotify）
- 功能六：活动通知（现有 `monitor-activity on` + `visual-activity off` 已兼容）

### 阶段 2：交互增强

- 功能三：会话选择器（集成现有 `99-tmux.fish` session group 逻辑）
- 功能四：模糊窗口跳转
- 功能一增强：分组和折叠

### 阶段 3：高级功能

- 功能五：工作区快照（简化版，不含 editor 文件推断）
- 功能二增强：inotify 优化

## 功能一：左侧竖向标签栏

### 渲染方式

**P0 验证结论：** `status-left` 的 `\n` 在 foot + tmux 中不渲染为多行，原 status-left 方案不可行。

**采用浮动窗格（floating pane）方案：** 参考开源 tmux 插件 tabby 的实现方式，使用 `tmux split-window -h -b -f -l <width>` 在终端左侧创建一个持久的浮动窗格作为侧边栏。浮动窗格拥有完整的终端渲染能力，不受 status-left 限制。

**架构（简化版 tabby 方案）：**

| 组件                       | 实现方式                      | 职责                                         |
| -------------------------- | ----------------------------- | -------------------------------------------- |
| sidebar-toggle (Bash)      | `tmux split-window -f`        | 创建/销毁浮动窗格                            |
| sidebar-render.scm (Guile) | 输出 ANSI 格式化文本到 stdout | 实时采集、缓存 fallback、渲染、点击处理      |
| sidebar-data.scm (Guile)   | wrapper                       | 兼容旧入口，转发到 `sidebar-render.scm data` |

**工作方式：**

- 按 `Ctrl+x B` 切换侧边栏显示/隐藏（toggle 持久状态）
- 侧边栏以浮动窗格形式覆盖在终端左侧，默认宽度 32 字符
- 窗格内运行显示循环：收到 `SIGUSR1`（信号驱动）或约 30 秒心跳时原位重绘
- 切换窗口、创建/销毁 pane、resize、client attach/resized 时，通过 hooks 发送 signal 通知侧栏重绘（仅用户主动切换时才 follow 新窗口）
- 鼠标点击 session/group 行可折叠或展开；点击 window/pane 行会切换到对应目标
- 点击坐标使用 `#{mouse_y}` 与 `#{pane_top}` 计算 pane 内行号，并带相邻行 fallback，避免 tmux 坐标差异导致点不中

**活动通知：**

- `sidebar-render.scm` 读取 `#{window_activity_flag}` 缓存，有活动的窗口标签显示红色
- 切换到该窗口后，tmux 自动清除活动标记

**相比 tabby 的简化与取舍：**

- 不使用 daemon/coordinator 架构，改用文件缓存 + 定期刷新
- 不实现上下文菜单；点击动作只做折叠和跳转
- 不使用 Bubble Tea 等 TUI 框架，渲染通过 ANSI 转义序列实现

### 标签内容

侧栏现在不是“每个 tmux window 一个代表标签”，而是显示完整结构：

```
┌─────────────────────────────┐
│            main             │
└─▾───────────────────────────┘
  └─ ▾ .config [1]
     └─ ● 1 brokenshine [3]
        ├─   2 ✳ Claude Code
        │  emacs · node /home/
        ├─   3 hx ./README.md
        │  emacs · hx ./README
        └─ ● 4 brokenshine
           emacs · -fish
```

层级含义：

- Session：顶部盒子，点击可折叠整个 session
- Group：按路径父目录自动分组，点击可折叠该组
- Window：tmux window/tag，显示 window index、window name、pane 数量
- Pane：显示该 tmux window 下的每个普通 pane，不再只显示代表 pane
- 描述行：显示路径 basename 和 `/proc/<pid>/cmdline` 摘要，优先体现正在运行的前台命令
- `●` 标记当前 active window/pane

标题优先级：

1. `@sidebar_window_title`
2. `@tabby_ai_title`
3. `@tabby_pane_title`
4. pane title（排除 shell/路径等泛化标题）
5. 非 shell `pane_current_command`
6. tmux window name

描述优先级：

1. `@sidebar_window_desc`
2. 路径 basename + 前台 cmdline 摘要
3. 路径 basename

手动标题绑定：

- `Ctrl+x T`：设置当前 window 的侧栏标题，不重命名 tmux window
- `Ctrl+x D`：设置当前 window 的侧栏描述

### 分组机制

- 自动按窗口工作目录的父路径分组
- **内部键**使用完整路径的哈希，避免同名目录冲突（如 `~/work/app` vs `~/personal/app`）
- **显示名**取路径最后一段；冲突时追加父目录前缀（如 `work/app` vs `pers/app`）
- 路径为 `/` 或 `~` 时，组名直接显示 `/` 或 `~`
- 窗口路径变化后，hook 触发重新计算分组
- 组名可手动重命名（覆盖自动值），存储在 tmux user option `@window_group` 中
- 组标题行可折叠/展开该组下的窗口

### 折叠控制

- 快捷键 `Ctrl+x B` 切换侧边栏浮动窗格的显示/隐藏
- 浮动窗格宽度默认 32 字符，位于终端左侧
- 显示状态下按 `Ctrl+x B` 隐藏（销毁窗格）
- 隐藏状态下按 `Ctrl+x B` 显示（创建窗格）
- 窗格显示/隐藏状态通过 tmux user option `@sidebar_visible` 持久化
- 分组折叠：在 sidebar-render 中处理，折叠状态存储在 `@sidebar_collapsed_groups` 中
- Session 折叠状态存储在 `@sidebar_collapsed_sessions` 中
- 鼠标点击折叠后通过 `SIGUSR1` 通知侧栏 pane 重绘，避免等待下一轮轮询

### 配色方案

**不维护独立主题文件。** 标签栏直接使用 tmux 的终端颜色（`default`、`brightblack`、`green` 等），由 foot 终端的 ANSI 调色板驱动。Foot 已经通过 darkman/noctalia 自动切换亮暗主题，tmux 继承终端颜色后标签栏自动跟随变化。

具体颜色映射在 tmux.conf 中通过 `@sidebar_*` user option 定义，引用 tmux 内置颜色名（如 `set -g @sidebar_active_fg green`），不需要额外的 theme 文件。

### 状态栏三段式布局

顶部状态栏重构为三段式布局：

| 区域 | 内容 | 样式 |
|------|------|------|
| 左侧 | 前缀键图标、session 名、git branch、命令、路径、zoom/copy 状态 | Nerd Font 图标标注各信息段 |
| 中央 | 日期时间 | 通过 `window-status-current-format` 居中，配合 `status-justify centre` |
| 右侧 | 系统负载、终端尺寸、主机名 | Nerd Font 图标标注 |

**前缀键视觉反馈：**
- 按下 `Ctrl+x` 时，前缀图标从 ``（空心）变为 ``（实心红色），session 名从绿色变为红色
- 松开后恢复默认样式

**中央区域原理：**
- tmux 状态栏三段结构为 `left | center(窗口列表) | right`
- `status-justify centre` 让中间窗口列表区域居中对齐
- `window-status-current-format` 显示当前窗口的日期时间，借用窗口标签位置实现居中
- `window-status-format` 设为空，非当前窗口不显示，避免干扰
- 注意：strftime 格式（`%Y-%m-%d`、`%H:%M`）在 `window-status-*` 中不展开，需用 `#(date +%Y-%m-%d)`

**Git branch 同步：**
- `sidebar-render.scm` 的 `render-if-changed` 在每次渲染时，将当前窗口的 git branch 写入窗口级选项 `@status_git_branch`（`-w` 级别）
- 状态栏 `status-left` 通过 `#{@status_git_branch}` 零开销引用
- 使用窗口级而非全局级选项，避免多 session 场景下 pane-loop 互相覆盖

### 性能与竞态控制

浮动窗格方案将渲染与数据采集分离：

**数据采集（实时优先 + 缓存 fallback）：**

- `sidebar-render.scm` 每次渲染优先实时调用 `tmux list-panes -a -F ...` 采集普通 pane 数据
- 采集结果写入 `sidebar-data.cache`；如果实时采集为空，才读取缓存
- `sidebar-data.scm` 和 `git-collector.scm` 保持为兼容入口，实际转发到 `sidebar-render.scm data/git`
- 缓存文件存放在 `/tmp/tmux-<socket-hash>-*.cache`，使用 socket path hash 隔离

**渲染（前台，窗格内循环）：**

- sidebar-render.scm 输出 ANSI 文本到 stdout
- pane-loop 启动时清屏一次，后续只移动光标到左上并清除残留，减少闪烁
- 点击、hook（signal 模式）、轮询均可触发渲染
- 刷新机制：signal 触发立即刷新（`SIGUSR1`），30 秒心跳兜底

**窗格跟随：**

- 切换窗口时通过 `after-select-window` hook 调用 sidebar-toggle follow
- sidebar-toggle 检查 `@sidebar_visible`，如果为 1 则在新窗口重建浮动窗格
- 同一窗口中如果出现多个侧栏 pane，保留当前有效 pane 并清理重复项
- 所有 list-panes 调用加 `-t session` 参数指定上下文，避免 run-shell -b hook 中 tmux 无法推断默认 session 的问题

**数据采集分层：**

- 轻量数据（session/window/pane、路径、进程名、pane title）：每次渲染直接从 `tmux list-panes -a -F` 获取
- 重量数据（git branch）：通过 `sidebar-render.scm git` 写入缓存；当前 pane 标题不再默认拼接 branch，避免挤掉真实标题
- 前台命令描述：通过 `/proc/<pane_pid>/task/<pid>/children` 追踪子进程，再读取 `/proc/<pid>/cmdline`

**进程名局限性：**

- `pane_current_command` 仅返回进程名（如 `python`），不含参数
- 当前描述行已经读取 `/proc/<pid>/cmdline` 和子进程 cmdline，但这依赖 Linux `/proc`
- 读取失败时回退到 `pane_current_command` 和路径 basename

### 数据来源

- tmux hook `after-select-pane`、`after-split-window`、`after-kill-pane`、`after-select-layout`、`after-resize-pane`、`after-new-window`、`window-unlinked` 触发 signal 通知侧栏重绘
- `after-select-window`、`client-attached`、`client-active`、`client-resized` 触发 signal + follow
- `after-new-session`、`client-session-changed` 触发 signal + follow（新 session 不经过 after-new-window）
- 规则：仅用户主动切换窗口/客户端时 follow；split/kill/resize 只 signal，避免 create_sidebar 内部触发 hook 级联导致频闪
- `sidebar-render.scm` 通过 `render-if-changed` 命令完成采集+渲染+状态栏选项同步
- 浮动窗格内的显示循环约每 30 秒心跳刷新，signal 可立即刷新

### 错误处理

**Guile 脚本：**

```scheme
(guard (ex ((error? ex)
            (system* "tmux" "display-message"
                     (format #f "script error: ~a" ex))))
  ;; 主逻辑
  ...)
```

**Bash 脚本：**

```bash
trap 'tmux display-message "session-selector error: $?"' ERR
```

脚本崩溃时，tmux status line 保持上次状态（不显示空白），并在状态栏显示错误提示。

## 功能二：Git 信息采集

### 采集方式

**不使用 `send-keys` 或在 pane 内执行命令。**

- 通过 `tmux display -p -t <pane> '#{pane_current_path}'` 获取每个 pane 的工作路径
- 检测该路径是否为 git 仓库：检查 `<path>/.git/HEAD` 是否存在
  - **安全校验实现：**
    ```bash
    pane_path=$(realpath "$pane_current_path")
    git_path=$(realpath "$pane_current_path/.git")
    [[ "$git_path" == "$pane_path"/* ]]
    ```
    `realpath` 来自 coreutils，在 Guix 中可用。不跟随指向 `pane_path` 外部的符号链接。
- 如果是 git 仓库，直接读取 `.git/HEAD` 文件内容解析分支名
  - `ref: refs/heads/<branch>` → 取 `<branch>`
  - SHA（detached HEAD）→ 取前 7 位
- 对于 `git worktree`：`.git` 是文件内容为 `gitdir: <path>`
  - 使用 `git -C <path> rev-parse --git-dir` 获取实际 git-dir（比手动解析可靠），加 `timeout 2s`
  - 如果 `git` 命令不可用或超时，跳过该 pane

### 后台采集进程

- `git-collector` 作为 tmux 的后台进程运行（`run -b`）
- **分层采集频率：**
  - 当前 attach 的 session 的当前 window：每 30 秒采集
  - 其他 window/session：每 120 秒采集
- 结果写入 `/tmp/tmux-<socket-hash>-git-branches.cache`
- 格式：`<session>:<window> <branch_name>`，每行一条
- 所有路径操作加 `timeout 2s`，防止 NFS/远程挂载阻塞
- 如果 pane 路径不可访问或非 git 仓库，不写入该条目
- **inotify 优化（阶段 3 可选）：** 如果系统安装了 `inotify-tools`，监听当前活跃 pane 的 `.git/HEAD` 变化事件，实现即时更新

### 缓存失效

- 后台采集是周期性的，分支切换后最多 30 秒延迟（活跃窗口）
- 可接受的折衷：标签栏信息是辅助性的，不需要实时精确
- 手动刷新：`Ctrl+x g` 强制触发一次即时采集

## 功能三：会话选择器

### 与现有 99-tmux.fish 的集成方式

选择器在现有 session group 创建逻辑**之前**执行，作为可选的「恢复入口」：

```
Foot 启动
  └─ 检测到 foot + 非 tmux + 非容器
       ├─ 有未 attach 的 session?
       │    ├─ 是 → 弹出 fzf 选择器
       │    │        ├─ 选中已有 session → attach，跳过 group 逻辑
       │    │        ├─ 选中「新建空会话」→ 继续执行现有 group 逻辑
       │    │        └─ Esc 退出 → 回到普通 shell（不创建 session）
       │    └─ 否 → 继续执行现有 group 逻辑
       └─ 无 session 存在
            └─ 继续执行现有 group 逻辑
```

现有 session group 创建逻辑（`main` group、`term_<pid>` session、自动 new-window）保持不变，只在「有可恢复会话时」插入选择器。

### 触发时机

触发条件（全部满足）：

1. 当前终端是 foot（`$TERM` 匹配 `foot*`）
2. 不在 tmux 内（`$TMUX` 为空）
3. 不在容器内（已有检测逻辑）

### 选择逻辑

1. 列出所有 tmux session：`tmux list-sessions -F "#{session_name} #{session_windows} #{session_created} #{session_attached} #{session_group}"`
2. 过滤规则：
   - `session_attached == 0` → 未被任何 client attach → 可选
   - `session_attached > 0` → 正在被使用 → 不可选，但在列表中显示标记「使用中」
   - **Session group 处理：** 如果一个 group 中有成员被 attach，其他未 attach 的成员仍然可选（它们是独立视图）
   - **P0 验证项：** 编码前必须编写最小可复现测试，验证 tmux session group 中成员 detach 后 `session_attached` 的精确行为
3. 如果无可选会话 → 继续执行现有 session group 逻辑
4. 如果有可选会话 → 调用 fzf 弹出选择列表

### 选择界面

fzf 弹窗显示格式：

```
session_name    3 windows    14:30
another_session 1 window     12:15   [使用中]
> [新建空会话]
```

- 已 attach 的会话显示 `[使用中]` 标记，通过 fzf 的条件不可选择
- 最后一项固定为 `[新建空会话]`
- 时间从 `session_created`（epoch）转换为 `HH:MM`

### 选择后行为

- 选中已有会话 → `tmux attach-session -t <name>`
- 选中「新建空会话」→ 继续执行现有 session group 创建逻辑
- **退出 fzf（Esc）→ 不创建 session，回到普通 shell**

## 功能四：模糊窗口跳转

### 触发

快捷键 `Ctrl+x f` 触发 fzf 弹窗。

### 列表内容

列出所有 session 中的所有窗口，明确标记来源：

```
[当前] main  ~/projects/app  (3 panes)
[当前] dev   ~/projects/app  (1 pane)
  dev   ~/projects/lib  (2 panes)   ← session: lib
```

- 当前 session 的窗口标注 `[当前]`，其他 session 标注 `← session: <name>`
- 显示：窗口名、路径、pane 数量

### 选择后行为

- 窗口在当前 session → `tmux select-window -t <window>`
- 窗口在其他 session → `tmux switch-client -t <session>:<window>`（原子操作，避免竞态）

## 功能五：工作区快照

### 预期管理

**快照是「工作区骨架」恢复，不是进程精确恢复。** 恢复后用户得到的是：

- 相同的窗口分组结构
- 相同的 pane 布局比例
- 每个 pane cd 到正确的工作目录
- 前台进程会被尝试重新启动（**不保证内部状态一致**）

Shell 历史、后台任务、环境变量、程序内部状态**无法保存**。`--dry-run` 输出会明确提示这一点。

### 命令

```
tmux-workspace save <name>           # 保存当前工作区
tmux-workspace load <name>           # 加载工作区
tmux-workspace load --dry-run <name> # 预览将恢复的内容
tmux-workspace list                  # 列出已保存的工作区
tmux-workspace remove <name>         # 删除工作区
```

### 保存内容

JSON 文件存储在 `~/.local/share/tmux/workspaces/<name>.json`（XDG_DATA_HOME 下，运行时数据）。

```json
{
  "name": "项目A",
  "created": "2026-05-07T14:30:00",
  "tmux_version": "3.4",
  "groups": [
    {
      "name": "app",
      "path": "~/projects/app",
      "windows": [
        {
          "name": "编辑",
          "cwd": "~/projects/app/src",
          "layout": "bd9d,191x45,0,0{57x45,0,0,1,133x45,58,0,2}",
          "layout_ratio": [0.3, 0.7],
          "panes": [
            {
              "cwd": "~/projects/app/src",
              "command": "hx",
              "is_shell": false
            },
            {
              "cwd": "~/projects/app",
              "command": "fish",
              "is_shell": true
            }
          ]
        }
      ]
    }
  ]
}
```

- `layout` 使用 tmux 的 `window-layout` 格式字符串
- `layout_ratio` 记录各 pane 占 window 宽度的相对比例（如 [0.3, 0.7]），作为 layout 字符串失效时的 fallback
- `command` 优先使用 `/proc/<pid>/cmdline` 获取完整命令行；不可用时回退到 `pane_current_command`
- `is_shell` 标记该 command 是否为 shell（通过检查 `/etc/shells` 判断），恢复时 shell 类 pane 不额外发送启动命令
- `tmux_version` 记录保存时的 tmux 版本，用于兼容性判断

### 恢复逻辑

1. 创建新 session
2. 按 JSON 创建窗口，cd 到对应目录
3. 用 `select-layout` 恢复 pane 布局
   - 如果 tmux 版本不匹配且 `select-layout` 失败，使用 `layout_ratio` 按比例手动重建
4. 非 shell 类 pane 通过 `send-keys` 启动记录的 command
   - **V1 简化：** 只恢复 `cwd` + 启动命令（如 `hx`），不尝试推断 editor 打开的文件路径
   - Editor 文件推断（通过 `/proc/<pid>/fd`）作为未来增强项，不在 V1 实现
5. `--dry-run` 输出 JSON 的可读摘要 + 明确提示「不恢复进程内部状态」，不执行任何操作

## 功能六：活动通知

### 机制

tmux 没有直接的「窗口有活动」hook。使用以下方案：

- `set -g monitor-activity on` 启用活动检测（已配置）
- `set -g visual-activity off` 关闭原生通知消息（已配置）
- 在 `status-interval`（如每 15 秒）触发的状态更新中，通过 `#{window_activity_flag}` 格式变量检查每个窗口是否有未读活动
- `sidebar-render` 在渲染时读取该标记，有活动的窗口标签显示不同颜色
- 切换到该窗口后，tmux 自动清除 `window_activity_flag`

无需自定义 hook，利用 tmux 内置的活动检测 + 状态栏刷新周期。

## 功能七：标签页上下文信息

### 信息来源

- **进程名**：实时读取 tmux `pane_current_command`
- **pane/window 标题**：读取 tmux pane title、window name，以及 `@sidebar_window_title`、`@tabby_ai_title`、`@tabby_pane_title`
- **描述**：读取 `@sidebar_window_desc`，否则用路径 basename + `/proc` 前台 cmdline 摘要
- **git branch**：通过 `sidebar-render.scm git` 写入缓存；当前默认不拼进 pane 标题，避免占用窄侧栏空间
- 标签栏渲染脚本负责三件事：实时采集、缓存 fallback、ANSI 格式化输出

### 显示格式与截断规则

标签宽度有限，必须严格控制：

| 字段    | 宽度策略                                     | 截断策略     |
| ------- | -------------------------------------------- | ------------ |
| session | 居中放入侧栏宽度内                           | 超出显示 `…` |
| group   | 扣除树形前缀、展开符、计数后自适应           | 超出显示 `…` |
| window  | 扣除树形前缀、active marker、pane 数后自适应 | 超出显示 `…` |
| pane    | 扣除树形前缀和 pane index 后自适应           | 超出显示 `…` |
| 描述行  | 扣除树形延续线后自适应                       | 超出显示 `…` |

示例：

```
└─ ● 1 very-long-wind… [3]
   ├─   2 pane-title-with-…
   │  source · hx ./README…
   └─ ● 3 fish
      tmux · -fish
```

完整信息可通过 `Ctrl+x i` 弹出详情面板查看。

### 顶部上下文条

状态栏三段式布局（见「状态栏三段式布局」章节）：

- 位置：顶部（`status-position top`）
- 左侧：工作区信息（前缀键、session、git branch、命令、路径、zoom/copy 状态）
- 中央：日期时间（通过 `window-status-current-format` 居中）
- 右侧：系统状态（负载、终端尺寸、主机名）
- 前缀键按下时图标变红，session 名变红，松开恢复
- window tabs 不在 status 中显示，由左侧侧栏承担导航功能
- `window-status-format` 和 `window-status-current-format` 中 strftime 不展开，需用 shell 命令 `#(date +...)`

## 功能八：Kitty 快捷键迁移

原 kitty 配置位于 `dotfiles/immutable/terminal/.config/kitty/kitty.conf`。迁移原则：

- kitty window 约等于 tmux pane
- kitty tab 约等于 tmux window
- 终端原生能力（字体、透明度、IME、窗口装饰、远程控制、hyperlink hover）仍留在 terminal 层
- 已有 tmux 肌肉记忆优先保留，例如 `Alt+方向键` 继续做方向切 pane
- 新增迁移主要放在 `Alt+Shift` 组合上，贴近 kitty 的 `kitty_mod = alt+shift`

已迁移键位：

| Kitty 行为                                | tmux 绑定                                     | tmux 行为                  |
| ----------------------------------------- | --------------------------------------------- | -------------------------- |
| `kitty_mod+n` new_window                  | `Alt+Shift+n`                                 | 在当前路径新建 pane        |
| `kitty_mod+k` close_window                | `Alt+Shift+k`                                 | 确认后关闭当前 pane        |
| `kitty_mod+c` new_tab                     | `Alt+Shift+c`                                 | 在当前路径新建 tmux window |
| `kitty_mod+x` close_tab                   | `Alt+Shift+x`                                 | 确认后关闭当前 tmux window |
| `alt+right/left` next/previous_tab        | `Alt+Shift+Right/Left`                        | 切换 tmux window           |
| `alt+down/up` next/previous_window        | `Alt+Shift+Down/Up`                           | 按 pane 顺序切换           |
| `alt+ctrl+down/up` move_window            | `Alt+Ctrl+Down/Up`                            | 移动当前 pane              |
| `kitty_mod+space` move_window_to_top      | `Alt+Space`                                   | 将当前 pane 移到 pane 1    |
| `kitty_mod+1..0` window index             | `Alt+Shift+1..0`                              | 按 pane 编号选择 pane      |
| `kitty_mod+l` next_layout                 | `Alt+Shift+l`                                 | tmux next-layout           |
| <kbd>kitty_mod</kbd> + <kbd>\\</kbd> tall | <kbd>Alt</kbd>+<kbd>Shift</kbd>+<kbd>\\</kbd> | `main-vertical`            |
| `kitty_mod+-` fat                         | `Alt+Shift+-`                                 | `main-horizontal`          |
| `kitty_mod+r` resize window               | `Alt+Shift+r`                                 | 进入 resize key table      |
| `kitty_mod+h` show_scrollback             | `Alt+Shift+h`                                 | copy-mode 回滚             |
| `kitty_mod+f` search_scrollback           | `Alt+Shift+f`                                 | 搜索回滚                   |
| `kitty_mod+/` command_palette             | `Alt+Shift+/`                                 | tmux command prompt        |
| `shift+insert` paste selection            | `Shift+Insert`                                | 粘贴 primary selection     |

复制模式补齐：

- `Ctrl+x [` 或 `Alt+Shift+h` 进入 copy-mode
- `v` 开始选择
- `y` / `Enter` 复制到 `wl-copy`
- 鼠标拖选结束复制到 `wl-copy`
- `Ctrl+x p` 从剪贴板粘贴

## 实现约束

### 语言规范

**Guile 脚本：**

- 使用 `#!/usr/bin/env guile` shebang + `!#` 入口
- 使用 `(ice-9 match)`、`(srfi srfi-1)` 等标准库
- JSON 操作使用 `(json)` module
- 外部命令调用通过 `(ice-9 popen)` 的 `open-pipe*`
- 错误处理使用 `guard`/`catch`
- 当前短期方案直接解释执行，并在 tmux 中使用 `GUILE_AUTO_COMPILE=0 guile --no-auto-compile` 抑制编译提示；预编译 `.go` 作为后续性能优化项

**Bash 脚本：**

- 使用 `#!/usr/bin/env bash`，显式设置 `set -euo pipefail`
- 仅用于 tmux 生命周期和 fzf 管道胶水（sidebar-toggle、session-selector、window-jump）

### 通用约束

- tmux 最低版本要求：**3.3a**（XDG 支持 + 完善的 `-F` 格式化 + hook 支持）
- 所有脚本启动时检测 tmux 版本，不满足时输出明确错误并退出
- 外部依赖：guile、fzf、git（可选，worktree 检测）
- 不使用 TPM、jq（Guile 原生 JSON），不引入额外包管理器
- 不维护独立主题文件，配色直接使用终端 ANSI 颜色，由 foot/darkman 驱动
- 标签栏渲染性能目标：交互体感无闪烁；当前通过原位重绘、实时采集、缓存 fallback 和 SIGUSR1 主动刷新实现
- 所有涉及文件系统操作的外部调用必须加 timeout，防止 NFS/远程路径阻塞
- 临时文件统一使用 `#{socket_path}` 的 hash 作为隔离键，放在 `/tmp/` 下
- 运行时数据（workspaces）放在 `~/.local/share/tmux/` 下（XDG_DATA_HOME）

## 测试策略

- 使用 `tmux -L test -f ~/.config/tmux/tmux.conf new-session -d` 创建隔离测试环境
- 为 `sidebar-data`、`git-collector`、`workspace` 编写单元测试
- 使用 `hyperfine` 测试渲染性能基准
- P0 已验证：`status-left` 多行渲染在 foot + tmux 中不可作为侧栏方案，已改用 floating pane
- 当前每轮改动后需要至少执行：

```bash
GUILE_AUTO_COMPILE=0 guile --no-auto-compile -s dotfiles/mutable/tmux/.config/tmux/scripts/sidebar-render.scm --as-library
bash -n dotfiles/mutable/tmux/.config/tmux/scripts/sidebar-toggle \
  dotfiles/mutable/tmux/.config/tmux/scripts/session-selector \
  dotfiles/mutable/tmux/.config/tmux/scripts/window-jump
git diff --check -- dotfiles/mutable/tmux
tmux source-file ~/.config/tmux/tmux.conf
```

- 冷启动/多 pane 验证模板：

```bash
tmux -L codex-final kill-server 2>/dev/null || true
tmux -L codex-final -f ~/.config/tmux/tmux.conf new-session -d -s final -n 'long-window-name-for-final-ellipsis-check' -c "$PWD" fish
tmux -L codex-final split-window -h -t final:1 -c "$PWD/source" fish
sleep 1.5
sock=$(tmux -L codex-final display-message -p '#{socket_path}')
sidebar=$(tmux -L codex-final list-panes -a -F '#{pane_id} #{pane_title}' | awk '$2=="tmux-sidebar" {print $1; exit}')
TMUX="${sock},0,0" TMUX_PANE="$sidebar" GUILE_AUTO_COMPILE=0 guile --no-auto-compile -s ~/.config/tmux/scripts/sidebar-render.scm
```

- 鼠标点击验证模板：

```bash
pane_top=$(tmux -L codex-final display-message -p -t "$sidebar" '#{pane_top}')
TMUX="${sock},0,0" TMUX_PANE="$sidebar" GUILE_AUTO_COMPILE=0 \
  guile --no-auto-compile -s ~/.config/tmux/scripts/sidebar-render.scm \
  click $((pane_top + 5)) "$pane_top" "$sidebar"
tmux -L codex-final list-panes -t final:1 -F '#{pane_index}:#{pane_active}'
```

- 截图验收：

```bash
niri msg action screenshot-screen
out=/tmp/tmux-sidebar-$(date +%s).png
wl-paste --type image/png > "$out"
```

## 当前实现状态（2026-05-08）

已完成：

- tmux 配置迁移到 `dotfiles/mutable/tmux/.config/tmux/tmux.conf`
- 侧栏默认显示，窗口标签不再显示在 status 中，status 移到顶部作为上下文条
- `[no tmux data]` 冷启动问题已通过实时采集 + 缓存 fallback 修复
- 数据模型改为每个普通 pane 一条数据，侧栏显示所有 window 下的所有 pane
- 点击 pane/window/group/session 均有动作，点击后通过 `SIGUSR1` 触发侧栏即时重绘
- 树形列表改为完整连续结构，避免断裂的 ASCII 线条
- 所有截断统一使用省略号 `…`，并修正等宽误截断问题
- 支持 `@sidebar_window_title` / `@sidebar_window_desc` 手动覆盖侧栏标题和描述
- 兼容 `@tabby_ai_title` / `@tabby_pane_title`
- kitty 的主要 window/tab/scrollback/copy 快捷键已按 tmux 语义迁移

当前未完成或后续增强：

- workspace 快照功能仍是设计阶段
- Git branch 当前作为缓存能力保留，默认不拼入 pane 标题；后续可考虑在更宽侧栏或详情弹窗中显示
- 预编译 `.go`、性能基准、inotify 优化仍是后续项
- 更复杂的上下文菜单、拖拽重排、右键操作暂不实现
