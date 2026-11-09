---
name: guix-config-maintenance
description: "Guix System 与 Guix Home 配置维护：改配置不生效的排查、shepherd 服务诊断、图形会话环境变量注入、XDG 目录、GNU Stow 与 Guix Home 两轨部署、用户态 daemon 兜底。触发：改 Guix 配置 / herd 排障 / GUI 应用缺环境变量 / dotfile 部署异常——任一出现即调用。"
---

# Guix 配置维护与排障

本 skill 只写通用机制，不绑定具体仓库。示例里的 `/path/to/config` 换成你的配置仓库，部署命令按你用的封装调整。

## 1. 改了配置却不生效

Guix Home 的 dotfile 有两套部署，先确认文件属于哪套。

| 部署方式                                            | 改源后                                                                                 |
| --------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `home-dotfiles-service-type`（通常 `layout 'stow`） | 文件复制进 `/gnu/store` 只读副本，再软链到 `$HOME`。必须重跑 `guix home reconfigure`。 |
| GNU Stow 直链                                       | 单文件软链到 `$HOME`，保存即生效。                                                     |

验证三步：

```bash
# 1. 改源
# 2. 重新部署 Home
guix home reconfigure /path/to/home.scm
# 3. 核对部署位
readlink ~/.config/<app>/<file>
md5sum <源文件> ~/.config/<app>/<file>
```

只重启服务不够。进程读的是 `~/.config` 下的软链，软链没换，读到的还是旧副本。

反方向同理：直接删 `~/.config` 下的文件，下次重跑 Home 会从 store 副本链回来。要删就从仓库源删。

## 2. shepherd 服务排查

### 先从 service 视角看

不要手动执行 service 的启动命令。它绕开 service 上下文，改坏的是用户环境，而且下次 hered 重启会覆盖。

四步取证：

```bash
# 1. 状态与缓存的 PID
herd status <service>
# 2. 进程是否真活着
cat /proc/<pid>/cmdline
ls -la /proc/<pid>/cwd
# 3. 完整 service 历史（含 on-change gexp 报错）
grep "<service-keyword>" /var/log/messages
# 4. 修根因后重启服务
herd restart <service>
```

### cached PID 不可信

`make-forkexec-constructor` 不 wait 子进程。子进程死后 shepherd 仍缓存旧 PID。真相只在日志与 `/proc/<pid>` 里。

### 服务 environment 必须在 start 时求值

把 `#:start` 写成 `(lambda args ((make-forkexec-constructor ... (environ)) args))`，不要直接给 `(make-forkexec-constructor ...)` 的求值结果。

直接给求值结果时，`(environ)` 在加载配置时就被固化成快照。登录瞬间图形会话变量还没就绪，`DISPLAY`、`WAYLAND_DISPLAY`、`DBUS_SESSION_BUS_ADDRESS` 全部缺失。`herd set-environment` 改的是 shepherd 进程环境，回填不了已固化的快照，`herd restart` 也无效。

### 服务命令不要带 `--replace`

`make-forkexec-constructor` 的命令里出现 `--replace`（典型来自上游 daemon 的自踢开关）会形成循环：新进程启动，给前任发 SIGTERM，前任非零退出，`respawn? #t` 判定失败又重启，再次踢自己。日志里 `Received SIGTERM as a planned --replace takeover` 与 `Another instance is already running` 交替出现。从服务定义里删掉该参数。

### 不要用 `pgrep -f` 抓服务 PID

终端工具的整段命令行会出现在 `bash -c` 的 cmdline 里，`pgrep -f "<模式>"` 必然匹配到自己，`kill -9` 会连带杀掉当前会话。按端口抓用 `ss -tlnpH 'sport = :<port>'` 取 `pid=`，按进程名抓用 `pgrep -x <comm>`。

### 多个 home-shepherd 并存

`herd restart` 只作用于当前连接的 daemon。旧 daemon 还活着时，它仍持有旧服务定义。诊断：

```bash
pgrep -af "shepherd-for-home"   # 多个 PID = 并存
ps -o pid,etime,cmd -p $(pgrep -f "shepherd-for-home")
```

