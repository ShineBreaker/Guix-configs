<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com -->
<!-- SPDX-License-Identifier: MIT -->

# quicktui-server — 远程终端服务（手机/网页经配对接入本机 tmux）

上游 Rust 单文件发行二进制（无仓库源码） · 手动部署到 `~/.local/bin/quicktui-server` + `~/.config/quicktui-server-v2/` · 调用方：home shepherd 常驻（`quicktui`）与手动配对/管理

QuickTUI 提供 HTTP + WebSocket 终端入口，设备配对后可 attach 本机 tmux 会话；AgentBridge2（AB2）另把本机各 agent 宿主（claude / codex / opencode / pi）的生命周期事件转发到同一入口。服务在 `source/config.org`「QuickTUI 远程终端」以 `home-daemon-service` 声明，日志落 `$XDG_STATE_HOME/shepherd/quicktui.log`。

## 用法

```bash
quicktui-server serve                 # 前台起服务（日常由 shepherd 拉起，勿手动）
quicktui-server doctor                # 自检外部依赖（tmux / herdr / 登录 shell PATH）
quicktui-server pairing welcome       # 配对引导（终端内交互）
quicktui-server pairing qrcode        # 打印短效配对二维码
quicktui-server pairing devices list  # 已配对设备
quicktui-server config show           # 打印配置原文
quicktui-server hooks status          # 各宿主的 AB2 hook 安装态
```

服务侧操作用 shepherd，不用 `systemctl`：`herd status quicktui` / `herd restart quicktui` / `herd stop quicktui`。

### 安装（手动，替代上游 `curl | sh`）

上游 `curl -fsSL https://dl.quicktui.cn/q.sh | sh` 只做一件事：下载 `quicktui-installer-linux-amd64`（release tag `installer-20260927-01`，sha256 校验后 `exec`）。Rust installer 再按 `https://dl.quicktui.cn/server-manifest.json` 的 `default_channel`（当前 `server2`）解析出 server release，下载 `quicktui-server-<os>-<arch>` 并校验，然后落盘到 `~/.local/bin/quicktui-server`、写 `~/.config/quicktui-server-v2/config.toml`、通过 server 自己的 `--setup-from-installer` 装 AB2 hooks，最后注册**systemd 用户服务**。本机是 Shepherd 初始系统、没有 systemd，自动注册那一步必然失败，故改为手动安装：

```bash
base=https://dl.quicktui.cn/releases/download/server2-20261002-01
curl -fsSL "$base/quicktui-server-linux-amd64" -o ~/.local/bin/quicktui-server
curl -fsSL "$base/quicktui-server-linux-amd64.sha256" -o /tmp/qs.sha256
(cd ~/.local/bin && sha256sum -c /tmp/qs.sha256)   # f0c532a3…78c64b
chmod +x ~/.local/bin/quicktui-server
quicktui-server hooks install                        # 装 AB2 hooks（幂等，可重复执行）
```

签名链：`.sha256` 之外还有 `.minisig`（minisign，Ed25519）。installer 内嵌公钥的 key id 为 `35fe7a218dcd84aa`；本机没有 `minisign`，用 python 复核（`cryptography` 库在 profile 内，签名在第 2 行、被签内容是二进制本体）：

```bash
curl -fsSL "$base/quicktui-server-linux-amd64.minisig" -o /tmp/qs.minisig
python3 - <<'PY'
import base64
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
pk = bytes.fromhex('d5d2eb3d768a124c76ed1616bc1457c2a7d961b939bd3b15d730a76ded91d44f')  # key id 35fe7a218dcd84aa
lines = open('/tmp/qs.minisig','rb').read().split(b'\n')
sig = base64.b64decode(lines[1])[10:]                # 2 字节算法 + 8 字节 key id + 64 字节签名
Ed25519PublicKey.from_public_bytes(pk).verify(sig, open('/home/brokenshine/.local/bin/quicktui-server','rb').read())
PY
```

升级换版本时先读 `https://dl.quicktui.cn/server-manifest.json` 拿当前 `default_channel` 与对应 tag，再按上面两步重下。

