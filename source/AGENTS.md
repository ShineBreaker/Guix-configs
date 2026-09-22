# source/ — Guix 配置源目录

`source/config.org` 是唯一的 Org 配置源（请勿新建第二个），通过 Org Babel tangle 生成 `tmp/config.scm`。执行 `blue rebuild` 可完成 tangle、括号平衡检查与系统 reconfigure，单次操作即可同时应用 `operating-system` 与内嵌的 `guix-home-service`。

`config.org` 正文承载**面向入门读者的就近解释**（块旁说明语法、数据形态与陷阱，2026-09-18 起明确此分工），**架构决策与运维知识集中在本文件**（内核定制另见 `files/kernel/AGENTS.md`）。

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

- **System 层（`operating-system`）**：负责底层基础设施，包括引导器（Limine / Rosenthal）、文件系统（LUKS + Btrfs + tmpfs 根目录）、自编译 CachyOS LTS 内核、系统服务群与用户账户。全局配置变量统一维护在 `information.scm`。
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
- 功能开关：注释掉 `<<ref>>` 引用即可在装配中停用该功能块（因此被注释的 `<<ref>>` 是刻意保留的开关，勿当死代码清理）。
- shepherd 服务请复用 `service-helpers` 块的简写构造（`home-daemon-service` 常驻用户进程 / `root-daemon-service` 常驻系统进程 / `root-one-shot-service` 开机一次），它们统一了日志落点与环境约定；`%flatpak-update-script` 供 system/user 两侧 flatpak 定时更新共用。

### 代码风格与可读性原则

目标读者是**刚入门 Guile/Guix/org 的用户**，可读性优先于简洁或「聪明」的写法。

抽象判定：

- 只有 **≥3 个调用点且确实消除重复**的包装才值得保留（如服务构造三件套、`computed-substitution-with-inputs` 的占位符注入）；单用途包装（1–2 个调用点）直接内联平凡写法，不为「将来可能复用」提前抽象。
- 程序化生成（`map` / `append-map` + 数据表）只用于消除真实重复或反转数据方向；若只是展开几条固定数据，平铺字面量。

平凡写法优先：

- 拼接少量已知值用普通 `list` / `string-append`，不用 quasiquote（`` `((,a ,b)) `` 这类结构写 `(list (list a b))`）。
- 数字比较用 `=`（必要时先判 `number?`），不用 `eq?`。
- 不引入点参数 + `apply`、双层闭包等技巧表达一次性简单逻辑；常量字符串不拆成多段再拼接；同一字面量（如 UUID）多处出现时收敛为单一绑定。

惯用法与陷阱（勿「顺手简化」，均有实证）：

- etc / 配置扩展的反引号点对 `` `("路径" ,文件) `` 是 Guix 生态通用格式，保留写法不换 `cons`，缺解释时在块旁补文档。
- gexp 内 `'#$list` 的外层 `'` **不可去**：quote 让列表序列化为脚本里的字面量数据，去掉会把列表当函数调用（第一个元素成为运算符）而构建失败。
- `#~(string-append (getenv "HOME") …)` 的 `#~` **不可去**：去掉会在配置求值期（root 执行重建时）取到 `/root` 并烘焙进服务闭包。
- shepherd one-shot 服务**不需要**传 `#:stop` / `#:respawn?`：两者对 one-shot 均惰性，且 stop 回调返回 `#f` 才表示「已停止」（返回 `#t` 语义反向，`herd stop` 会报停止失败）。

Org 文档写法：

- 面向入门者的解释写在块旁 org 正文（不进 tangle 产物）；代码块内只留短分类标签与关键警示（会进产物）。
- 等宽标记 `=code=` 两侧必须是 ASCII 空白或 ASCII 标点——紧贴中文标点/汉字会**静默失效**并引发相邻标记误配对，写作时「标记外加空格」。
- 解释只写可确证的行为（可从代码、数据表或上游源码验证），不臆测历史原因；正文全角标点、代码用 `=...=` 标记。

## 验证流程（修改后必做）

```bash
blue --dry-run rebuild     # 运行完整构建验证（真执行 tangle 与语法检查，不写入系统）
blue check                 # 快速逐块检查括号平衡，直接定位到出错块名
blue home                  # 仅构建并切换 Home 层（含 dotfiles），无需 sudo 权限，供 agent 调试
```

> **语义改动的补充验证**：`--dry-run` 会把 system build 验证也短路。涉及结构改写、变量替换等语义变化时，另跑 `guix time-machine --channels=source/channel.lock -- system build tmp/config.scm --dry-run` 做实际求值；并可把 `git show HEAD:source/config.org` tangle 到隔离目录，与新产物逐块 diff 核对每处差异均为预期改动。

## 全局变量与文件系统（`information.scm`）

`config.org` 在头部通过 `(load "../source/information.scm")` 引入全局变量。

- **存储拓扑**：根目录 `/` 为 tmpfs（每次重启自动清空）；持久化数据存放于 Btrfs 子卷并挂载到 `/var/lib`、`/gnu`、`/boot` 等目录；用户主目录数据挂载自 `/data` 分区。
- **持久化登记**：若新增需持久化的目录，必须同时在 `information.scm` 的 `%data-dirs` 与 `%btrfs-subvolumes` 中声明。
- **休眠机制**：因 Guile initrd 无法从加密 swap 恢复休眠镜像，swap 采用明文独立分区。休眠镜像写入该分区；恢复链路由 `resume=UUID=` 内核参数与 `resume-device` 服务（按 UUID 反查设备号写入 `/sys/power/resume`）衔接。
- `fixed-machine-id` 生成算法定义于 `information.scm`。

