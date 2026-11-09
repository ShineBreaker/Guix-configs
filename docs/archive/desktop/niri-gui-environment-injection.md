# niri GUI 应用环境变量注入实战

具体场景：Guix-configs 仓库 + niri 桌面 + greetd 登录 + fcitx5 输入法 + nix-profile 装的 Electron/Qt 应用（hermes-desktop / QQ 等）。提炼自 2026-06-21 hermes-desktop + QQ 双击 .desktop 没输入法问题修复。

## 现象

- 终端里 `hermes-desktop`（或 `QQ`）能正常打字
- 桌面图标双击启动的同一个应用，fcitx 候选窗不弹
- `/proc/<pid>/environ` 缺 `GTK_IM_MODULE=fcitx` / `QT_IM_MODULE=fcitx` / `XMODIFIERS=@im=fcitx` 等

## 根因

Guix + niri + greetd 启动链里，GUI 应用的环境变量来源：

```
TTY login → greetd-tuigreet → niri-session → niri → 子进程(GUI app)
```

每个环节喂环境的方式不同；**任一环节没喂，子进程就没拿到**。

实测诊断命令(`pgrep -af 'systemd --user'`、`systemctl --user show-environment`)显示：Guix 默认配置下 systemd --user **没在跑**（用户的 niri 是 TTY 启动，不是 systemd --user 拉起）。所以 `~/.config/environment.d/*.conf` **不被读**,`systemctl --user show-environment` 是空。

## 解决方案：niri "环境注入三件套"

在 `dotfiles/immutable/desktop/.config/niri/config.kdl` 同时改三处，GUI 应用就有完整环境：

```kdl
environment {
  XDG_CURRENT_DESKTOP "niri"
  GTK_IM_MODULE "fcitx"
  QT_IM_MODULE "fcitx"
  XMODIFIERS "@im=fcitx"
  SDL_IM_MODULE "fcitx"
  GLFW_IM_MODULE "ibus"
}

spawn-sh-at-startup "herd set-environment graphical-session XDG_CURRENT_DESKTOP=$XDG_CURRENT_DESKTOP XDG_SESSION_TYPE=$XDG_SESSION_TYPE NIRI_SOCKET=$NIRI_SOCKET DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS WAYLAND_DISPLAY=$WAYLAND_DISPLAY PATH=$PATH:$XDG_STATE_HOME/nix/profile/bin:$HOME/.local/bin"

spawn-sh-at-startup "dbus-update-activation-environment WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP GTK_IM_MODULE QT_IM_MODULE XMODIFIERS SDL_IM_MODULE GLFW_IM_MODULE"
```

（`DISPLAY` 不必在此列——`x11-display` 服务会在依赖链上游 `setenv`；IME 变量只喂 niri 子进程，shepherd 服务不需要。注意 `herd set-environment` 只改 shepherd 进程环境，**对加载时已固化环境列表的服务无效**，见下节「求值时机陷阱」。）

三处作用：

1. `environment { }`——niri 给所有子进程注入（主战场）
2. `herd set-environment`——喂 Guix shepherd 拉起的服务
3. `dbus-update-activation-environment`——喂 dbus activation 环境（影响 dbus 拉起的服务，如 fcitx5 dbus interface）

## Shepherd 服务拿不到图形环境变量：求值时机陷阱

> 2026-11-03 实证。clipsync / mpris-proxy / poweralertd / waydroid-session 登录后连续失败三次被 shepherd 禁用，而 `herd eval root '(getenv "WAYLAND_DISPLAY")'` 明明有值。

### 现象

- 服务日志：`缺少 DISPLAY / WAYLAND_DISPLAY`、`Can't get on session bus`、`Unable to autolaunch a dbus-daemon without a $DISPLAY`。
- shepherd 进程当时**已经有**这些变量（`herd eval` 可查），`herd restart` 也不恢复，`herd enable && herd start` 仍失败。
- 同一批服务里，Guix 自带的（nosdshell / sunshine）却正常。

### 根因

服务定义里的环境列表在**加载定义时**就被求值并固化，不是每次 start 时读：

```scheme
;; 错误：加载 config 的那一刻就调用 make-forkexec-constructor，
;; (environ) 从此固定为「shepherd 刚启动、niri 尚未就绪」的快照
(start (make-forkexec-constructor
        (list ...)
        #:environment-variables (environ)))
```