清理：SIGTERM 旧 daemon，确认只剩一个，再 `herd restart <service>`。旧服务留下孤儿进程时一并终止。

### 日志是本地化的

shepherd 日志按 locale 输出。grep 英文 `Respawning` 常为空，改 grep 本地化文案（如「正在重启」）或用服务名搜。

## 3. 图形会话的环境变量从哪来

双击 `.desktop` 启动的应用缺环境变量（输入法不弹、Electron 打不了字、Qt 字体不对、代理不生效）时，先问：它启动时谁在喂它环境。

在 Guix 加 niri、greetd 这类非 systemd 启动链里，变量来源只有三处：

1. 合成器配置的 `environment { ... }` 块，对它启动的所有子进程生效。
2. 会话启动脚本里的 `dbus-update-activation-environment`，喂给经 D-Bus 激活的服务。
3. `herd set-environment`，喂给 shepherd 启动的服务。

不在链里的：`~/.profile`、`~/.bashrc` 只影响 login shell；`~/.config/environment.d/*.conf` 需要 systemd 的用户会话管理器，Guix 上不生效；`systemctl --user show-environment` 同理查不到东西。

### 标准做法

合成器配置里三处一起改：

```kdl
environment {
  XDG_CURRENT_DESKTOP "niri"
  GTK_IM_MODULE "fcitx"
  QT_IM_MODULE "fcitx"
  XMODIFIERS "@im=fcitx"
  SDL_IM_MODULE "fcitx"
  GLFW_IM_MODULE "ibus"
}

spawn-sh-at-startup "herd set-environment graphical-session DISPLAY=$DISPLAY WAYLAND_DISPLAY=$WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=$XDG_CURRENT_DESKTOP XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR XDG_SESSION_TYPE=$XDG_SESSION_TYPE GTK_IM_MODULE=$GTK_IM_MODULE QT_IM_MODULE=$QT_IM_MODULE XMODIFIERS=$XMODIFIERS SDL_IM_MODULE=$SDL_IM_MODULE GLFW_IM_MODULE=$GLFW_IM_MODULE"

spawn-sh-at-startup "dbus-update-activation-environment WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP GTK_IM_MODULE QT_IM_MODULE XMODIFIERS SDL_IM_MODULE GLFW_IM_MODULE"
```

`$VAR` 在这条启动命令里可能还是空，因为合成器自己的环境没有这些变量。要么保证 `environment` 块先求值，要么把值写成字面量。

改完重跑 `guix home reconfigure`，再重启整个图形会话。多数合成器不支持热重载主配置。验证：

```bash
tr '\0' '\n' < /proc/$(pgrep -f <app>)/environ | grep GTK_IM_MODULE
```

### 常见变量

| 类别       | 变量                                                                                 | 症状                                       |
| ---------- | ------------------------------------------------------------------------------------ | ------------------------------------------ |
| 输入法     | `GTK_IM_MODULE` / `QT_IM_MODULE` / `XMODIFIERS` / `SDL_IM_MODULE` / `GLFW_IM_MODULE` | Electron、Qt、SDL、GLFW 应用打不了中文     |
| Wayland    | `WAYLAND_DISPLAY` / `XDG_RUNTIME_DIR`                                                | 应用找不到 wayland socket，退回 X11 或黑屏 |
| 显示       | `DISPLAY` / `XDG_SESSION_TYPE`                                                       | XWayland 回落、会话类型识别错误            |
| 桌面       | `XDG_CURRENT_DESKTOP`                                                                | portal 集成失效                            |
| Locale     | `LANG` / `LC_ALL` / `LANGUAGE`                                                       | 界面乱码                                   |
| 代理       | `http_proxy` / `https_proxy` / `HTTP_PROXY` / `HTTPS_PROXY`                          | Electron、Qt 应用不走终端代理              |
| 光标与字体 | `XCURSOR_PATH` / `FONTCONFIG_PATH` / `QT_QPA_FONTDIR`                                | 主题或字体 fallback                        |

### XCURSOR_PATH 是整体替换

