# source/ — Guix 配置源目录

`config.org` 是唯一 Org 源（**不要新建第二个**），tangle 生成 `tmp/config.scm`；`blue rebuild` 完成 tangle → 括号检查 → reconfigure，单次同时应用 operating-system 与内嵌 guix-home-service。

config.org 正文只保留结构标签与一行式提示；**技术知识与取舍理由全部集中在本文**（内核另见 `files/kernel/AGENTS.md`，互链不重复）。

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

## 职责边界与原则

- **System**（`operating-system`）：引导器（Limine, rosenthal）、文件系统（LUKS+Btrfs+tmpfs）、内核（自编译 CachyOS LTS）、八个按职责拆分的服务块、用户账户；全局变量在 `information.scm`。
- **Home**（`home-environment`）：4 个包列表（desktop/terminal/devtools/user）+ custom + hermes 运行时、dotfiles 部署、Home 服务、环境变量、字体。
- **原则**：系统层最小化（首装快、迭代不碰系统 reconfigure），能用 Home 解决不上浮 System；优先改 `dotfiles/immutable/<app>/`，只在需要 Guix 介入时改 config.org。
- **两套部署路径不互通**：`source/files/`（home-files-service-type + 路径注入 `$$bin/foo$$`）与 `dotfiles/immutable/`（stow 软链到 `~`）。后者指向 /gnu/store 只读副本，改源后必须 `blue home` 重建软链接才生效。
- **新增应用流程**：`dotfiles/immutable/<app>/` 建目录 → 加到包列表 → 加到 `dotfile-services` 的 `packages` 列表。Emacs 新包须同时登记 `emacs-services` 的 `specifications->manifest`；新增/重命名 dotfile 子目录同样必须同步该列表。

## 修改 config.org 前必读

结构分区：模块导入 → 系统配置（Bootloader/FileSystems/Kernel/Packages/Services/Users）→ 用户配置（Packages/Services/Environment/Font）→ Live ISO。

**块级编辑**（改单个 `#+NAME:` 块，避免读全文件）：

```bash
blue block-show <name>                 # 提取块 body 到 tmp/block-<name>.scm（打印路径）
blue block-replace <name> <body-file>  # 替换 + 原子写回 + 括号验证
```

body 首两行是 lang/noweb 标记，第 3 行起是内容；可能含 `<<ref>>` 占位需自行追踪；括号验证仅对 scheme 块触发。适合低耦合小块，改 `emacs-services` 等高耦合大块仍建议读整段；失败时 `git checkout source/config.org` 恢复。

## Org Noweb 机制

- `#+NAME: ref` 命名代码块；`<<ref>>` 引用（**Org 功能，非 Scheme 语法**）
- `#+begin_src scheme :tangle ../tmp/config.scm :noweb yes` 标记 tangle 目标
- `<<ref>>` 是功能开关：注释掉的引用即停用该块

## 验证流程（改后必走）

```bash
blue rebuild               # tangle → 括号检查 → reconfigure → locate --update（agent 禁跑，提醒用户）
blue --dry-run rebuild     # 构建验证不写入（tangle/括号检查真跑）
blue home                  # 仅 Home 层（含 dotfiles），不需 sudo —— agent 调试用
blue check                 # 逐块括号平衡检查（定位到块名，最快）
```

## 全局变量与文件系统（`information.scm`）

被 `config.org` 头部 `(load "../source/information.scm")` 加载；变量清单直接读该文件。改前检查 `config.org` 各块引用是否需同步。

文件系统模型：根目录 tmpfs（重启清空）；持久化靠 Btrfs 子卷挂 `/var/lib`、`/gnu`、`/boot` 等；用户数据 `/data` 分区 bind-mount 到 `~`。**持久化目录必须同时在 `%data-dirs` 与 `%btrfs-subvolumes` 中登记**。头部代码块（全局变量、文件系统、内核）同时影响 system 与 home；启动时序敏感的服务集中在 `filesystem-services` 块。