shepherd 登录时先于 niri 加载配置，快照里没有 `DISPLAY` / `WAYLAND_DISPLAY` / `DBUS_SESSION_BUS_ADDRESS`。之后 niri 的 `herd set-environment` 或 `wayland-display` 服务的 `setenv` 只改 shepherd 进程的环境，**不会回填已经固化的列表**。所以依赖 `graphical-session` 也没用——依赖只决定启动顺序，不改变快照时机。

### 正确写法（Guix 自家 home 服务类型同款）

把构造调用放进 start 过程的函数体，每次 start 重新求值：

```scheme
(start (lambda args
         ((make-forkexec-constructor
           (list ...)
           #:environment-variables (environ)
           #:log-file (string-append (getenv "XDG_STATE_HOME") "/shepherd/foo.log"))
          args)))
```

`#:start` 必须是 `(lambda args (...))`，不能是 `(make-forkexec-constructor ...)` 的直接求值结果。`herd restart` 会重新执行这个 lambda，因此改完环境后 restart 即可生效，无需重启 shepherd。

### 对照实验（可复现）

```bash
# 旧形式：加载时固化
herd eval root '(putenv "SENTINEL=before")'
herd load root /tmp/svc-old.scm      # #:start (make-forkexec-constructor ... (environ))
herd start svc-old                   # → before
herd eval root '(putenv "SENTINEL=after")'
herd restart svc-old                 # → 仍是 before

# 新形式：start 时求值
herd load root /tmp/svc-new.scm      # #:start (lambda args ((make-forkexec-constructor ... (environ)) args))
herd start svc-new                   # → after
```

### 自查

```bash
# 配置里所有直接求值的 start 都是潜在受害者
grep -n '#:start (make-forkexec-constructor' source/config.org
grep -rn 'make-forkexec-constructor' dotfiles/mutable/agents/*/.local/share/adhoc-services/
```

本仓库的 `home-daemon-service` 已按此模式实现；自己手写开关服务时照抄同一形式。

### 热验证单个服务：`herd load` 必须包 `register-services`

Guix 生成的 `/gnu/store/*-shepherd-<svc>.scm` 末尾只是一个裸 `(service ...)` 表达式，没有注册动作。直接 `herd load root` 它会打印「正在加载」却**什么都不注册**，随后 `herd status` 看到的是旧定义——很容易误判成「修了没用」。先 `herd unload root <name>` 让名字空出来，再用包装文件加载：

```scheme
;; /tmp/verify-<svc>.scm
(use-modules (shepherd service))
(register-services
 (list (primitive-load "/gnu/store/<hash>-shepherd-<svc>.scm")))
```

```bash
herd stop <svc>; herd unload root <svc> || true
herd load root /tmp/verify-<svc>.scm
herd enable <svc>; herd start <svc>
tr '\0' '\n' < /proc/$(herd status <svc> | grep -oP '主 PID：\K[0-9]+')/environ | grep -E '^(DISPLAY|WAYLAND_DISPLAY|DBUS_SESSION_BUS_ADDRESS)='
```

注意两点：`herd load` 只收绝对路径（相对路径报 `open-fdes: 没有那个文件或目录`）；这种手工加载只活在当前 shepherd 进程里，`blue home` 重启 shepherd 后会回到 conf 里的定义。

### 边界：set-environment 之后仍有小竞态

- `DISPLAY` / `WAYLAND_DISPLAY`：由 `x11-display` / `wayland-display` 服务在依赖链上游 `setenv`，服务 start 时必然已在，无竞态。
- `DBUS_SESSION_BUS_ADDRESS`：实测 shepherd 启动时就已经在环境里（登录链提供），早于 niri 注入即有值，无竞态。
- `NIRI_SOCKET` / `XDG_CURRENT_DESKTOP`：只有这两个是 niri 自己 `spawn-sh-at-startup` 注入的，与 `graphical-session` ready 并行，存在百毫秒级窗口。服务若需要它们，在入口加短轮询等变量出现，或把变量前移到登录链而不是 niri 内注入。

## 部署 + 生效流程（三步缺一不可）

```bash
# 1. 改完 .kdl 后 blue home(让 store 副本同步)
blue home

# 2. 重启 niri 会话 —— 重要!niri 主配置不支持热重载
#    两条路:
#    a) 直接登出再登录
#    b) 终端跑 pkill -f 'niri --session',greetd 会自动重启 niri
pkill -f 'niri --session'

# 3. 验证环境注入生效
cat /proc/$(pgrep -f hermes-desktop | head -1)/environ | tr '\0' '\n' | grep -E 'GTK_IM_MODULE|QT_IM_MODULE|XMODIFIERS'
# 应输出:GTK_IM_MODULE=fcitx / QT_IM_MODULE=fcitx / XMODIFIERS=@im=fcitx
```

