# source/ — Guix 配置源目录

`source/config.org` 是唯一的 Org 配置源（不要新建第二个），经 Org Babel tangle 生成 `tmp/config.scm`，一次 reconfigure 同时应用 `operating-system` 与内嵌的 `home-environment`。命令清单以 `blue list` 为准，单命令详情见 `blue help <命令>`。

`config.org` 正文承载**面向入门读者的就近解释**（块旁说明语法、数据形态与陷阱），**架构决策与运维知识集中在本文件**。本篇不讲 `blue` 与脚本的旗标机制（见 `docs/scripts/blueprint.md`）；仓库级硬约束见根 `AGENTS.md`。

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

## 职责边界

- **System 层（`operating-system`）**：引导器（Limine / Rosenthal）、文件系统（LUKS + Btrfs + tmpfs 根目录）、自编译 CachyOS LTS 内核、系统服务群与用户账户。
- **Home 层（`home-environment`）**：4 个包清单（desktop / terminal / devtools / user）、自定义包与 Hermes 运行时、dotfiles 部署、用户服务、环境变量与字体。
- **最小化原则**：系统层保持精简；Home 层能解决的不上浮 System 层。优先改 `dotfiles/immutable/<app>/`，仅在需要 Guix 介入时才动 `config.org`。
- **两套部署路径互不干扰**：`source/files/` 走 `home-files-service-type`（支持 `$$bin/foo$$` 路径注入占位符）；`dotfiles/immutable/` 走 Guix Home stow 布局（改源后须 `blue home` 生效）。
- **新增配置流程**：在 `dotfiles/immutable/<app>/` 建目录 → 在 `config.org` 的对应包清单里加入 → 在 `dotfile-services` 的 `packages` 列表登记。Emacs 插件包另须登记 `emacs-packages` 块。

`config.org` 顶层章节顺序即阅读顺序：`导览` / `维护操作` / `模块导入` / `全局 define` / `配置文件骨架` / `系统配置` / `用户配置` / `Live ISO`。系统与用户配置各自拆成 `** Bootloader | FileSystems | Kernel | Packages | Services | Users` 这类二级章节，每个二级章节带一个 `CUSTOM_ID`，`导览` 用 `[[#id]]` 索引它们。

## Org 写法与块级编辑

### Noweb 机制

- 块命名 `#+NAME: <block-name>`，引用其他块写 `<<block-name>>`（Org 模板展开，非 Scheme 语法）。
- `main` 块是**唯一总装配表**：所有叶子块靠 `<<ref>>` 挂进 `%home` 与 `%system` 两个表单。注释掉 `<<ref>>` 即停用该功能块——被注释的 `<<ref>>` 是刻意保留的开关，**不是死代码，不要清理**。
- **shepherd 服务复用四个 helper 块**：`home-daemon-service-helpers`（常驻用户进程）、`root-daemon-service-helpers`（常驻系统进程）、`root-one-shot-service-helpers`（开机一次），三者统一了日志落点与环境约定；`flatpak-service-helpers` 的 `%flatpak-update-script` 供 system / user 两侧 flatpak 定时更新共用。

### 块级编辑操作

改单个 `#+NAME:` 块时不必读完整大文件，用块级工具：

```bash
blue block-show <name>                 # 提取到 tmp/block-<name>.scm 并打印路径
blue block-replace <name> <body-file>  # 原子写回 config.org，scheme 块自动 tangle + 括号校验
```

- 块名只允许字母 / 数字 / `-` / `_`（拼进输出路径并交给 elisp，`../` 与空白会构成路径穿越 / 匹配注入面）。
- 提取出的 body **前两行是语言与 noweb 标记，第 3 行起才是代码内容**。
- `block-replace` 是真实写 `source/config.org` 的操作，**dry-run 模式下直接报错禁用**；写回是原子的，失败时用 `git checkout source/config.org` 还原。
- 高耦合的大型块（如 `emacs-packages`、`home-packages`）建议直接读上下文，块工具的价值在独立小块。

### Org 正文与内嵌脚本

- 面向入门者的解释写在块旁正文（不进 tangle 产物）；代码块内只留短分类标签与关键警示（会进产物）。
- 等宽标记 `=code=` 两侧必须是 ASCII 空白或 ASCII 标点——紧贴中文标点或汉字会**静默失效**并引发相邻标记误配对，一律「标记外加空格」。
- 只写可确证的行为（能从代码、数据表或上游源码验证），不臆测历史原因。
- **内嵌脚本块**（sh / fish / js 块，以及 `program-file` / `computed-file` / `mixed-text-file` / `render-script` 生成的脚本）必须有 `#+NAME:`，必要时加 `#+CAPTION:`；用途、调用方、失败语义与不变量写在块旁正文；新增命名脚本块时在 `docs/scripts/README.md` 的「config.org 内嵌脚本」表登记。

## 代码风格

目标读者是刚入门 Guile/Guix/org 的用户，可读性优先于「聪明」的写法。