## files/ 模板系统与路径注入

`source/files/` 存放需要**动态注入绝对路径**的模板文件，由 `home-files-service-type` 部署。模板中的 `$$bin/foo$$` 占位符会在构建期被替换为对应 Guix 包在 `/gnu/store` 中的绝对路径。无需路径注入的常规配置文件请直接放入 `dotfiles/immutable/<app>/`。

该目录另含两个自包含子目录：`kernel/`（定制内核定义，见其 AGENTS.md）与 `livecd/`（Live ISO 载荷，经 `local-file` 打进镜像）。

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

## 网络与防火墙

- **nftables 防火墙（接口信任模型）**：规则集开机时由 `nftables-service-type` 全局加载，input/forward 默认 drop，仅放行 DHCP、ICMP、established/related 与 Tailscale WireGuard 端口（udp 41641）。`trusted_ifaces` 集合内的接口（`virbr0` 虚拟机网桥、`tailscale0`）整接口全端口放行。NetworkManager dispatcher 仅动态增删该集合元素（可信 WiFi 加入发起连接的无线接口），绝不执行 `flush ruleset`。
- **WiFi 信任白名单**：以 NM Profile 名（`CONNECTION_ID`，非 SSID）为准，存储于加密文件 `wifi-trust.age` 中。Dispatcher 脚本在内存管道中解密比对，不落盘明文；私钥缺失时仅按不可信处理，不阻断联网。脚本经 activation 拷入 `/etc/NetworkManager/dispatcher.d/`（该目录是持久挂载点，规则文件随系统代原子切换）。
- **WiFi 省电策略（`nm-powersave-conf`）**：目标是连接时恒不省电（低延迟、远程操控优先）。NM 每次连接都把省电重置为开启，曾尝试用 dispatcher 在 up 事件补救但被 NM 默认行为覆盖、不可靠，故改为在 NM `[connection]` 段写默认 `wifi.powersave=2`；拔电时由 udev ac-power 规则切回省电。注意 `[connection]` 段枚举与 profile 属性不同：0=NM默认 1=ignore 2=disable省电 3=enable省电。
- **OpenSSH**：显式声明 `permit-root-login 'prohibit-password`——root 锁定密码、仅允许密钥登录，防上游默认漂移。
- **mihomo-daemon**：`-d` 把数据目录（geodata/cache/UI/proxies）归位到 `/var/lib/mihomo`，随 @data 子卷持久化（此前 root 环境下默认写 `/.config/mihomo`）。启动经 `mihomo-run` 包装：解密 `mihomo-subscriptions.age` 后用 envsubst 渲染模板到 `/var/lib/mihomo/config.yaml` 再 exec；解密失败降级为空订阅启动（直连仍可用），不触发 respawn 风暴。模板侧与换订阅操作见 `dotfiles/immutable/system/AGENTS.md`。

## 用户层与自定义包要点

- **D-Bus 总线**：声明空 `dbus` Home 服务承接依赖，避免与 Niri 启动时的 `dbus-run-session` 会话总线产生冲突。
- **Emacs 服务**：以 `emacs --fg-daemon` 模式常驻运行，相关软件包隔离在 Emacs 专属 profile 中。
- **Hermes 运行时**：FHS 基础依赖纳入 `home-packages` 维持 GC Root；系统冲突包（cairo、glib、gtk+ 等）写入独立的 manifest 部署到 Hermes 专属数据目录。
- **自定义包（custom-packages）规则**：顶层 `define` 代码块经 Noweb 拼入 `main` 顶部；`custom-packages-list` 仅放置包列表表达式（被 `(append ...)` 引用）。
- **指纹识别栈**：
  - Goodix `27c6:689a` 需要 libfprint ≥1.94.9 的 `goodixmoc` 驱动支持，因此定制了 libfprint 与 fprintd 变体包。
  - PAM 层面将 `pam_fprintd.so` 作为 sufficient 规则插入在 `pam_unix` 之前，实现指纹优先、密码兜底。

## Live ISO 镜像构建

- 通过 `blue build-iso` 生成 `tmp/live-iso-<variant>.scm`（desktop / minimal 两个变体），再由 `tools/build-image.scm` 构建 ISO 镜像。
- **隔离要求**：ISO 的 tangle 目标必须是独立的 `tmp/live-iso-<variant>.scm`，绝对不能复用 `tmp/config.scm`；ISO 专用的模块引用内联在各变体块内部，共享部分走 `<<live-common>>` noweb 片段（不独立 tangle）。

## 频道管理

- `channel.scm`：声明 Guix 官方频道及第三方扩展频道分支，可手动编辑。
- `channel.lock`：由 `blue update` 命令根据当前锁定的 Commit 自动生成，**禁止手动编辑**。
- 更新流程：编辑 `channel.scm` → `blue update`（按新声明重建并提交 `channel.lock`）→ `blue pull`（按锁定频道执行 `guix pull`）。`blue pull` 只认 `channel.lock`，不会读 `channel.scm` 的未锁定改动，顺序不可颠倒。

## 操作红线（Agent 禁区）

<critical>
1. 禁止 Agent 自行运行 `blue rebuild` 或 `guix system reconfigure`（需 sudo 权限），调试验证仅使用 `blue home`，完成后提醒用户手动 rebuild。
2. 禁止手动编辑 `tmp/` 下的中间生成物和 `source/channel.lock`。
3. 遵循修改边界：优先修改 `dotfiles/`，仅在必要时修改 `config.org`；能用 Home 层解决的不上浮 System 层。
4. 修改 `config.org` 后必须运行 `blue check` 或 `blue --dry-run rebuild` 验证语法。
</critical>