- 休眠取舍：Guile initrd 不支持从加密 swap 恢复休眠镜像，加密与休眠二选一时保留了休眠——**休眠镜像把内存明文写入 swap 分区**。
- `fixed-machine-id` 的固定算法在 `information.scm`。

## files/ 模板系统

存放**需要路径注入**的静态模板，由 `home-files-service-type` 直接部署；`$$bin/foo$$` 替换为 Guix 包绝对路径（rosenthal `computed-substitution-with-inputs`）：模板内写占位符，`specs->pkgs` 参数提供对应包。**纯配置文件不要放这里**，放 `dotfiles/immutable/<app>/`。

## 系统层机制注记（为什么这么配）

- **内核模块**：`ip_tables`/`iptable_nat` 是 iptables 兼容层，libvirt/podman 网络后端依赖，与 nftables 规则集共存；`zswap.compressor=zstd` 写 cmdline 必回退 lzo（zswap late_initcall 早于任何 userspace modprobe），故 zstd 模块加载后经 `zswap-zstd` 服务运行时切换（旧页留原池、新页用新算法，内核官方支持）。
- **sysctl**：`default_qdisc=fq` —— BBR 的 pacing 依赖 fq 的 EDT 模型，fq_pie 使 BBR 退化为内核软件 pacing（CPU 开销更高、突发延迟更差）；`tcp_rmem`/`tcp_wmem` 三元组 —— 只设 `*_max` 时 tcp_wmem 仍受默认 4M 限制，高 BDP（跨国代理链路）必须设三元组；`dirty_writeback_centisecs=1500` —— 空闲时减少 SSD 唤醒，笔记本有电池掉电风险可忽略。
- **cleanup-/tmp**：/tmp 是 btrfs 持久挂载，标志文件 `/run/cleanup-tmp-done` 保证每开机周期只有首次真正清空（`find -mindepth 1 -delete` 保留目录本身，粘滞位修正 1777）；`cleanup-/tmp-prereq` 把 cleanup-/tmp 注入 `user-processes` requirement，使所有用户服务确定性排在清空之后（复用 file-systems→user-processes 官方注入手法）。
- **udev**：动态生成的规则文件必须 `file->udev-rule` 包装（把单文件包成含 `lib/udev/rules.d/` 结构的目录派生，裸 `computed-file` 被 rules union 静默跳过）；gexp 内不能裸调 `file-append`/`spec->pkg`（builder 无此绑定），store 路径宿主侧算好经 `#$` 注入。
- **AC 电源联动**：udev power_supply 事件 → PPD 切档 + WiFi 省电开关；udev 冷插拔早于 PPD 上线会静默失败，`ac-power-init` 开机按当前电源状态补跑一次。
- **桌面**：kmscon tty2-6、tty1 不设 getty 留内核消息、登录集中 tty7 greetd；elogind 挂起/休眠键一律 ignore（`hibernate-polkit` 例外放行本地活跃用户，规则文件 `50-hibernate.rules`）；fstrim 不在系统 profile，从 util-linux 注入 store 路径。

## 网络：nftables 与热点 AP 链

