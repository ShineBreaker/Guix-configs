# starecho.xutryeditor OAuth 回调修复实例

## 背景

应用：xuTryEditor（UE5 应用通过 Wine 运行）
Wine 前缀：`/home/brokenshine/.local/share/wine`
浏览器：zen（XDG 默认）
桌面：niri (Wayland)

## 故障现象

1. 用户启动 xuTry.exe，点击登录
2. 应用调用 `LaunchURL` 打开 `https://starecho.net/oauth/authorize?...&redirect_uri=starecho.xutryeditor%3A%2F%2Fcallback...`
3. Wine 正确转给 Linux 浏览器 zen
4. 用户在浏览器完成登录
5. 服务器 302 重定向到 `starecho.xutryeditor://callback?code=xxx&state=yyy`
6. ❌ 浏览器弹出错误：没有应用程序能处理该协议

## 根因分析

从应用日志确认协议 scheme：
```
LogWindows: LaunchURL https://starecho.net/oauth/authorize?...&redirect_uri=starecho.xutryeditor%3A%2F%2Fcallback...
```

从 Wine 注册表确认协议已注册（但只对 Wine 内部有效）：
```
[Software\\Classes\\starecho.xutryeditor\\shell\\open\\command]
@="\"Z:\\home\\brokenshine\\Programs\\xuTryEditor_Remake\\xuTryEditor\\Binaries\\Win64\\xuTry.exe\" --starecho-callback=\"%1\""
```

确认 Linux 端缺少 handler：
```bash
$ xdg-mime query default x-scheme-handler/starecho.xutryeditor
# (空结果)
```

## 修复步骤

### 1. 创建 Handler 脚本

`/home/brokenshine/.local/bin/starecho-handler.sh`：
```bash
#!/bin/bash
export WINEPREFIX="/home/brokenshine/.local/share/wine"
WINE="/home/brokenshine/.guix-home/profile/bin/wine"
EXE_PATH="/home/brokenshine/Programs/xuTryEditor_Remake/xuTryEditor/Binaries/Win64/xuTry.exe"
WORK_DIR="/home/brokenshine/Programs/xuTryEditor_Remake/xuTryEditor/Binaries/Win64"
CALLBACK_URL="$1"

if [ -z "$CALLBACK_URL" ]; then
    echo "$(date): No URL provided" >> /tmp/starecho-handler.log
    exit 1
fi

cd "$WORK_DIR"
"$WINE" "$EXE_PATH" "--starecho-callback=$CALLBACK_URL" >> /tmp/starecho-handler.log 2>&1 &
disown
```

### 2. 创建 Desktop Entry

`/home/brokenshine/.local/share/applications/starecho-handler.desktop`：
```ini
[Desktop Entry]
Type=Application
Name=StarEcho xuTry Callback Handler
Exec=/home/brokenshine/.local/bin/starecho-handler.sh %u
Terminal=false
StartupNotify=false
MimeType=x-scheme-handler/starecho.xutryeditor;
NoDisplay=true
```

### 3. 注册 MIME 关联

`/home/brokenshine/.local/share/applications/mimeapps.list`：
```ini
[Default Applications]
x-scheme-handler/starecho.xutryeditor=starecho-handler.desktop
```

### 4. 验证

```bash
$ xdg-mime query default x-scheme-handler/starecho.xutryeditor
starecho-handler.desktop
```

手动触发测试：
```bash
$ bash /home/brokenshine/.local/bin/starecho-handler.sh "starecho.xutryeditor://callback?code=test"
$ cat /tmp/starecho-handler.log
# 确认 Wine 进程正常启动
```

## 关键参数确认方法

从 Wine 注册表找到 `--starecho-callback=` 参数名：
```bash
WINEPREFIX=/home/brokenshine/.local/share/wine wine reg query \
  "HKCU\Software\Classes\starecho.xutryeditor\shell\open\command"
```

输出中的 `--starecho-callback=\"%1\"` 表明应用期望接收此参数来接收回调 URL。

## 后续诊断：handler 触发但回调数据未转发（2026-08-07）

上述修复已完成，handler 确实被触发（`xdg-mime query default x-scheme-handler/starecho.xutryeditor` 返回 `starecho-handler.desktop`），但回调数据没有传给第一个实例。

### 诊断过程

1. **确认 handler 被触发**：`/tmp/starecho-handler.log` 显示 `Received callback` 和 `Forwarded to Wine`
2. **确认单实例检测成功**：应用日志显示 `Login already in progress; joining the active request`
3. **但回调数据未转发**：第二个实例打印 `Cannot listen for connections, port 9264 is currently in use`（FMOD 端口冲突），然后完整初始化图形界面
4. **发现 Wine 版本不匹配**：
   - Bottles 用 `Proton-CachyOS Latest` 的 Wine（`wine-11.0 (CachyOS)`）
   - Handler 用 Guix 安装的 Wine（`wine-11.0`）
   - 两个 Wine 二进制在容器外直接运行时，Bottles Wine 报错 `/lib/ld-linux.so.2: could not open`

### 根因

handler 用错了 Wine 二进制 → 两个不同来源的 Wine 进程无法通过 mutex/pipe 共享单实例状态 → 第二个实例虽然检测到第一个实例存在，但回调 URL 数据未通过 IPC 转发。

### 未验证的修复方案

1. **通过 `flatpak run --command=bash` 在 Bottles 容器内运行 handler**（推荐）
2. **用 patchelf 修改 Bottles Wine 的 interpreter** 让它在容器外也能运行
3. **统一 Wine 来源**：不通过 manager GUI，用命令行 + manager Wine 启动应用和 handler

→ 本次会话在方案验证阶段结束，下次继续需从这三个方向之一推进。

## 实际修复：用户将应用移到容器外（2026-08-07 续）

用户最终选择将应用从 Bottles 容器移出，直接用 Guix 宿主 Wine 运行整个应用。这样 handler 也用同一个 Wine，IPC 兼容性不再有问题。

### 关键修复点

1. **shebang 必须用 `#!/usr/bin/env bash`**：Guix 环境下 `/bin/bash` 不存在，只有 `/usr/bin/env bash` 可用。handler 脚本第一行写 `#!/bin/bash` 会导致 `xdg-open` 报 `env: "/home/brokenshine/.local/bin/starecho-handler.sh": 没有那个文件或目录`。

2. **MIME 关联创建后需重新登录桌面环境**：创建 `.desktop` 文件和 `mimeapps.list` 后，必须重新登录 niri/WM 让新的 XDG MIME 关联生效，否则浏览器不会调用 handler。

3. **验证 handler 触发的最终手段**：
   ```bash
   xdg-open "starecho.xutryeditor://callback?code=test"
   ```
   如果返回 `env: "...starecho-handler.sh": 没有那个文件或目录`，说明 shebang 有问题；如果静默成功且 `/tmp/starecho-handler.log` 有输出，说明 handler 已正确注册。

### 后续验证

截至会话结束，handler 已能正确触发（`xdg-open` 测试通过），但完整 OAuth 流程尚未验证（用户需重新登录桌面环境后才能测试）。下次会话应跟进完整登录流程是否成功。