`doctor` / `serve` 首次运行会把探测到的 tmux、herdr 绝对路径与 `session_backend=herdr` 写回 `config.toml`（自动探测字段带 `_auto` 后缀），这是上游行为，配置文件属运行时状态、不入库。

### 升级

`quicktui-server upgrade check` 看是否有新 release（按 `update_channel`，当前 `server2`，实测 current == latest `server2-20261002-01`），`upgrade install` 自更新后重启服务。上游 installer 的 `--tag` / `--channel` 只是换下载源，本机不走它。

## 实现与约束

- **二进制不进 Guix profile**：server 要 attach 的是本机 tmux 默认 socket（`/tmp/tmux-1000/default`）与 `$HOME` 下的配置/配对状态，store 只读副本拿不到这些；`session_backend` 探测到的 `herdr`（`herdr_bin`）与 tmux 也都只在用户 profile 里。
- **服务走 `home-daemon-service` 而非 systemd**：上游 `service install` 只认 `systemctl --user`，本机没有 systemd。`source/config.org` 内的路径写成 `#~(string-append (getenv "HOME") …)`，让 HOME 在**服务启动时**求值——去掉 `#~` 会以重建时的用户（可能是 root）取 `/root` 并烘焙进服务闭包（hermes-services 同款约定）。
- **AB2 hooks 由 server 自管，禁止手改**：`~/.config/claude/settings.json`、`~/.config/codex/hooks.json`、`~/.config/opencode/plugins/agentbridge2.js`、`~/.pi/agent/extensions/agentbridge2.ts` 四处文件里带 `_ab2_managed` 标记的块全部由 `hooks install` / `hooks uninstall` 增删；claude 的 `settings.json` 改写前会留 `settings.json.ab2-backup-<时间戳>` 备份。这些文件本身多由各自应用拥有，手工编辑会与下一次 `hooks install` 冲突。
- **installer 不认沙箱 HOME**：若 `$HOME` 与 euid 对应的 passwd home 不一致，installer 打 warning 后**改用 passwd home 落盘**（实测 `HOME=/tmp/... ` 时全部写进了真实家目录）。想在隔离环境试跑必须让 `$HOME` 与 passwd 记录一致，或直接手动安装。
- **监听面**：默认 `addr = "0.0.0.0:8022"`（局域网可达，纯 HTTP + 设备配对 + 端到端加密）。只想本机用时 `quicktui-server config set addr 127.0.0.1:8022` 后 `herd restart quicktui`。
- **依赖探测**：server 用「登录 shell PATH」找 tmux（≥3.2）与 herdr，本机两者都在 `~/.guix-home/profile/bin`；缺失时上游流程会去装 tmux 3.6a 到 `~/.local/tmux/` 或 `curl | sh` 装 Herdr——本机都不需要。
- **tmux socket 目录必须 0700**：server 启动时校验 socket 所在目录「属主为当前用户且模式 0700」，不满足就拒绝该 backend 并继续跑（不退出）。默认配置的 `/tmp/tmux-1000/` 由 tmux 首次启动时自建，本就是 0700，实测通过；只有把 socket 指到 `/tmp` 这类 1777 目录才会触发拒绝。改 `tmux_socket` 时确保新目录是 0700 且属主是自己。
- **只读 reconcile**：server 常驻后每 10s 跑一轮 tmux 状态对账（`list-sessions` / `show-options` / `has-session`），不新建、不改写会话（实测对账期间用户既有 `Quake` / `main` 会话无变化）。

## 排障

| 现象                                | 原因                                          | 处理                                            |
| ----------------------------------- | --------------------------------------------- | ----------------------------------------------- |
| `herd status quicktui` 显示反复重启 | `~/.local/bin/quicktui-server` 缺失或不可执行 | 按上方步骤重新落盘二进制                        |
| agent 宿主事件到不了                | AB2 hooks 被应用重写覆盖                      | `quicktui-server hooks install` 补装            |
| 端口占用                            | 别的进程占了 8022                             | `config set addr 127.0.0.1:<新端口>` 后重启服务 |
