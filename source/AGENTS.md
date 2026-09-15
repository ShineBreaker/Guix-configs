# source/ — Guix 配置源目录

`source/config.org` 是唯一的 Org 配置源（请勿新建第二个），通过 Org Babel tangle 生成 `tmp/config.scm`。执行 `blue rebuild` 可完成 tangle、括号平衡检查与系统 reconfigure，单次操作即可同时应用 `operating-system` 与内嵌的 `guix-home-service`。

`config.org` 正文仅保留结构标签与简短提示，**完整的技术细节与架构决策记录在此文档中**（内核定制另见 `files/kernel/AGENTS.md`）。

<!-- structor:begin depth=1 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
source/
├── files/
├── nix/
├── channel.lock
├── channel.scm
├── config.org
├── information.scm
└── manifest.scm
```

<!-- /structor -->

## 职责边界与核心原则

- **System 层（`operating-system`）**：负责底层基础设施，包括引导器（Limine / Rosenthal）、文件系统（LUKS + Btrfs + tmpfs 根目录）、自编译 CachyOS LTS 内核、8 个系统级服务块及用户账户。全局配置变量统一维护在 `information.scm`。
- **Home 层（`home-environment`）**：负责用户态环境，包括 4 个包清单（desktop/terminal/devtools/user）、自定义包与 Hermes 运行时、dotfiles 部署、用户服务、环境变量及字体配置。
- **最小化原则**：系统层保持精简（提升初始安装与迭代效率）。能通过 Home 层解决的配置不上浮到 System 层；优先修改 `dotfiles/immutable/<app>/`，仅在需要 Guix 介入时修改 `config.org`。
- **两套部署路径互不干扰**：
  1. `source/files/`：使用 `home-files-service-type` 部署，支持 `$$bin/foo$$` 路径注入占位符。
  2. `dotfiles/immutable/`：使用 Guix Home stow 布局部署到 store 只读副本并软链到 `$HOME`，修改后须 `blue home` 生效。
- **新增配置流程**：在 `dotfiles/immutable/<app>/` 新建目录 → 在 `config.org` 加入对应包列表 → 在 `dotfile-services` 的 `packages` 列表中登记。若是 Emacs 插件包，须同步更新 `emacs-services` 的 `specifications->manifest`。

## 修改 config.org 前必读

### 文件结构分区

1. 导览与维护操作（可执行 Babel 块）
2. 模块导入与全局骨架（`main` 块是唯一总装配表，包含所有叶子块引用）
3. 系统配置（Bootloader / FileSystems / Kernel / Packages / Services / Users）
4. 用户配置（Packages / Services / Environment / Fonts）
5. Live ISO 构建声明

各二级标题均带有 `CUSTOM_ID`，正文与导览之间通过 `[[#id]]` 互相链接。

### 块级编辑操作

修改单一 `#+NAME:` 块时，可使用块级工具避免读取完整大文件：

```bash
blue block-show <name>                 # 提取指定块到 tmp/block-<name>.scm
blue block-replace <name> <body-file>  # 原子写回并进行 Scheme 括号校验
```

> **注意**：提取出的 body 前两行为语言和 noweb 标记，第 3 行起为代码内容。对于高耦合的大型块（如 `emacs-services`），建议直接阅读上下文；如遇异常可用 `git checkout source/config.org` 恢复。

### Org Noweb 机制

- 代码块命名：`#+NAME: <block-name>`
- 引用其他块：`<<block-name>>`（此为 Org 模板展开功能，非 Scheme 语法）
- 功能开关：注释掉 `<<ref>>` 引用即可在装配中停用该功能块。

## 验证流程（修改后必做）

```bash
blue --dry-run rebuild     # 运行完整构建验证（真执行 tangle 与语法检查，不写入系统）
blue check                 # 快速逐块检查括号平衡，直接定位到出错块名
blue home                  # 仅构建并切换 Home 层（含 dotfiles），无需 sudo 权限，供 agent 调试
```

## 全局变量与文件系统（`information.scm`）

`config.org` 在头部通过 `(load "../source/information.scm")` 引入全局变量。

- **存储拓扑**：根目录 `/` 为 tmpfs（每次重启自动清空）；持久化数据存放于 Btrfs 子卷并挂载到 `/var/lib`、`/gnu`、`/boot` 等目录；用户主目录数据挂载自 `/data` 分区。
- **持久化登记**：若新增需持久化的目录，必须同时在 `information.scm` 的 `%data-dirs` 与 `%btrfs-subvolumes` 中声明。
- **休眠机制**：Guile initrd 暂不支持从加密 swap 恢复休眠镜像，故当前配置选择支持休眠，休眠镜像会将内存数据写入指定 swap 分区。
- `fixed-machine-id` 生成算法定义于 `information.scm`。

## files/ 模板系统与路径注入

`source/files/` 存放需要**动态注入绝对路径**的模板文件，由 `home-files-service-type` 部署。模板中的 `$$bin/foo$$` 占位符会在构建期被替换为对应 Guix 包在 `/gnu/store` 中的绝对路径。无需路径注入的常规配置文件请直接放入 `dotfiles/immutable/<app>/`。

## 系统层机制注记

- **内核模块与网络协议栈**：
  - 加载 `ip_tables` / `iptable_nat` 作为兼容层，供 Libvirt 与 Podman 网络后端使用，与 nftables 主规则集并存。
  - `zswap.compressor=zstd`：由于内核 cmdline 阶段早于用户态 modprobe，zswap 在启动时会先使用内置算法，待 zstd 模块加载后由 `zswap-zstd` 服务在运行时切换。
  - `sysctl` 调优：设置 `default_qdisc=fq` 保障 BBR 的 pacing 正常工作；设置 `tcp_rmem` / `tcp_wmem` 缓冲三元组避免高 BDP 跨国链路受限；设置 `dirty_writeback_centisecs=1500` 减少空闲时 SSD 唤醒。
- **启动与清理服务**：
  - `/tmp` 目录挂载在持久 Btrfs 子卷，通过 `/run/cleanup-tmp-done` 标记确保单次开机仅在首次清理；`cleanup-/tmp-prereq` 将其前置注入到 `user-processes`，确保所有用户服务启动前 `/tmp` 已就绪。
  - Udev 动态规则必须使用 `file->udev-rule` 包装成标准目录派生结构。
  - AC 电源联动：捕获 Udev `power_supply` 事件自动调节 PPD 档位与 WiFi 省电策略，开机时由 `ac-power-init` 根据当前电源状态初始化执行。
- **桌面与会话**：
  - TTY 分配：TTY1 预留给内核消息，TTY2-6 使用 kmscon，TTY7 运行 Greetd 图形登录。
  - Elogind 默认忽略硬件休眠键，由 `50-hibernate.rules` 授权本地活跃用户。

## 网络：nftables 与热点 AP

- **nftables 防火墙（接口信任模型）**：规则集开机时由 `nftables-service-type` 全局加载，input/forward 默认 drop，仅放行 DHCP、ICMP、established/related 与 Tailscale WireGuard 端口（udp 41641）。`trusted_ifaces` 集合内的接口（`uap0` 热点、`virbr0` 虚拟机网桥、`tailscale0`）整接口全端口放行。NetworkManager dispatcher 仅动态增删该集合元素（可信 WiFi 加入 `wlp0s20f3`），绝不执行 `flush ruleset`。
- **WiFi 信任白名单**：以 NM Profile 名（`CONNECTION_ID`，非 SSID）为准，存储于加密文件 `wifi-trust.age` 中。Dispatcher 脚本在内存管道中解密比对，不落盘明文。
- **热点 AP（2026-09-13 起手动启停）**：hostapd 直管 `uap0`（type `__ap`，Udev `ENV{NM_UNMANAGED}="1"` 隔离，规则序号须 >75），开机不自启，由 fish 命令 `hotspot on/off/status`（内部 `sudo herd`）控制。安全不变式：
  1. STA 与 AP 并发共享单一 radio（#channels<=1），AP beacon 会把 radio 锁死在其信道——执行体启动时内联探测：STA 已连接则跟随其信道，未连接用 2.4G ch6（self-managed world regdom 下 5G 全带 no IR，无 STA 关联起 5G 会被内核 START_AP 拒绝）。热点开启期间 STA 无法漫游到其他信道，需先 `hotspot off`。
  2. hostapd 配置必须带 `hw_mode`，且与信道段配对（1-14 → g，其余 → a），否则报 "Could not determine operating frequency"。
  3. `hotspot-ap` 不设 respawn，进程退出后 shepherd 标记 disabled；`hotspot on` 先 `herd enable` 再 `start`（幂等）。
  - 热点凭据：存放于 `wifi-hotspot.age` 密文中。生成和更新由用户手动执行，Agent 禁止读取或输出其明文。

## 用户层与自定义包要点

- **D-Bus 总线**：声明空 `dbus` Home 服务承接依赖，避免与 Niri 启动时的 `dbus-run-session` 会话总线产生冲突。
- **Emacs 服务**：以 `emacs --fg-daemon` 模式常驻运行，相关软件包隔离在 Emacs 专属 profile 中。
- **Hermes 运行时**：FHS 基础依赖纳入 `home-packages` 维持 GC Root；系统冲突包（cairo、glib、gtk+ 等）写入独立的 manifest 部署到 Hermes 专属数据目录。
- **自定义包（custom-packages）规则**：顶层 `define` 代码块经 Noweb 拼入 `main` 顶部；`custom-packages-list` 仅放置包列表表达式（被 `(append ...)` 引用）。
- **指纹识别栈**：
  - Goodix `27c6:689a` 需要 libfprint ≥1.94.9 的 `goodixmoc` 驱动支持，因此定制了 libfprint 与 fprintd 变体包。
  - PAM 层面将 `pam_fprintd.so` 作为 sufficient 规则插入在 `pam_unix` 之前，实现指纹优先、密码兜底。

## Live ISO 镜像构建

- 通过 `blue build-iso` 生成 `tmp/live-iso.scm`，再由 `tools/build-image.scm` 构建 ISO 镜像。
- **隔离要求**：ISO 的 tangle 目标必须是独立的 `tmp/live-iso.scm`，绝对不能复用 `tmp/config.scm`；ISO 专用的模块引用必须内联在 `live-installation-os` 块内部，切勿并入主模块列表。

## 频道管理

- `channel.scm`：声明 Guix 官方频道及第三方扩展频道分支，可手动编辑。
- `channel.lock`：由 `blue update` 命令根据当前锁定的 Commit 自动生成，**禁止手动编辑**。
- 更新流程：编辑 `channel.scm` → `blue pull` → `blue update`。

## 操作红线（Agent 禁区）

<critical>
1. 禁止 Agent 自行运行 `blue rebuild` 或 `guix system reconfigure`（需 sudo 权限），调试验证仅使用 `blue home`，完成后提醒用户手动 rebuild。
2. 禁止手动编辑 `tmp/` 下的中间生成物和 `source/channel.lock`。
3. 遵循修改边界：优先修改 `dotfiles/`，仅在必要时修改 `config.org`；能用 Home 层解决的不上浮 System 层。
4. 修改 `config.org` 后必须运行 `blue check` 或 `blue --dry-run rebuild` 验证语法。
</critical>
