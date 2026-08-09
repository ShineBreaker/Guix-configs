---
name: wine-protocol-forwarding
description: "修复 Wine 应用自定义 URL 协议（OAuth 回调 app://）在 Linux 浏览器无法跳回的方案。覆盖 handler 注册、Wine 二进制匹配诊断、flatpak 容器内/外 IPC 兼容性。"
triggers:
  - Wine app login opens browser but callback never returns
  - 浏览器提示没有程序能处理自定义协议
  - OAuth redirect_uri 指向自定义 scheme 无法回调
  - Wine 应用注册了 URL Protocol 但 Linux 不响应
  - handler 触发了但应用日志显示 "joining" 后回调数据未转发
  - Wine 二进制不匹配（Bottles Proton-CachyOS vs Guix 标准版）
  - Bottles Wine 容器外报 `/lib/ld-linux.so.2: could not open`
---

# Wine 自定义 URL 协议转发（Linux 宿主端）

## 场景

Windows 应用通过 Wine 运行时，常使用自定义 URL 协议（如 `starecho.xutryeditor://`、`discord://`、`vscode://`）做 OAuth 登录回调。流程：

```
Wine 应用 → LaunchURL(https://oauth.server/...)
         → Wine start.exe 转给 Linux 默认浏览器
         → 用户在浏览器完成认证
         → 服务器 302 重定向到 app://callback?code=xxx
         → ❌ Linux 没有该协议 handler → 跳转失败
```

## 根因

Wine 注册表里虽然注册了协议（`HKCU\Software\Classes\<scheme>\shell\open\command`），但这**只对 Wine 内部有效**。原生 Linux 浏览器走 XDG MIME 查询 handler，不会读 Wine 注册表。

## 修复三步

### 1. 编写 Handler 脚本

创建 `~/.local/bin/<app>-handler.sh`：

```bash
#!/bin/bash
export WINEPREFIX="<用户的 Wine 前缀路径>"
WINE="<wine 二进制路径>"
EXE_PATH="<Windows 应用的 Linux 绝对路径>"
WORK_DIR="<应用工作目录>"
CALLBACK_URL="$1"

cd "$WORK_DIR"
"$WINE" "$EXE_PATH" "--callback-flag=$CALLBACK_URL" >> /tmp/<app>-handler.log 2>&1 &
disown
```

关键：
- `WINEPREFIX` 必须和运行应用的 prefix 一致
- 回调参数名（`--starecho-callback`、`--callback` 等）需从 Wine 注册表或应用字符串中确认
- 用 `disown` 让 Wine 进程脱离调用它的 shell，避免浏览器等待 handler 退出

### 2. 创建 Desktop Entry

创建 `~/.local/share/applications/<app>-handler.desktop`：

```ini
[Desktop Entry]
Type=Application
Name=<应用名> Callback Handler
Exec=/home/<user>/bin/<app>-handler.sh %u
Terminal=false
StartupNotify=false
MimeType=x-scheme-handler/<scheme>;
NoDisplay=true
```

### 3. 注册 XDG MIME 关联

创建或追加 `~/.local/share/applications/mimeapps.list`：

```ini
[Default Applications]
x-scheme-handler/<scheme>=<app>-handler.desktop
```

验证：
```bash
xdg-mime query default x-scheme-handler/<scheme>
# 应返回 <app>-handler.desktop
```

## 诊断流程

1. **确认 Wine 注册表已有协议注册**
   ```bash
   WINEPREFIX=<prefix> wine reg query "HKCU\Software\Classes\<scheme>\shell\open\command"
   ```

2. **查看应用日志确认 redirect_uri scheme**
   - 从日志中找到 `LaunchURL ...&redirect_uri=<scheme>%3A%2F%2Fcallback`

3. **确认 Linux 端缺少 handler**
   ```bash
   xdg-mime query default x-scheme-handler/<scheme>
   # 空结果 = 没有 handler
   ```

4. **测试 handler 脚本手动触发**
   ```bash
   bash ~/.local/bin/<app>-handler.sh "<scheme>://callback?code=test"
   # 检查 /tmp/<app>-handler.log
   ```

5. **刷新桌面环境**（重新登录或重启 compositor）让新 MIME 生效后，在浏览器中完整走一遍 OAuth 流程验证

## 关键陷阱

### 1. Wine 二进制不匹配（最常见死穴）

**handler 用错了 Wine = 回调永远传不过去**