`XCURSOR_PATH` 被赋值时替换掉 xcursor 的内置搜索路径，不是追加。写成 `("XCURSOR_PATH" . "$XDG_DATA_HOME/icons")` 会让搜索范围只剩一个目录，Guix profile 里的光标主题找不到，光标退回默认。

正确写法保留父环境路径：

```scheme
("XCURSOR_PATH" . "$XCURSOR_PATH:$XDG_DATA_HOME/icons")
```

诊断探针：

```c
#include <X11/Xcursor/Xcursor.h>
#include <stdio.h>
#include <stdlib.h>
int main(void) {
  printf("env = %s\n", getenv("XCURSOR_PATH") ? getenv("XCURSOR_PATH") : "(unset)");
  printf("path = %s\n", XcursorLibraryPath());
  return 0;
}
```

```bash
guix shell libx11 libxcursor gcc -- gcc probe.c -lXcursor -o probe
env XCURSOR_PATH=$HOME/.local/share/icons ./probe
env -u XCURSOR_PATH ./probe
```

## 4. XDG 与环境变量的注入分层

不同层次的进程用不同机制。没有单一手段覆盖全部。

| 层次               | 机制                                                            | 用途                            |
| ------------------ | --------------------------------------------------------------- | ------------------------------- |
| 用户 session       | `home-environment-variables-service-type`                       | XDG 基础目录、`EDITOR`、`PAGER` |
| Wayland session    | `home-graphical-session-service-type`                           | `XDG_SESSION_TYPE` 等会话标记   |
| GUI 应用           | 合成器 `environment {}` 加 `dbus-update-activation-environment` | 输入法、Wayland、桌面集成       |
| Portal 路由        | `xdg-desktop-portal` 的 `portals.conf`                          | 截图、文件选择器、通知后端      |
| 系统服务           | `#:environment-variables`                                       | 服务进程自身的环境              |
| 定时器与 gexp 脚本 | gexp 里 `setenv`                                                | 运行时补变量                    |

### 用户 session 变量

```scheme
(define %xdg-env
  '(("HISTFILE" . "$XDG_STATE_HOME/bash/history")
    ("CARGO_HOME" . "$XDG_DATA_HOME/cargo")
    ("NPM_CONFIG_USERCONFIG" . "$XDG_CONFIG_HOME/npm/npmrc")
    ("PYTHON_HISTORY" . "$XDG_STATE_HOME/python/history")))

(simple-service 'xdg-env home-environment-variables-service-type %xdg-env)
```

加一项再重跑 `guix home reconfigure` 即生效。

### Wayland 会话标记

```scheme
(service home-graphical-session-service-type
  (home-graphical-session-configuration
    (wayland? #t)
    (x11? #t)))
```

缺少这个标记时，portal 的 ScreenCast 与 Screenshot 接口会静默失败，flatpak 应用的截图和文件选择器不好使。

### Portal 后端

`portals.conf` 里的实现 ID 必须与已安装的 portal 包对应：

| 包                         | 实现 ID |
| -------------------------- | ------- |
| `xdg-desktop-portal-gnome` | `gnome` |
| `xdg-desktop-portal-gtk`   | `gtk`   |
| `xdg-desktop-portal-wlr`   | `wlr`   |

改了 `portals.conf` 要同时确认包在 profile 里，否则该后端不存在，portal 静默回落。

### 服务与脚本

系统服务用 `#:environment-variables`，只影响该服务进程。gexp 生成的定时器或脚本在文件里 `setenv`，作用范围是脚本自身。

### daemon 配置用绝对路径

shepherd 起的 daemon 在启动时 `$HOME` 未必是用户家目录。配置里写 `~/.guix-home/profile/bin/<tool>` 这类相对路径会展开失败，daemon 退回内置默认值或直接报错。

用 `$$bin/<tool>$$` 之类的构建期路径注入，写成 `/gnu/store/...` 绝对路径。验证：

```bash
gpgconf --check-programs   # 看实际解析到的 pinentry 路径
```

## 5. GNU Stow 与 Guix Home 两轨

同一份仓库可以同时用两种部署：

