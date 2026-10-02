<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# ISO 自主打包 — 一条命令打出 Live 救援镜像

`blue build-iso` 基于 `source/config.org` 的 `* Live ISO` 章节打出 Live ISO，产物落到 `dist/jeans-<variant>-<YYYYMMDD>.<arch>.iso`，定位是救砖 + 装机双用途的救援盘。本文档只讲功能模型与用法；实施细节（全部 use-modules、块代码、修正记录）都在 `source/config.org` 同章节的头部注释里。

## 前置

在仓库根运行 `blue build-iso`；构建耗时 30+ 分钟（实测）。改 OS 定义前先读 `source/config.org` 的 Live ISO 章节顶部注释——详细错误码表与决策矩阵都在那里。

## 操作

### 1. 管线模型

`source/config.org`（Live ISO 章节）→ tangle → `tmp/live-iso-<variant>.scm` → `guix repl -- tools/build-image.scm`（经 `guix time-machine` 锁 `source/channel.lock`）→ `guix system image --image-type=iso9660` → `dist/jeans-<variant>-<YYYYMMDD>.<arch>.iso`。

管线自写代码不超过 50 行，其余都是 Guix core 与 BLUE build system 的标准件：

| 层 | 由谁负责 | 本仓库做的事 |
| --- | --- | --- |
| iso9660 / EFI / MBR | Guix core 的 `--image-type=iso9660` | 不碰 |
| installation-os 基底 | Guix core `(gnu system install)` 的 `make-installation-os` | 继承并定制 |
| 非自由内核 / 固件 | nonguix 的 `linux` + `linux-firmware` | 接入 |
| OS 定义 | 本仓库 | `source/config.org` 的 Live ISO 章节 |
| 构建编排 | BLUE build system | `build-iso` 命令（`blueprint.scm`） |
| 产物落地 | 本仓库 | `tools/build-image.scm` |

### 2. 构建

```bash
blue build-iso              # 构建 %images 列出的全部变体
blue build-iso desktop      # 只构建 XFCE 镜像（主目标）
blue build-iso minimal      # 只构建 minimal 镜像（纯 CLI fallback）
```

变体表是 `blueprint.scm` 的 `%images`（`("desktop" "minimal")`，顺序即构建顺序：主目标在前、fallback 在后），文件名前缀 `jeans` 也是 `blueprint.scm` 里定的。带参只构建匹配的变体，不带参构建全部。

### 3. 产物内容

两个变体共用：live/live 与 root/live 固定口令（救援盘需要确定性的 sudo/ssh 口令），shell 均为 fish；nonguix `linux` + `linux-firmware` 内核（基底默认的 `modprobe.blacklist=radeon,amdgpu` 已删，否则 AMD 显卡无 KMS、Wayland 桌面起不来）；4 套 substitute 镜像（guix-moe、nonguix、panther、sjtug，公钥内嵌为 plain-file，不依赖运行时联网拉公钥）；`/etc/guix/channels.scm` 预置 guix + nonguix；`rescue-chroot.sh` 与 `emergency-blue.sh` 经 `live-rescue-tools` 包装进 PATH；`emacs-minimal` 内嵌供 tangle；仓库快照在 `~/Guix-configs`（剔除 `.git`/`dist`/`tmp`，只读，用前 `cp -r` 一份可写副本）。

- **desktop**：`xfce-desktop-service-type` + `labwc`（Wayland）+ `greetd`（vt7 自动登录 live，登出后 default-session 自动回桌面）；删掉 tty1 的 kmscon 安装器直进桌面；网络走 NetworkManager（nm-applet 托盘、`nmtui` 亦可）。
- **minimal**：保留 tty1 的 TUI 安装器（kmscon）与 connman（TUI 安装器的网络步骤依赖它）；`issue` 印救援盘速查。
- **基底默认 tty**：tty2 是文档服务，tty3-6 是 root 自动登录的 mingetty。

### 4. 烧盘与验证

```bash
# 烧 U 盘
dd if=dist/jeans-desktop-<YYYYMMDD>.x86_64-linux.iso of=/dev/sdX bs=4M status=progress conv=fsync

# QEMU 验证
qemu-system-x86_64 -m 4G -enable-kvm -cdrom dist/jeans-desktop-*.iso

# sha256 校验
sha256sum dist/jeans-desktop-*.iso
```

## 关键约束

下列几条是最致命的，`blue check` 全都抓不到，只能靠真跑构建暴露。