- **抽象判定**：只有 ≥3 个调用点且确实消除重复的包装才值得保留；单用途包装直接内联平凡写法。程序化生成（`map` / `append-map` + 数据表）只用于消除真实重复或反转数据方向，否则平铺字面量。
- **平凡写法**：拼接少量已知值用普通 `list` / `string-append`，不用 quasiquote（`` `((,a ,b)) `` 写 `(list (list a b))`）；数字比较用 `=`（必要时先判 `number?`）不用 `eq?`；不用点参数 + `apply`、双层闭包表达一次性逻辑；同一字面量（如 UUID）多处出现时收敛为单一绑定。

### 惯用法与陷阱（勿「顺手简化」，均有实证）

- etc / 配置扩展的反引号点对 `` `("路径" ,文件) `` 是 Guix 生态通用格式，保留写法不换 `cons`。
- gexp 内 `'#$list` 的外层 `'` **不可去**：quote 让列表序列化为脚本里的字面量数据，去掉会把列表当函数调用（第一个元素成为运算符）而构建失败。
- `#~(string-append (getenv "HOME") …)` 的 `#~` **不可去**：去掉会在配置求值期（root 执行重建时）取到 `/root` 并烘焙进服务闭包。
- shepherd one-shot 服务**不需要**传 `#:stop` / `#:respawn?`：两者对 one-shot 均惰性，且 stop 回调返回 `#f` 才表示「已停止」（返回 `#t` 语义反向，`herd stop` 会报停止失败）。
- 非字面量路径必须用 `assume-source-relative-file-name` 标记，否则 `local-file` 退化成按 cwd 解析。

## 全局变量与文件系统（`information.scm`）

`config.org` 在头部通过 `(load "../source/information.scm")` 引入全局变量。

- **存储拓扑**：根目录 `/` 为 tmpfs（每次重启自动清空）；持久化数据放 Btrfs 子卷并挂载到 `/var/lib`、`/gnu`、`/boot`；用户主目录数据挂自 `/data` 分区。
- **持久化登记**：新增需持久化的目录，必须同时在 `information.scm` 的 `%data-dirs` 与 `%btrfs-subvolumes` 中声明。
- **休眠机制**：Guile initrd 无法从加密 swap 恢复休眠镜像，故 swap 采用明文独立分区。镜像写入该分区，恢复链路由 `resume=UUID=` 内核参数与 `resume-device-service`（按 UUID 反查 major:minor 写入 `/sys/power/resume`）衔接。
- `fixed-machine-id` 的生成算法（`generate-machine-id`）定义在 `information.scm`，由 `machine-id-service` 块写成 `/etc/machine-id`。

## files/ 模板系统

`source/files/` 存放需要**动态注入绝对路径**的模板文件，由 `home-files-service-type` 部署；模板里的 `$$bin/foo$$` 占位符在构建期替换为对应 Guix 包在 `/gnu/store` 中的绝对路径（配合 `computed-substitution-with-inputs`）。不需要路径注入的常规配置文件直接放 `dotfiles/immutable/<app>/`。

该目录另含两个自包含子目录：`kernel/`（定制内核定义，见 [files/kernel/AGENTS.md](files/kernel/AGENTS.md)）与 `livecd/`（Live ISO 载荷，经 `local-file` 打进镜像）。

## 系统层机制注记

- **内核与网络协议栈**：加载 `ip_tables` / `iptable_nat` 作为兼容层，供 Libvirt 与 Podman 网络后端使用，与 nftables 主规则集并存。`zswap.compressor=zstd` 在内核 cmdline 阶段早于用户态 modprobe，故启动先用内置算法，待 zstd 模块加载后由 `zswap-zstd` 服务在运行时切换。`sysctl` 侧设 `default_qdisc=fq` 保障 BBR pacing，设 `tcp_rmem` / `tcp_wmem` 缓冲三元组避免高 BDP 链路受限，设 `dirty_writeback_centisecs=1500` 减少空闲时 SSD 唤醒。
- **启动与清理服务**：`/tmp` 挂载在持久 Btrfs 子卷，用 `/run/cleanup-tmp-done` 标记保证单次开机只清一次；`cleanup-/tmp-prereq` 前置注入 `user-processes`，保证所有用户服务启动前 `/tmp` 已就绪。Udev 动态规则必须用 `file->udev-rule` 包装成标准目录派生结构。AC 电源联动捕获 Udev `power_supply` 事件自动调节 PPD 档位与 WiFi 省电策略，开机由 `ac-power-init` 按当前电源状态初始化。
- **桌面与会话**：TTY1 留给内核消息，TTY2-6 走 kmscon，TTY7 跑 Greetd 图形登录。Elogind 默认忽略硬件休眠键，由 `50-hibernate.rules` 授权本地活跃用户。

## 网络与防火墙

