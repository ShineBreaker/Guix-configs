# ISO: KDE Plasma 桌面在 Guix Live ISO 上的装配（实战沉淀）

> 来源：2026-07-07 会话。用户把 Live ISO 从 XFCE 改成 **KDE Plasma**，原改动导致打包失败。
> 本文件记录 KDE 专有的装配要点 + 本次修复的完整错误序列 + 验证结果。
> 与 `iso-build-debug.md` 的 XFCE/lightdm/labwc 内容互补——本文件只讲 KDE。

## 0. 结论（已验证可启动）

`blue build-iso desktop` 在本仓库修完配置后**成功出盘**：

```
dist/jeans-desktop-20260707.x86_64-linux.iso   5.2 GB
file type: ISO 9660 CD-ROM filesystem data (DOS/MBR boot sector) 'GUIX_IMAGE' (bootable)
sha256: 0844693d652c1020a09d107e144ed5a47ea786b1da045682a903f350af80ede8
```

构建全程 exit code 0，无 service 图折叠错误。这是本仓库**第一个真正构建成功的 KDE ISO**（原 XFCE 版此前从未真跑到 fold-services 阶段）。

## 1. KDE 装配要点（与 XFCE 的本质差异）

| 维度 | XFCE 版（旧） | KDE Plasma 版（新） |
| --- | --- | --- |
| 桌面 service | `xfce-desktop-service-type` | `plasma-desktop-service-type`（来自 `(gnu services desktop)`） |
| 显示管理器 | `lightdm-service-type` | `sddm-service-type`（来自 `(gnu services sddm)`） |
| 桌面自带 DM？ | 否（lightdm 独立） | **否**——`plasma-desktop-service-type` 只 extends polkit/dbus/pam/profile，**不**带 DM，必须显式加 sddm |
| session 名 | `xfce`（`.desktop` 去扩展名） | `plasma`（SDDM 的 `auto-login-session` 值 = `"plasma.desktop"`） |
| 依赖 elogind？ | 否（installer 用 mingetty/kmscon） | **是**——SDDM 的 `display-server "x11"` 路径拉 `xorg-server`，xorg-server 依赖 elogind，installer 基座不含它 |

### 1.1 SDDM 配置字段（对照锁定版 guix 源码验证）

`gnu/services/sddm.scm`（`channel.lock` 锁定 commit）的 `sddm-configuration` 字段：

- `(display-server "x11")` —— 默认 x11；写 `"wayland"` 在当前版本不真正生效（注释说"enabled by wayland greeter PR"，未合）
- `(auto-login-user "live")` —— 自动登录用户（配合 live user 弱密码）
- `(auto-login-session "plasma.desktop")` —— **必须带 `.desktop` 后缀**（源码注释示例：`xfce.desktop` / `gnome.desktop`）。值 = `share/wayland-sessions/` 或 `share/xsessions/` 下 `.desktop` 文件名去扩展名后加 `.desktop`

> 注意：SDDM 的 `auto-login-session` 与 lightdm 的 `user-session` 不同——SDDM **必须**写 `"plasma.desktop"`（带后缀），lightdm 写 `"xfce"`（不带后缀）。混用会导致 autologin 后进不去桌面。

### 1.2 elogind 必须显式加

```scheme
(list (service elogind-service-type)          ; 关键，否则报 'xorg-server 需要 elogind'
      (service plasma-desktop-service-type)
      (service sddm-service-type
        (sddm-configuration
          (display-server "x11")
          (auto-login-user "live")
          (auto-login-session "plasma.desktop"))))
```

报错原文：`服务 'xorg-server' 需要 'elogind'，但没有任何服务提供该服务`。
根因：installer 基座（`%installation-services`）用 mingetty/kmscon 而非登录管理器，不含 elogind；SDDM 的 xorg 路径间接依赖它。

## 2. 本次修复的完整错误序列

按出现顺序（每条都实测过）：

### 错误 1：tangle 失败 — `<<live-xfce-define>>` 死引用

用户把 XFCE 改成 KDE 时，把 `live-xfce-define` 块整段删了，但 `live-installation-os` 块里还残留 `<<live-xfce-define>>` 引用 → tangle 阶段直接失败。
**修复**：删掉该 noweb 引用。

### 错误 2：`services` 字段结构破碎 + 括号失衡

用户改动把 `(append <<guix-substitutes>> )` 提前闭合，后面 `(operating-system-services %live-base-os)` 和 `(modify-services %desktop-services ...)` 成了 `operating-system` 的非法多余字段初值；且 `operating-system`/`define` 两层外括号数错（末行 `))))` 缺/多）。