- **tangle 目标绝对不能复用 `tmp/config.scm`**：每个变体各自 tangle 到 `tmp/live-iso-<variant>.scm`。误用会让 ISO 定义污染主机配置，`blue rebuild` 随即崩在 `%system` 未定义或多处重复定义上。验证：`tail tmp/live-iso-desktop.scm` 末行应是 `%live-desktop-os`（裸值），`grep -c 'live-desktop-os' tmp/config.scm` 应为 0。
- **`<<live-common>>` 只在 live 变体块内展开**：它是 noweb 片段、不独立 tangle；被主 `main` 块引用会把 ISO 内容混进 `tmp/config.scm`。验证：`grep -E 'live-(common|installation)' tmp/config.scm` 应为空。
- **`<<guix-substitutes>>` 展开后本身就是一个 service 列表**：在 `services` 里必须用 `append` 拍平，不能当 `cons*` 的单个元素——否则整个列表被当成一个 service 嵌进去，guix 报 `services` 字段类型不对。`blue check` 只看块内括号平衡，抓不到这类 list-in-list 类型错。
- **builder 里要用 `(guix build utils)` 必须 `with-imported-modules`**：trivial-build-system 的 builder 默认不导入该模块，直接在 `#~(begin ...)` 里 `use-modules` 会在 drv 编译阶段报 `no code for module (guix build utils)`；`with-imported-modules` 多包一层，结尾要补一个右括号。
- **删 kmscon 必须配对删 console-font**：`make-installation-os` 的 kmscon 在 tty1 且 `login-program` 是安装器，而 kmscon 是 `term-tty1` 的唯一提供者；`console-font-service-type` 对每个 tty 都有 `term-<tty>` 依赖。只删 kmscon 会让 `console-font-tty1` 找不到提供者。console-font 只设 TTY 字体，删了无副作用。
- **删 connman 必须同时显式加 NetworkManager**：`make-installation-os` 默认网络栈是 connman，它提供 shepherd 的 `networking`，而 `openssh` 的 `ssh-daemon` 依赖 `networking`——只删不补会让 ssh-daemon 起不来。`xfce-desktop-service-type` 只是 polkit/pam/profile 的小扩展，不含 `%desktop-services`，NetworkManager 不会自动来。
- **live / root 的 shell 必须指向 ISO 包列表里已安装的包**（现为 fish）。改成列表里没有的包会导致登录即失败。
- **`blue --dry-run build-iso` 仍会真跑 tangle**：`--dry-run` 短路的是 `%run`（镜像构建等子进程），但 `org-babel-tangle-file` 必须真跑，否则 dry-run 拿不到 `tmp/live-iso-<variant>.scm` 产物。
- **`make-installation-os` 来自 `(gnu system install)`**（guix `9e068cc` 的 `gnu/system/install.scm:693`），不是 rosenthal；live 变体块必须 `(use-modules (gnu system install))`。别凭印象改 use-modules 列表。
- **只装 mihomo 包，不引 service / config / tun**：ISO 内手动启，装好后由 `blue rebuild` 重建。
- **ISO 复用 `source/channel.lock`**：本仓库只有一份主机配置，ISO 用的是它的子集。代价是镜像 closure 含 bluebox / sops-guix 等主机专用频道的依赖（实测未导致问题）。

## 排障

| 症状 | 原因 / 处理 |
| --- | --- |
| `blue build-iso` 报 `%system` 未定义或多处重复定义 | tangle 目标误用 `tmp/config.scm`，见「关键约束」第一条 |
| `services` 字段类型不对 | `<<guix-substitutes>>` 被当 `cons*` 元素，改用 `append` 拍平 |
| `no code for module (guix build utils)`（drv 编译失败） | builder 缺 `with-imported-modules` |
| 服务依赖 `term-tty1` 无提供者 | 删 kmscon 时漏删 console-font |
| 服务依赖 `networking` 无提供者 | 删 connman 时没显式加 NetworkManager |
| `no code for module (gnu packages X)` | 删该 use-modules，改走 `specifications->packages` |
| 字段名或值类型报错 | 查 Guix 手册对应 service |
| `blue check` 报多余括号 | `blue block-show <块名>` 定位块名，`git diff` 找行 |
| `guix time-machine: failed to authenticate` | `source/channel.lock` 频道公钥过期，跑 `blue update` 重生 |
| QEMU 启动但 X 起不来 | 进 tty 查日志，X 日志在 `~/.local/share/xorg/` |

接手时真撞错的顺序：先 grep `source/config.org` 的 Live ISO 章节顶部注释与该节块代码，再查 Guix 手册对应 service / package 文档，最后才看上游 issue。

## 相关

- `source/config.org` 的 `* Live ISO` 章节——实施细节、全部 use-modules、块代码
- `blueprint.scm` 的 `build-iso` 命令——`%images`、变体过滤、文件名拼合
- [scripts/blue-helpers.md](scripts/blue-helpers.md) §build-image.scm——`tools/build-image.scm` 的调用契约
- [rescue-chroot.md](rescue-chroot.md) / [emergency-blue.md](emergency-blue.md)——ISO 里预装的两个救援脚本