- **nftables**：规则集开机由 nftables-service-type 整体加载一次，NM dispatcher 只原子更新 `trusted_ifaces` 集合、绝不 `flush ruleset`（不删 libvirt 等运行时规则）；DHCP/ICMP 始终放行，保证不可信态能引导联网。
- **可信白名单**：NM profile 名（`CONNECTION_ID`，**非 SSID**，须与 `nmcli connection show` 一致），存 age 密文 `dotfiles/mutable/tools/secrets/.local/share/secrets-encrypted/wifi-trust.age`；dispatcher 只注入密文与 `age`/`nft`/`grep` 的 store 路径，解密直通管道给 grep 不落明文；私钥缺失/解密失败仅撤销 WiFi 信任，不阻断联网。白名单密文与 age 私钥属凭据，**agent 禁止读取/展示其明文内容或外发**；改动白名单由用户手动执行。
- **dispatcher 部署**：`/etc/NetworkManager` 是 btrfs 持久挂载点，etc-service-type 写不进，dispatcher 脚本经 activation 在每次 reconfigure 时拷贝到位。
- **热点 AP 链**（2026-09-09 断网事故复盘后的设计；脚本头注释含安全不变式，改前必读）：
  1. 隔离用 udev `ENV{NM_UNMANAGED}="1"`，不用 conf.d —— NM 1.54 不认 `device.interface-name`（unknown key 警告、从未生效），且持久子卷里坏 conf 跨系统代残留；activation 顺带删历史残留 `20-uap0-unmanaged.conf`。规则序号须 >75（75-net-description 会无条件重设 `ID_NET_NAME*`，共享 MAC 下 udev 会试图把 uap0 改名成 wlp0s20f3）。
  2. 信道不确定绝不起热点：managed+AP 并发合法但 `#channels<=1`，AP beacon 锁死 radio 信道（起在错误信道 = STA 连不上别的信道）。信道唯一来源：STA 已连信道，或扫描可见的 autoconnect profile 信道（且须无 no-IR 标志，本机 self-managed regdom 下 5G 全带 no IR）；皆无则 `exit 0` 等下一触发点，每分钟 `hotspot-recheck` timer 保证收敛。
  3. hostapd 配置必须带 `hw_mode`（默认 g 只有信道 1-14，5G 信道配 g = "Could not determine operating frequency"，事故真凶）；执行体读 `/run/auto-hotspot/channel`，文件缺失即拒绝启动。
  4. `hotspot-ap` 不 respawn：失败即停由决策脚本下个触发点重拉（respawn = 反复折腾接口的风暴）。
  5. 事件上下文（`SUBSYSTEM` / `NM_DISPATCHER_ACTION`）自重入后台执行 + flock 串行多入口（同步跑决策拖慢事件处理，dispatcher 版曾被 NM 退出的 SIGTERM 杀死）。
  6. 决策：AC 供电且 wlp0s20f3 当前 profile 不在可信名单才开；四个触发入口：auto-hotspot 服务（开机）、NM dispatcher 任意设备 up/down（WiFi 切换与网线插拔）、udev power_supply 插拔、每分钟 recheck timer。应急开关 `touch /run/hotspot-disabled`（tmpfs，重启自愈，只关不开）。
  - 热点凭据：age 密文 `.../secrets-encrypted/wifi-hotspot.age`（两行：SSID、密码）。生成/更新由用户手动执行：`printf 'SSID\n密码\n' | age -r <age公钥> -o .../wifi-hotspot.age`；agent 禁止读取/展示其明文或外发。

## 用户层注记

- 空 `dbus` 服务承接依赖，避免与拉起 niri 的 `dbus-run-session` 会话总线冲突。
- `emacs-services`：`emacs --fg-daemon` 常驻服务 + 包进 emacs 专属 profile。
- hermes-desktop：FHS 运行时进 `home-packages` 保 GC root（被当前 generation 引用不被 gc 清理）；与系统冲突的包（cairo/dconf/glib/gtk+）只进独立 manifest（tangle 到 `tmp/hermes-desktop-manifest.scm`）部署到 hermes 数据目录，不进 home profile。
- `cpu-dma-latency`：按需持有 `/dev/cpu_dma_latency`，默认不自启（待机功耗），音频低延迟场景手动 herd 启停。
- 计时器：flatpak 用户包周六 18:00（仅外接电源）、nix gc 周日 19:30（与 18:00 的 guix-gc 错峰）。
- `NIX_USER_CONF_FILES` 追加载入 `gh-token.conf`（GitHub API token 防 flake 解析 403 限流；0600 不进 git）。

## custom-packages 结构规则

`custom-package-defs` 放顶层 `define`（经 noweb 拼进 main 顶层）；`custom-packages-list` 只放表达式——它在 `%home` 的 `(append ...)` 引用点被内联，表达式位置写不了 `define`。新增包：先在 defs 块定义，再登记进 list 块。

## CachyOS LTS 内核

定义与操作规程（升级/换机/裁剪/消融/对拍）及全部取舍结论自包含于 `files/kernel/`，见 `files/kernel/AGENTS.md`；config.org 只 load 一行。

## 指纹识别栈（变体包要点）