## 验证三件套清单

确认生效：

```bash
# niri 配置软链接指向最新 store hash(蓝 home 后)
readlink ~/.config/niri/config.kdl

# fcitx5 在跑(没跑就先跑 fcitx5 -r 或查 service)
pgrep -af fcitx5

# systemd --user 在不在(决定 environment.d 是否生效,通常为空就行)
pgrep -af 'systemd --user'

# 终端 vs GUI 起的同一应用的环境对比
env | grep -E 'GTK_IM|QT_IM|XMODIFIERS'                                          # 终端
cat /proc/$(pgrep -f hermes-desktop | head -1)/environ | tr '\0' '\n' | grep ...  # GUI
```

## 关键事实（踩过的坑）

- **Guix 不用 systemd**（用户原话 "Guix不使用 systemd!"——2026-06-21）。所以 `~/.config/environment.d/` / `systemctl --user show-environment` 在 Guix 这条链里基本是死路；不要先绕这里。
- **`source/nix/` 那条 home-manager 配置跟 Guix 不互通**（根 AGENTS.md 写明）。改 `i18n.inputModule.type = "fcitx5"` 只影响 nix 那条链；你用 `blue home` 部署不会生效。
- **niri 主配置不支持热重载**（`niri msg action reload-config` 只对部分子配置生效，`environment { }` 块和 `spawn-sh-at-startup` 列表不支持）。改完必须重启 niri 会话。
- **改 .kdl 文件后再 `blue home`,store 副本变了；但 `pkill niri --session` 之后 greetd 重启的 niri 读的是软链接 target**(`/gnu/store/<hash>-home-dotfiles--config-niri-config-kdl`)——所以 `blue home` 必须先于 `pkill`。
- **`spawn-sh-at-startup "dbus-update-activation-environment WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP"` 是用户已有的**——漏加 fcitx 变量会导致通过 dbus 拉起的服务（fcitx5 客户端）拿不到 env。

## 一并治本的范围

修完三件套，所有 GUI 应用共用：

- nix-profile 装的 Electron 应用(hermes-desktop / QQ / VSCode Slack Discord)
- nix-profile 装的 Qt 应用(Yaak / qtscrcpy / PrismLauncher)
- 任何未来装的 GUI 应用（Chromium / Firefox / Steam / 等等）
- Guix 装的 GUI 应用也走这条路

所以**改一次覆盖所有**——不要针对某个 .desktop 单独修 Exec=。

## 反模式（单独修某个 .desktop 的 Exec=——仅当三件套够用时）

如果只用方案 "改 hermes.desktop 的 Exec= 加 env":

```ini
# ~/.local/share/applications/hermes.desktop
Exec=env GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx ... /home/brokenshine/.nix-profile/bin/hermes-desktop %U
```

副作用：

1. **治标**：QQ / Steam / VSCode / 等等还是没输入法
2. **易腐烂**：nix-profile rebuild 会从 `/nix/store` 软链覆盖回来，改动消失
3. **硬编码**：DISPLAY=:0 / WAYLAND_DISPLAY=wayland-1 写死，SSH 进不同机器失效

只有当用户明确要求"只修这一个应用"、或者这个应用是 sandbox 里跑的（niri 三件套喂不到）时，才用单 .desktop 修法。

**例外**：当三件套已正确注入（env vars 齐全）、但 Electron 版本差异导致仍不工作时，见下方 §"三件套全对但仍不工作（版本差异坑）"——此时 `.desktop` 覆盖是正确解法。

## 三件套全对但 Electron 应用仍不工作（版本差异坑）

> 提炼自 2026-06-22 QQ 输入法问题：niri 三件套已部署、`NIXOS_OZONE_WL=1` 已注入、
> 所有 IME env vars 确认存在，但 `fcitx5-diagnose` 显示 `focus:0`。

### 现象

- niri `environment { }` 块 + `herd set-environment` + `dbus-update-activation-environment` 全部已配
- `cat /proc/<pid>/environ | tr '\0' '\n' | grep NIXOS_OZONE` → `NIXOS_OZONE_WL=1` ✓
- `GTK_IM_MODULE=fcitx` / `QT_IM_MODULE=fcitx` / `XMODIFIERS=@im=fcitx` 全部存在
- `fcitx5-diagnose` → `program:QQ frontend:wayland_v2 cap:72 focus:0`
- 同一 compositor(niri) + 同一 fcitx5 下，另一个 Electron 应用(hermes-desktop, Electron 41) **工作正常**（`focus:1`）