应用通过 Bottles/Lutris/Heroic 等 manager 启动时，manager 使用自己的 Wine（如 Proton-CachyOS、GE-Proton）。如果 handler 里调用的是 Guix/Nix 宿主安装的 Wine，两个 Wine 二进制虽然版本号可能相同，但：

- 编译差异（CachyOS 定制版 vs 标准版）导致 IPC 机制不兼容
- **在 flatpak 沙箱外运行时，Bottles 的 Wine 可能直接报错退出**：`/lib/ld-linux.so.2: could not open`（容器内才有 32-bit loader）
- 即使能启动，两个不同来源的 Wine 进程也无法通过 mutex/pipe 共享单实例状态

**症状**：
- Handler 日志显示"Received callback"和"Forwarded to Wine"
- 应用日志显示 `Login already in progress; joining the active request`（单实例检测成功）
- 但回调 URL 实际没有传过去，登录永远卡住
- FMOD 报 `Cannot listen for connections, port 9264 is currently in use`（第二个实例试图完整初始化）

**诊断**：
```bash
# 确认 manager 用的是哪个 Wine
cat ~/.local/share/wine/bottle.yml | grep Runner
# → Runner: Proton-CachyOS Latest

# 找到 manager Wine 的实际二进制
find ~/.var/app/com.usebottles.bottles/data/bottles/runners/ -name "wine" | head -3

# 测试 manager Wine 能否在容器外直接运行
WINEPREFIX=/home/brokenshine/.local/share/wine \
  /path/to/manager/wine --version
# 如果报错 /lib/ld-linux.so.2: could not open → 不能在容器外运行
```

**修复方向**（按优先级）：

A. **在 manager 容器内运行 handler**（推荐）：
```bash
#!/bin/bash
CALLBACK_URL="$1"
flatpak run --command=bash com.usebottles.bottles -c "
WINE='/home/brokenshine/.var/app/com.usebottles.bottles/data/bottles/runners/Proton-CachyOS Latest/files/bin/wine'
EXE='Z:\\\\home\\\\brokenshine\\\\Programs\\\\xuTryEditor_Remake\\\\xuTryEditor\\\\Binaries\\\\Win64\\\\xuTry.exe'
\"$WINE\" \"\$EXE\" \"--starecho-callback=$CALLBACK_URL\"
" &
```
→ 验证：`flatpak run --command=bash` 在容器内启动的实例是否和 manager 启动的实例共享 IPC。

B. **用 patchelf 修改 manager Wine 的 interpreter** 让它在容器外也能运行：
```bash
# 找到容器的 ld-linux.so.2
flatpak run --command=ls com.usebottles.bottles /lib/ld-linux.so.2

# patchelf 改 interpreter 指向容器内的 loader
patchelf --set-interpreter /path/to/container/ld-linux.so.2 /path/to/manager/wine
```

C. **统一 Wine 来源**：用 manager 的 Wine 启动整个应用（不通过 manager GUI 而是命令行），这样 handler 也用同一个 Wine。

### 2. IPC 机制诊断

应用单实例检测 ≠ 回调转发成功。需要验证：

```bash
# 启动第一个实例（后台）
WINEPREFIX=<prefix> <wine> <exe> &
PID1=$!

# 等待启动
sleep 15

# 用第二个实例发送回调
WINEPREFIX=<prefix> <same-wine-as-first> <exe> "--starecho-callback=<url>"

# 检查第一个实例日志是否有：
# - "Login already in progress" → 单实例检测OK
# - "Received callback" / "callback received" → 数据转发OK
# - FMOD port conflict → 第二个实例完整初始化，数据未转发
```

### 3. 其他陷阱

- **Guix 环境 shebang**：Guix 系统没有 `/bin/bash`，只有 `/usr/bin/env bash`。handler 脚本第一行**必须**写 `#!/usr/bin/env bash`，否则 `xdg-open` 调用时会报 `env: "...": 没有那个文件或目录`
- **exec ... & 是矛盾写法**：`exec` 替换当前进程，`&` 后台化。应去掉 `exec`，直接用 `"$WINE" ... &` + `disown`
- **WINEPREFIX 不匹配**：handler 启动的 Wine 进程和应用运行时的 prefix 必须一致
- **参数名不匹配**：从 Wine 注册表或 `strings <exe> | grep callback` 确认参数名（如 `--starecho-callback`）
- **桌面环境缓存**：创建 desktop entry 和 mimeapps.list 后可能需要重新登录 DE/WM（niri 需重新登录会话）

## 参考实例

见 `references/starecho-xutry.md` —— 实际修复 starecho.xutryeditor OAuth 回调的完整记录。