- 根因：Goodix `27c6:689a`（match-on-chip，出厂固件）需 libfprint ≥1.94.9 的 `goodixmoc` 认领，Guix 上游 1.94.5 不认；网传 Goodix 闭源 TOD 驱动只覆盖 533C/539C/550a 等其他型号，勿装。
- libfprint 1.94.100 + fprintd 1.94.5 **必须同步升级**（fprintd 1.94.5 构建要求 libfprint ≥1.94.9）；升级只改两个 version 与对应 hash（`guix hash -f nix-base32`）。
- 变体点：输入 `nss→openssl`（1.94.7 起 URU4x00 改链 OpenSSL ≥3，为 lib/nss 设 rpath 的 configure flag 一并移除）；`-Dudev_hwdb=enabled` 强制装（eudev pkg-config 伪装 systemd 251，libfprint 的 auto 逻辑误判「已内置」而跳过 autosuspend hwdb，缺失即全系统没有 autosuspend 条目）；fprintd 1.94.5 用 `-Dlibsystemd=libelogind` 取代旧 `patch-systemd-dependencies` 补丁；pam_wrapper 已 required:false，旧 `ignore-test-dependencies` 补丁整体删除；`patch-output-directories` 保留（meson.build 写法未变，正则仍命中）。
- 接线：fprintd 是 D-Bus 按需激活非 shepherd 常驻（`herd` 看不到是正常的）；PAM transformer 把 `pam_fprintd.so` 以 sufficient 插到 pam_unix 前（指纹失败回落密码）；libfprint autosuspend hwdb（含 27c6:689a 条目）挂 `udev-service-type`。

## Live ISO

- `blue build-iso` → tangle `tmp/live-iso.scm` → `tools/build-image.scm` 出 iso9660；变体 desktop（XFCE + labwc Wayland）/minimal。

<critical>
- tangle 目标 `../tmp/live-iso.scm` **绝对不能复用** `../tmp/config.scm`，否则 `%live-installation-os` 污染主机配置
- `<<live-modules>>` 只被 live-installation-os 引用，**绝不能塞进主 `<<modules>>` 块**（会污染 tmp/config.scm）
- `blue check` 不做 cross-tangle 验证，改完 `tail tmp/live-iso.scm` 确认末行是 `%live-installation-os` 裸值
</critical>

- 机制：精简频道（guix+nonguix）经 modify-services 写进 guix-configuration，Live 的 `/etc/guix/channels.scm` 预置 nonguix（与 `<<guix-substitutes>>` 互补：一个管拉源码频道一个管下载二进制）；skeletons 把 `source/files/livecd` 平铺进 `/etc/skel`（target `"."` 平铺 copy-recursively，新增/删文件只改 livecd/ 目录不打表；**skeletons 覆盖不合并**，须保留 `%live-base-os` 默认 skeleton 的 .zprofile）；greetd autologin 直 execl 会话命令（`greetd-user-session` 不查 PATH，command 必须 `file-append` store 绝对路径；`xdg-session-type "wayland"` + `xdg-env?` 设好环境再 exec），退出后 agreety 兜底；elogind 供 PAM session 与 labwc 的 libseat seat；`labwc` 是 `startxfce4 --wayland` 合成器依赖，`wlr-randr` 供 XFCE Wayland 面板调分辨率。

## 频道管理

`channel.scm` 可编辑（频道与分支定义）；`channel.lock` 自动生成，**禁止手动编辑**。流程：改 `channel.scm` → `blue pull` → `blue update`。

<critical>
- 优先改 `dotfiles/`，只在需要 Guix 介入时改 `config.org`；能用 Home 解决就不用 System
- 不要手动编辑 `tmp/config.scm`（重新 tangle 会覆盖）
- 新增 dotfile 子目录后必须更新 `dotfile-services` 的 `packages` 列表
- Agent 禁止自行运行 `blue rebuild` / `guix system reconfigure`（需 sudo）；只许 `blue home` 调试，改完验证后提醒用户手动 rebuild
- 修改后必走验证流程（`blue --dry-run rebuild` / `blue check`）
</critical>