- **nftables（接口信任模型）**：规则集由 `nftables-service-type` 开机全局加载，input/forward 默认 drop，仅放行 DHCP、ICMP、established/related 与 Tailscale WireGuard 端口（udp 41641）。`trusted_ifaces` 集合内的接口（`virbr0` 虚拟机网桥、`tailscale0`）整接口全端口放行；NetworkManager dispatcher 只动态增删该集合元素（可信 WiFi 加入发起连接的无线接口），**绝不执行 `flush ruleset`**。
- **WiFi 信任白名单**：以 NM Profile 名（`CONNECTION_ID`，非 SSID）为准，存在加密文件 `wifi-trust.age` 中。Dispatcher 脚本在内存管道里解密比对、不落盘明文；私钥缺失时只按不可信处理，不阻断联网。脚本经 activation 装到 `/etc/NetworkManager/dispatcher.d/10-trusted-ssid`（该目录是持久挂载点，规则文件随系统代原子切换）。
- **WiFi 省电策略（`nm-powersave-conf`）**：目标是连接时恒不省电（低延迟、远程操控优先）。NM 每次连接都把省电重置为开启，用 dispatcher 在 up 事件补救会被 NM 默认行为覆盖，故改为在 NM `[connection]` 段写默认 `wifi.powersave=2`——activation 装到 `/etc/NetworkManager/conf.d/wifi-powersave.conf`，拔电时由 udev ac-power 规则切回省电（`/etc/NetworkManager/dispatcher.d/20-wifi-powersave`）。注意 `[connection]` 段枚举与 profile 属性不同：0=NM默认 1=ignore 2=disable省电 3=enable省电。
- **OpenSSH**：显式声明 `permit-root-login 'prohibit-password`——root 锁密码、仅密钥登录，防上游默认漂移。
- **mihomo-daemon**：`-d` 把数据目录（geodata / cache / UI / proxies）归位到 `/var/lib/mihomo`，随 @data 子卷持久化。启动经 `mihomo-run` 包装：解密 `mihomo-subscriptions.age` 后用 envsubst 渲染模板到 `/var/lib/mihomo/config.yaml` 再 exec；解密失败降级为空订阅启动（直连仍可用），不触发 respawn 风暴。模板侧与换订阅操作见 `dotfiles/immutable/system/AGENTS.md`。

## 用户层与自定义包

- **D-Bus 总线**：声明空 `dbus` Home 服务承接依赖，避免与 Niri 启动时的 `dbus-run-session` 会话总线冲突。
- **Emacs 服务**：以 `emacs --fg-daemon` 常驻，相关包隔离在 Emacs 专属 profile（`emacs-services` 块同时喂 home-emacs 与 neomacs 两个服务）。
- **Hermes 运行时**：FHS 基础依赖纳入 `home-packages` 维持 GC Root；系统冲突包（cairo、glib、gtk+ 等）写入独立的 manifest 部署到 Hermes 专属数据目录。
- **自定义包**：`custom-defines` 块的顶层 `define` 经 Noweb 拼入 `main` 顶部；`custom-packages-list` 只放包列表表达式（被 `main` 里 `(append ...)` 引用）。
- **指纹识别栈**：Goodix `27c6:689a` 需要 libfprint ≥1.94.9 的 `goodixmoc` 驱动，故定制了 libfprint 与 fprintd 变体包；PAM 层面把 `pam_fprintd.so` 作为 sufficient 规则插在 `pam_unix` 之前，实现指纹优先、密码兜底。

## Live ISO 构建

`blue build-iso` 先 tangle 出 `tmp/live-iso-<variant>.scm`（`desktop` = XFCE + labwc、免密自动登录 live 用户；`minimal` = 保留 tty1 TUI 安装器与 tty3-6 root 免密 shell），再由 `tools/build-image.scm` 构建镜像，产物落到 `dist/`。**tangle 目标必须是独立的 `tmp/live-iso-<variant>.scm`，绝对不能复用 `tmp/config.scm`**；ISO 专用的模块引用内联在各变体块内部，共享部分走 `<<live-common>>` noweb 片段（不独立 tangle）。完整构建流程见 `docs/iso-build.md`。

## 频道管理

- `channel.scm` 声明 Guix 官方频道与第三方扩展分支，**可手动编辑**；`channel.lock` 由 `blue update` 按当前锁定 Commit 自动生成并提交，**禁止手动编辑**。
- 更新顺序不可颠倒：编辑 `channel.scm` → `blue update`（重建并提交 `channel.lock`）→ `blue pull`（按锁定频道 `guix pull`）。`blue pull` 只认 `channel.lock`，不读 `channel.scm` 的未锁定改动。

## 验证

```bash
blue --dry-run rebuild     # 完整构建验证：真执行 tangle 与语法检查，不写入系统
blue check                 # 最快：逐块括号平衡检查，定位到具体块名
blue home                  # 仅构建并切换 Home 层（含 dotfiles），无需 sudo，供 agent 调试
```

> **语义改动的补充验证**：`--dry-run` 会短路 system build 验证。涉及结构改写、变量替换等语义变化时，另跑 `guix time-machine --channels=source/channel.lock -- system build tmp/config.scm --dry-run` 做实际求值；也可把 `git show HEAD:source/config.org` tangle 到隔离目录，与新产物逐块 diff，核对每处差异均为预期改动。