### 根因

**Electron 版本差异**导致 Wayland IME 实现成熟度不同：

| Electron 版本                | Chromium 版本 | Wayland IME 行为                                                                              |
| ---------------------------- | ------------- | --------------------------------------------------------------------------------------------- |
| **41.7.2**（hermes-desktop） | ~134          | Wayland IME 默认工作，cmdline 零 flag 也正常                                                  |
| **~29–32**（QQ 内嵌版）      | ~122–128      | 需要 `--enable-features=UseOzonePlatform` feature flag；缺则 text-input-v3 协议无法激活 focus |

QQ wrapper 的条件块 `${NIXOS_OZONE_WL:+--ozone-platform-hint=auto ...}` 只加了 `--ozone-platform-hint=auto`
和 `--enable-features=WaylandWindowDecorations`，**缺了 `UseOzonePlatform`**。

### 诊断三步（确认是版本差异而非环境缺失）

```bash
# 1) 确认环境变量齐全（排除三件套未生效）
#    对比 工作进程 vs 不工作进程 的 /proc/<pid>/environ
cat /proc/<pid_works>/environ | tr '\0' '\n' | sort > /tmp/env-ok.txt
cat /proc/<pid_fails>/environ | tr '\0' '\n' | sort > /tmp/env-fail.txt
comm -23 /tmp/env-ok.txt /tmp/env-fail.txt    # OK 有 FAIL 没有的

# 2) 确认 cmdline flag 差异
cat /proc/<pid_works>/cmdline | tr '\0' ' '
cat /proc/<pid_fails>/cmdline | tr '\0' ' '
# → 看是否缺少 UseOzonePlatform / ozone-platform 等 flag

# 3) 确认 Electron 版本差异
readlink -f /proc/<pid>/exe   # 拿到 store 路径
strings <store-path>/<binary> | grep -oP 'Chrome/\d+' | sort -u  # Chromium 版本
# 或查 store 路径里的 electron-unwrapped 版本号
```

### 解法：`.desktop` 覆盖（补 cmdline flag）

当三件套已生效但 Electron 版本太老时，`.desktop` 覆盖是正确做法（不是反模式）——补上缺失的 flag：

```ini
# ~/.local/share/applications/qq.desktop（XDG 用户级覆盖系统级）
[Desktop Entry]
Name=QQ (Wayland IME fix)
Exec=/nix/store/<hash>-qq/bin/qq --ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations --enable-wayland-ime=true --wayland-text-input-version=3 %U
Terminal=false
Type=Application
Icon=/nix/store/<hash>-qq/share/icons/hicolor/512x512/apps/qq.png
StartupWMClass=QQ
Categories=Network;
```

新增的 flag（相对原 wrapper 输出）：

- `--ozone-platform=wayland`（替代 wrapper 的 `--ozone-platform-hint=auto`；强制 Wayland，不 fallback）
- `--enable-features=UseOzonePlatform`（**关键**：补上缺失的 Ozone platform feature）

XDG 规范保证 `~/.local/share/applications/qq.desktop` 覆盖系统级 qq.desktop，无需改 nix store。

### 备选：走 XWayland（最稳但不够 native）

如果 Wayland IME 还是不行（尤其老 Electron + wlroots compositor 已知 bug 多），强制 X11 + XIM：

```
Exec=.../bin/qq --ozone-platform-hint=x11 %U
```

走 XWayland 后 IME 依赖 `XMODIFIERS=@im=fcitx`（已在三件套注入），比 Wayland text-input-v3 成熟稳定。

## 关联场景

- "黑屏" 但 fcitx 没弹 → §6.2 三件套 + 重启 niri
- "改了 niri 配置不生效" → `blue home` + `pkill niri --session`，改 .kdl 不是改完就生效
- "终端能起 GUI 应用但 .desktop 起不行" → 100% 是环境变量；对比两端 `/proc/<pid>/environ` 差异
- "改了 home-manager 输入法配置没生效" → `source/nix/` 与 Guix 不互通；走 niri 三件套
- "改了 `~/.config/environment.d/` 没生效" → Guix 不用 systemd；走 niri 三件套
