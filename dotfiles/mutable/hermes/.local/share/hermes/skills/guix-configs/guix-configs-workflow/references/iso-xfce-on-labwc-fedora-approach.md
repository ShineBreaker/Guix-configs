# ISO: XFCE-on-labwc (Wayland) via Fedora's three-file approach

> 实战 2026-07-07。从 Fedora RPM `xfce4-session-wayland-session-4.20.3-2.fc44.x86_64.rpm`
> 解包研究,落地到 Guix-configs 的 `source/config.org` `live-installation-os` 块。

## 1. 核心机制(为什么能跑)

XFCE 4.20 的 `startxfce4` 原生支持 `--wayland`:它会把窗口管理器换成 labwc(Wayland
compositor),XFCE 的 panel/apps 全部跑在 labwc 上。不需要 Guix 有专门的
`xfce-wayland-service-type`。

**离线验证**(本环境 `web_extract` 对 guix.gnu.org 报 "Blocked: URL targets a
private or internal network address",浏览器可用但分页找不到 `lightdm-seat-configuration`):
直接 grep 本地锁定版 guix 源码,更准且 commit-exact:

```bash
# channel.lock 里 guix commit = 9e068cc...
# 实际 bin/startxfce4, 4.20.4:
grep -n -- "--wayland" /gnu/store/*xfce4-session-4.20.4/bin/startxfce4
#   49: elif test "x$OPT" = "x--wayland"
#   79: XDG_SESSION_TYPE="wayland" / 85: GDK_BACKEND="wayland,x11" / 89: QT_QPA_PLATFORM="wayland"
# labwc 0.20.1 存在:
grep -n "(define-public labwc" /gnu/store/*9e068cc*/gnu/packages/wm.scm  # :4830
```

## 2. Fedora RPM 解包(三件套)

```bash
# 没 rpm 命令时, libarchive 的 bsdtar 能解 cpio 包
bsdtar -tf xfce4-session-wayland-session-*.rpm
# ./usr/share/wayland-sessions/xfce-wayland.desktop
# ./usr/share/xfce4/labwc/labwc-rc.xml
# ./usr/share/xfce4/labwc/labwc-environment
bsdtar -xf *.rpm -C /tmp/xfce-wayland
```

三文件作用:
- `xfce-wayland.desktop`: `Exec=startxfce4 --wayland`, `DesktopNames=XFCE`。
- `labwc-rc.xml`: 主题 Adwaita、4 桌面、W-Return 起 `xfce4-terminal`、W-F4 关窗、
  音量键 `amixer ...`、W+数字切桌面。**Fedora 版用 `amixer -D pulse`,ISO 上
  pulseaudio 可能不在,改 `amixer sset Master`(去掉 `-D pulse`)。**
- `labwc-environment`: `XKB_DEFAULT_LAYOUT=en` + `XCURSOR_THEME=Adwaita`。

## 3. 在 Guix ISO 里落地的等价三件套(synthetic package)

labwc 包本身**不提供** `.desktop` / rc / environment。手动造一个 `trivial-build-system`
包,把这三个文件写进对应目录:

- `share/wayland-sessions/xfce-wayland.desktop` —— lightdm 的 `sessions-directory`
  扫这个目录(`lightdm.scm:443-445`),greeter 就能列出 "Xfce Session (Wayland)",
  且能被 `user-session` 选中。
- `share/xfce4/labwc/labwc-rc.xml`
- `share/xfce4/labwc/labwc-environment`

packages 段并入 `"labwc"` + `"xwayland"`(labwc 0.20 默认自动拉起 Xwayland,
X11 app 在 wayland 下仍可用)。synthetic 包并进**同一个** `(append ...)`(不要新开
append,否则第一个 append 缺闭合 -> 括号失衡,见 SKILL.md §8.2 坑 5b)。

lightdm `user-session` 改成 `"xfce-wayland"` -> autologin 直接进 Wayland 版 XFCE。

## 4. 写 synthetic package 时 `blue check` 括号平衡的实战坑

`blue check` 只数**真实 Scheme 结构括号**(不计入字符串内括号、不计入 `;;` 注释内
括号)。手写带多行 `display "..."` 的包时,收尾 `))))))))` 极易数错,而且 `patch`
工具 fuzzy match 会偷偷改 `)` 数量(见 SKILL.md §8.2 坑 1)。

**已验证的调试路径(本会话实测)**:
- `blue check` 报 `多余 N 个右括号 (open=129 close=131)` 时,`open` 是固定基线,
  `close` 随你改的收尾 `)` 数量线性变化(8个->+2, 9个->+1, 10个->+4 非单调是因为
  中途还改了别处)。**不要靠推理数括号**——直接二分/单步调收尾 `)` 数量,每次
  `blue check` 看 open/close 差值收敛。本会话最终收尾是 **6 个 `)`**(`" port))))))`)
  才平衡。
- **XML 属性用双引号会引入 `\"` 转义**,在 `(display "...")` 里让结构更难读且
  易错。labwc 的 `labwc-rc.xml` 改用**单引号属性**(`<font name='sans'/>`),
  libxml2/labwc 都支持,字符串里彻底无 `\"`,可读性 + 平衡都更好。
- **`.desktop` / `description` 里的 `(Wayland)` `(labwc)` 括号**:`blue check` 不计入
  字符串内括号(已验证 open 计数不受其影响),所以保留无妨;但为干净也可去掉括号写法。

**结论**: 手写 multi-file synthetic package 时,优先用模板骨架,把文件内容用单引号
XML 属性,`blue check` 后以"调收尾 `)` 数量 + 看 open/close 差值"为唯一收敛手段,
不要试图手算括号数。

## 5. 仍待确认的运行时点

- ISO 里 `xfce4-terminal` 已在 packages,W-Return 能起它。
- 音量键用的 `amixer` 需 `alsa-utils` —— 若 ISO packages 没装,labwc 音量键无效
  (不影响登录)。需要可加 `"alsa-utils"`。
- XFCE 4.20 + labwc 真实硬件 Wayland 支持取决于显卡驱动,需实际启动验证桌面能否起来。
