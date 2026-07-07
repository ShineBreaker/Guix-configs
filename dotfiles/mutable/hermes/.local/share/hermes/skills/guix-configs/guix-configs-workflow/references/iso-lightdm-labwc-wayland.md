# ISO lightdm autologin + labwc Wayland session（实战沉淀）

> 来源：2026-07-07 会话。在 `source/config.org` 的 `live-installation-os` 块（装机 ISO）里
> ① 修 lightdm 自动登录真正落进 XFCE 桌面；② 注入 labwc 作为可选 Wayland session。
> 所有字段名均对照仓库锁定的 `guix 9e068cc` 的本地源码 `gnu/services/lightdm.scm` 验证过。

## 0. 先确认这段是 ISO 还是主机配置

`source/config.org` 里有**两套**桌面栈：
- 主机配置：走 `(gnu services ...)` 主 `operating-system`，tangle 到 `tmp/config.scm`。
- ISO 配置：`live-installation-os` 块，tangle 到 `tmp/live-iso.scm`（独立 `#+NAME:` + `:tangle ../tmp/live-iso.scm`）。

改 lightdm 前**先定位 tangle 目标**——本会话改的是 ISO 段（含 `make-installation-os` / `live` user / `slim` 包），不影响主机。
主机若也想 autologin，是另一处独立配置，不要混用。

## 1. lightdm 自动登录的关键：autologin-user 必须配 user-session

lightdm 的 `lightdm-seat-configuration` 字段（`guix 9e068cc`，`gnu/services/lightdm.scm:263`）：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `name` | seat-name | `*` 匹配所有 seat |
| `user-session` | maybe-string | 默认进的 session 名（小写，如 `"xfce"`） |
| `type` | seat-type | `'local` / `'xremote`，默认 `'local` |
| `autologin-user` | maybe-string | 自动登录的用户名 |
| `greeter-session` | greeter-session | 默认 `'lightdm-gtk-greeter` |
| `xserver-command` | maybe-file-like | 通常不用填 |
| `session-wrapper` | file-like | 默认 `(xinitrc)` |
| `extra-config` | list-of-strings | 追加到 seat 段 |

**典型坑**：只写 `(autologin-user "live")` 不写 `user-session`，lightdm 自动登录后不知道进哪个桌面，
**停在 greeter 等选 session**，看起来像"没自动登录"。修复就是补一行 `(user-session "xfce")`。

`user-session` 的值 = `share/xsessions/<name>.desktop` 里的 session 名。XFCE 是 `xfce`
（验证：`/gnu/store/*xfce4-session*/share/xsessions/xfce.desktop` 的 `[Desktop Entry]` / `Name=Xfce Session`）。
lightdm 的 `sessions-directory` 扫 `share/xsessions` + `share/wayland-sessions`（`lightdm.scm:443-445`），
所以 session 名必须与 `.desktop` 文件名（去掉 `.desktop`）一致。

## 2. 给 ISO 加一个 Wayland session（labwc，无 service-type）

Guix **没有** `labwc-desktop-service-type`（XFCE 有，labwc 没有官方 service 封装）。
要让 labwc 作为可选 Wayland session 出现在 lightdm greeter，做法：

**(a) 装包**：`"labwc"` + `"xwayland"`（labwc 0.20 默认自动拉起 Xwayland，让 XFCE 的 X11 app 在 wayland 下仍可用）。
验证：`/gnu/store/7zgni80jiqddpy7127lh8yvpk48bqmkd-guix-9e068cc/gnu/packages/wm.scm:4830` 有 `(define-public labwc "0.20.1")`。

**(b) 造一个 synthetic 包**写 `share/wayland-sessions/labwc.desktop` —— labwc 包本身不提供 `.desktop`，
但 lightdm 的 `sessions-directory` 会扫这个目录，所以放进去 greeter 就能列出 "Labwc"。

```scheme
;; use-modules 需加: (guix packages) (guix licenses) (guix build-system trivial)
(define labwc-wayland-session
  (package
    (name "labwc-wayland-session")
    (version "0")
    (source #f)
    (build-system trivial-build-system)
    (arguments
     (list #:builder
           #~(begin
               (use-modules (guix build utils))
               (let ((out #$output))
                 (mkdir-p (string-append out "/share/wayland-sessions"))
                 (call-with-output-file
                     (string-append out "/share/wayland-sessions/labwc.desktop")
                   (lambda (port)
                     (display "[Desktop Entry]
Name=Labwc (Wayland)
Comment=Labwc stacking Wayland compositor
Exec=labwc
Type=Application
" port)))))))
    (home-page "https://labwc.github.io")
    (synopsis "Wayland session entry for labwc")
    (description "Provides a Labwc entry in the display manager's wayland session list.")
    (license license:gpl2)))
```

**(c) 并进 packages**：把 `labwc-wayland-session` 并进**同一个** `(append ...)`（不要新开一个 append，见 §3 坑）：

```scheme
(packages
 (append (specifications->packages
          '( ... "labwc" "xwayland" "network-manager" ...))
         (list labwc-wayland-session)
         (operating-system-packages %live-base-os)))
```

**(d) 不动 autologin**：`user-session` 仍 `"xfce"`，autologin 默认进 XFCE；labwc 作为 greeter 里**手动可选**的项。
这是最稳的形态（纯 wayland autologin 实验性，ISO 上易黑屏）。

## 3. 改 packages 段的两个真实坑（本会话踩过）

- **坑 A — 把单个 `append` 拆成两个 append**：patch 时若把原 `(append (specifications->packages '(...)) (operating-system-packages %live-base-os))`
  在中间断开、另起一个 `(append (list labwc-wayland-session) (operating-system-packages %live-base-os))`，
  第一个 append 只剩一个参数且缺闭合括号 → `blue check` 报 `多余 1 个左括号 (open=116 close=115)`。
  **修复**：合并成一个 append，把新增项并进去（见上面 (c)）。
- **坑 B — 误删相邻项**：第二个 patch 的 `old_string` 没包含 `"network-manager-applet"`，替换后把它丢了。
  写 patch 时 `old_string` 必须覆盖**完整的**受影响行，不要为了"精准"而漏掉同行列表里的兄弟项。

## 4. 验证（AI 不跑 rebuild）

```bash
cd ~/Projects/Config/Guix-configs && blue check    # 括号平衡，秒级，不写系统
```

`blue check` 通过 = 块级括号合法。真正生效需用户手动 `blue rebuild`（生成 `tmp/live-iso.scm` + 打包 ISO），
装机盘启动后 greeter 会列出 "Labwc (Wayland)"，autologin 默认仍进 XFCE。

## 5. 字段验证的离线法（对照 §8.2 坑 2）

不要只信 web 手册（本环境 `web_extract` 对 guix.gnu.org 报 "Blocked: URL targets a private or internal network address"）。
锁定的 guix 已在 `/gnu/store`，直接 grep 本地源码：

```bash
# 列出所有含 lightdm.scm 的 guix store 路径（注意可能有多个版本）
ls -d /gnu/store/*guix*/gnu/services/lightdm.scm
# 用 channel.lock 的 commit 锁定版本:
grep commit ~/Projects/Config/Guix-configs/source/channel.lock   # 拿到 9e068cc...
ls -d /gnu/store/*9e068cc*/gnu/services/lightdm.scm
# 读 define-configuration 确认字段
grep -n -A 30 'define-configuration lightdm-seat-configuration' \
  /gnu/store/*9e068cc*/gnu/services/lightdm.scm
```

这比 `curl` 到 savannah 更稳：**commit-exact**（仓库锁定的版本），且离线可用。