| 模型      | 链路                                             | 改源后                       |
| --------- | ------------------------------------------------ | ---------------------------- |
| Guix Home | 源复制到 `/gnu/store` 只读副本，再软链到 `$HOME` | 必须 `guix home reconfigure` |
| GNU Stow  | 源直接软链到 `$HOME`                             | 立即生效                     |

GNU Stow 适合高频手改、需要 git 备份的配置。常用命令：

```bash
stow -d /path/to/dotfiles -t "$HOME" <pkg>            # 部署
stow -d /path/to/dotfiles -t "$HOME" --restow <pkg>   # 重建链接
stow -d /path/to/dotfiles -t "$HOME" --delete <pkg>   # 撤销
```

### 陷阱

- 不要让两套部署指向同一文件。Guix Home 的软链与 Stow 的软链会互相覆盖。
- 应用会把配置原子写成实体文件（临时文件加 rename），stow 的软链因此断掉。重新部署前先用 `md5sum` 比对仓库源与部署位，以较新者为准：仓库新就重建链接，部署位新就先把内容拷回源。
- `stow` 遇到一个实体文件冲突就中止整个包，已经处理的文件不会回补。先跑 dry run 预览，或逐文件检查部署位是链接、实体还是缺失。
- 删 `$HOME` 下的原文件不要用 `rm`。安全做法是拷到源，再把原文件移到临时目录，部署成功后再清理。

## 6. 用户态 daemon 的兜底配置

用户态 daemon（wireplumber、swayidle、gammastep 等）行为不符合预期，而 Guix 的系统配置没有对应开关时，需要在 `~/.config/<daemon>/` 注入用户态配置。前提是 daemon 会读这个目录，多数 daemon 默认只读系统目录。

### 先分类再动手

| 根因                      | 表现                           | 兜底                                  |
| ------------------------- | ------------------------------ | ------------------------------------- |
| daemon 的自动行为被误触发 | 某条件触发后状态被改并持久化   | 配置层关掉该行为                      |
| 状态恢复把错误状态读回来  | 状态文件里的旧值反复回放       | 行为层 hook 强制覆盖                  |
| 启动顺序                  | 服务比 daemon 先起，配置没读到 | 行为层加 ready hook                   |
| 上游 bug                  | 无解                           | 接受现状，写 workaround，不跟上游硬碰 |

### 配置层加行为层

wireplumber 的例子：配置层在 `~/.config/wireplumber/wireplumber.conf.d/` 关掉 automute，行为层在 `~/.config/wireplumber/scripts/40-alsa/` 放 Lua 脚本，监听 `node-state-changed`，把 ALSA sink 的 mute 写回 false。

目录名里的数字控制加载顺序，`40-` 先于上游的 `50-` 注册，才能抢到 hook 时机。配置层负责关掉默认行为，行为层负责兜底纠正，两者缺一不可。

### 防覆盖

用户态配置的源文件放在仓库里，再用第二套部署方式落到 `~/.config`。只改部署位不改源，下次部署会被覆盖。验证方式同第 1 节。

## 7. 常见误判

- **Electron 应用输入法失效**：先确认 `GTK_IM_MODULE` 等变量进了应用环境，再对 Electron 版本查 flag 差异。不同 Electron 版本读的变量不同，部分版本需要 `--enable-wayland-ime`。
- **portal 功能静默失败**：先看 `XDG_SESSION_TYPE` 与 `portals.conf`，再查后端包是否安装。
- **改了 dotfile 没生效**：先判断属于哪套部署，再确认部署位软链指向哪个 store 副本。
- **服务重启后仍用旧配置**：shepherd 的 environment 在加载时固化，改定义后要重启服务，不是重跑 `guix home reconfigure` 就够。

## 延伸阅读

- `references/electron-wayland-ime-debug.md`：Electron 应用在 Wayland 下输入法失效的完整诊断，含 flag 与版本对照。
- `references/gpg-agent-pinentry-absolute-store-path.md`：daemon 配置必须用绝对路径的取证与修复。
- `references/xdg-dot-dir-migration.md`：把家目录点目录迁到 XDG 目录的流程。