**修复**：重建 services 为 `(append <<guix-substitutes>> (list plasma sddm elogind) (operating-system-user-services %live-base-os))))`，收尾 5 个 `)` 平衡（102/102 验证通过）。

### 错误 3（核心根因）：`多余一个类为'account'/'pam'/'profile'的目标服务`

修复括号后进入 fold-services，报 `多余一个类为'account'的目标服务`（之后改 plasma-only 变 `pam`、加 sddm 变 `profile`——同源）。

**根因**（决定性）：`operating-system-services`（system.scm:890）会自动 `(append (operating-system-user-services os) (operating-system-essential-services os))`，即**自动把 essential 服务（system/boot/pam/account/shepherd-root 等单实例核心服务）注入一次**。原代码把 `(operating-system-services %live-base-os)` 又作为 `services` 字段值写进去 → 这些核心服务被注册**两遍** → 单实例服务冲突。

原 XFCE 版的 `(append ... (operating-system-services %live-base-os))` **也踩了同一个坑**，只是从没真跑到 fold-services 阶段，所以一直没暴露。

**修复**：services 字段改用 `operating-system-user-services`（只取用户服务，不含 essential），让 `operating-system` 自己在求 `operating-system-services` 时补 essential **一次**：

```scheme
(services
 (append
  <<guix-substitutes>>
  (list (service elogind-service-type)
        (service plasma-desktop-service-type)
        (service sddm-service-type
          (sddm-configuration
            (display-server "x11")
            (auto-login-user "live")
            (auto-login-session "plasma.desktop"))))
  (operating-system-user-services %live-base-os))))
```

### 错误 4：`xorg-server 需要 elogind`

见 1.2。加 `(service elogind-service-type)` 解决。

## 3. 验证路径（端到端）

```bash
cd ~/Projects/Config/Guix-configs

# 1) 括号平衡（block 级，秒级）
blue check 2>&1 | tail -3

# 2) 手动复现构建，抓 guix 真实报错（%guix 封装会吞 backtrace）
rm -f tmp/live-iso.scm
guix time-machine --channels=source/channel.lock -- shell emacs-minimal -- emacs --quick --batch -l org \
  --eval "(require 'ob-tangle)" --eval "(org-babel-tangle-file \"source/config.org\")"
guix time-machine --channels=source/channel.lock -- repl -- \
  tools/build-image.scm dist/jeans-desktop-$(date +%Y%m%d).x86_64-linux.iso \
  tmp/live-iso.scm --image-type=iso9660 2>&1 | tee /tmp/iso-kde-build.log

# 3) 正式后台构建（30+ 分钟，background=true + notify）
blue build-iso desktop

# 4) 校验
file dist/jeans-desktop-*.iso    # 应显示 'GUIX_IMAGE' (bootable)
sha256sum dist/jeans-desktop-*.iso
```

## 4. 已知遗留（非阻塞，另立项）

- **Panther channel 公钥 bug**：`guix-substitutes` 块里 Panther 段误用了 `guix-moe` 的 service 名（`'guix-moe-substitutes`）和公钥（`guix-moe.pub`），应改为 `'panther-substitutes` + `panther.pub`。不影响离线构建（4 套镜像公钥已注入 ISO），但联网拉 Panther substitute 时会鉴权失败。本次未修（patch 因"3 个匹配"反复失败，且非阻塞）。
- **`%images` 仍列 `("desktop" "minimal")`**：minimal 变体共用同一份带桌面的 `live-installation-os`，与"纯 CLI fallback"语义不符（历史遗留，见 `iso-build-debug.md` 5）。

## 5. 离线查 guix 源码的范式（KDE 字段验证用）

本环境 `web_extract` 对 `guix.gnu.org` 报 "Blocked: URL targets a private or internal network address"。直接 grep 本地锁定的 guix 源码（commit-exact，比 curl savannah 稳）：

```bash
COMMIT=$(grep -m1 commit source/channel.lock | sed 's/.*commit "\(.*\)".*/\1/')
SD=$(ls -d /gnu/store/*${COMMIT}*/gnu/services/sddm.scm 2>/dev/null | head -1)
# 若上面为空（commit 字面未命中），直接用现成的 guix-system-source：
SD=/gnu/store/*-guix-system-source/gnu/services/sddm.scm
grep -nE "define-configuration <sddm-configuration|\(display-server|auto-login-user|auto-login-session" "$SD"
```
