<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# Chroot 救援手册 — tmpfs 根 + LUKS + Btrfs 子卷 + Limine

面向真机故障时的自己：在任意 live 发行版 U 盘里把本机存储解开、挂进 chroot、修完再退出。拓扑数据核对自 `source/information.scm`（拓扑的单一真源），配套脚本 `tools/rescue-chroot.sh` 默认 dry-run、只打印将执行的命令。

## 前置

适用场景（任意 live 发行版 U 盘，以 root 运行）：

- 能看到 Limine 菜单，但系统启动失败（内核 panic、shepherd 卡在某个服务、file-systems 失败等）；
- `guix system reconfigure` 之后起不来（配置改崩）；
- `/gnu`、`/var/guix` 出问题导致启动中断，需要重建或回滚；
- 引导相关文件损坏（`limine.conf`、`BOOTX64.EFI`、UKI `.EFI` 条目）。

不需要 chroot 的情况：只救用户数据时解开 LUKS 直接挂 `DATA/Share`（/data）即可；LUKS header 本身坏了走「排障」里的 header 抢救流程，本手册解决不了。

依赖工具（先把网络配好，后面 reconfigure 下载 substitutes 要用）：

| 工具                           | Arch                    | Debian / Ubuntu           |
| ------------------------------ | ----------------------- | ------------------------- |
| `cryptsetup`                   | `pacman -S cryptsetup`  | `apt install cryptsetup`  |
| `mount.btrfs`                  | `pacman -S btrfs-progs` | `apt install btrfs-progs` |
| `findmnt` / `mount` / `umount` | util-linux（自带）      | util-linux（自带）        |

## 操作

以下以目标根挂载点 `MNT=/mnt` 为例，每一步都假设你以 root 运行。

### 1. 存储拓扑速查

分区层（本机实测）：

| 分区             | UUID                                        | 内容                                                                |
| ---------------- | ------------------------------------------- | ------------------------------------------------------------------- |
| `/dev/nvme0n1p1` | `9699-52A2`（vfat 短 UUID，label `SYSTEM`） | ESP。Limine 本体 + 全部 UKI 启动项                                  |
| `/dev/nvme0n1p2` | `327f2e02-1e4f-48b2-87f0-797c481850c9`      | LUKS2，解锁后叫 `/dev/mapper/root`，内含整个 Btrfs（label `Linux`） |
| `/dev/nvme0n1p3` | `169557cc-00a4-448c-9bb6-7bd80fc2b023`      | 明文 swap（休眠镜像住这，内核参数 `resume=UUID=169557cc-…`）        |

Btrfs 子卷 → 挂载点（label `Linux`；表内 18 条系统挂载 + 独立的 `/data`）：

| 子卷                              | 挂载点                | 救援时                                                           |
| --------------------------------- | --------------------- | ---------------------------------------------------------------- |
| `SYSTEM/Guix/@gnu`                | `/gnu`                | **必挂**（store，一切的前提）                                    |
| `SYSTEM/Guix/@persist/guix`       | `/var/guix`           | **必挂**（system 代链、daemon 数据库都在这）                     |
| `SYSTEM/Guix/@boot`               | `/boot`               | **必挂**（reconfigure 重装引导用；ESP 独立在外面）               |
| `SYSTEM/Guix/@data`               | `/var/lib`            | 建议（machines / services 状态）                                 |
| `DATA/Share`                      | `/data`               | **必挂**（配置仓库在 `/data/Projects/Config/Guix-configs`）      |
| `DATA/Home/Guix`                  | `/home`               | 建议（blue 入口在 `~/.local/bin`、`.guix-home`）；脚本有意不挂它 |
| `SYSTEM/Guix/@persist/log`        | `/var/log`            | 建议（救日志时需要）                                             |
| `SYSTEM/Guix/@etc/guix`           | `/etc/guix`           | 建议（guix ACL / 配置持久层）                                    |
| `SYSTEM/Guix/@etc/NetworkManager` | `/etc/NetworkManager` | 建议（WiFi 配置住这）                                            |
| `SYSTEM/Guix/@etc/ssh`            | `/etc/ssh`            | 建议（host key 住这）                                            |
| `DATA/Flatpak`                    | `/var/lib/flatpak`    | 可选                                                             |
| `DATA/LibVirt`                    | `/var/lib/libvirt`    | 可选                                                             |
| `SYSTEM/Guix/@etc/libvirt`        | `/etc/libvirt`        | 可选                                                             |
| `SYSTEM/Guix/@persist/cache/root` | `/root/.cache`        | 可选                                                             |
| `SYSTEM/Guix/@persist/cache/var`  | `/var/cache`          | 可选                                                             |
| `SYSTEM/Guix/@persist/db`         | `/var/db`             | 可选                                                             |
| `SYSTEM/Guix/@persist/tmp`        | `/var/tmp`            | 可选                                                             |
| `SYSTEM/Guix/@tmp`                | `/tmp`                | 可选（系统配置里它才是唯一非开机挂载）                           |
| `SYSTEM/Guix/@nix`                | `/nix`                | 可选；已在 `information.scm` 里注释掉，脚本不会挂                |

其他运行时挂载（救援时**不需要**复刻）：`/` 与 `/var/lock` 是 tmpfs；`/gnu/store` 以只读 bind 叠在 `/gnu` 上；`/home/<user>/<目录>` 是从 `/data/<目录>` 来的一堆 bind（`%data-dirs`）。

`machine-id` 固定为 `7edb01e408858012cb48ab345b029b63`（= md5("brokenshine")，见 `information.scm` 的 `generate-machine-id`），随 etc 模板部署。

### 2. 解密 LUKS

```sh
cryptsetup open UUID=327f2e02-1e4f-48b2-87f0-797c481850c9 root
# 设备名可能漂移，等价写法：cryptsetup open /dev/nvme0n1p2 root
```

解锁后 Btrfs 在 `/dev/mapper/root`。若提示设备已存在，说明已经解开了，跳过即可。

### 3. 挂载 Btrfs 子卷

按依赖顺序（父挂载点在前）。`-o subvol=…,compress=zstd:3` 与系统日常一致：

```sh
MNT=/mnt; mkdir -p "$MNT"

# --- 最小集合（能 reconfigure 就靠这四个 + /data）---
mount -t btrfs -o subvol=SYSTEM/Guix/@gnu,compress=zstd:3         /dev/mapper/root "$MNT/gnu"
mount -t btrfs -o subvol=SYSTEM/Guix/@persist/guix,compress=zstd:3 /dev/mapper/root "$MNT/var/guix"
mount -t btrfs -o subvol=SYSTEM/Guix/@boot,compress=zstd:3        /dev/mapper/root "$MNT/boot"
mount -t btrfs -o subvol=DATA/Share,compress=zstd:3               /dev/mapper/root "$MNT/data"

# --- 建议集合（其余按第 1 步的表按需）---
mkdir -p "$MNT"/var/lib "$MNT"/home "$MNT"/var/log "$MNT"/etc/guix "$MNT"/etc/NetworkManager "$MNT"/etc/ssh \
         "$MNT"/var/{cache,db,tmp} "$MNT"/var/tmp "$MNT"/root/.cache "$MNT"/tmp
mount -t btrfs -o subvol=SYSTEM/Guix/@data,compress=zstd:3        /dev/mapper/root "$MNT/var/lib"
mount -t btrfs -o subvol=DATA/Home/Guix,compress=zstd:3           /dev/mapper/root "$MNT/home"
mount -t btrfs -o subvol=SYSTEM/Guix/@persist/log,compress=zstd:3 /dev/mapper/root "$MNT/var/log"
mount -t btrfs -o subvol=SYSTEM/Guix/@etc/guix,compress=zstd:3    /dev/mapper/root "$MNT/etc/guix"
mount -t btrfs -o subvol=SYSTEM/Guix/@etc/NetworkManager,compress=zstd:3 /dev/mapper/root "$MNT/etc/NetworkManager"
mount -t btrfs -o subvol=SYSTEM/Guix/@etc/ssh,compress=zstd:3     /dev/mapper/root "$MNT/etc/ssh"
# 其余（@nix、@tmp、@persist/*、DATA/Flatpak、DATA/LibVirt）按需同法挂载。
```

注意：`@etc/*` 要**先于**第 5 步的 /etc 拷贝挂好（先挂会被拷贝内容填充，后挂则盖住拷进去的同名目录——两种顺序都不会坏数据，但先挂更干净）。

### 4. bind /proc /sys /dev 与 ESP、网络

```sh
mount --rbind /dev  "$MNT/dev";  mount --make-rslave "$MNT/dev"
mount --rbind /proc "$MNT/proc"; mount --make-rslave "$MNT/proc"
mount --rbind /sys  "$MNT/sys";  mount --make-rslave "$MNT/sys"

# ESP（Limine 与 UKI 都在这）
mkdir -p "$MNT/efi"
mount UUID=9699-52A2 "$MNT/efi"

# 网络：live 的 resolv.conf 常是符号链，-L 取真身
cp -L /etc/resolv.conf "$MNT/etc/resolv.conf"
```

### 5. 重建 /etc（本手册的灵魂）

前提：`$MNT/gnu` 与 `$MNT/var/guix` 已挂。当前代 profile 链是 `$MNT/var/guix/profiles/system` → `system-<N>-link` → `/gnu/store/<hash>-system`；该目录里有 `activate`（activation 脚本）、`etc`（→ store 的 `-etc` /etc 模板）、`profile`（系统 union profile）、`configuration.scm`、`channels.scm`、`kernel`、`initrd`、`parameters`、`provenance` 等。

**方案一（推荐，简单）：拷贝 etc 模板**

```sh
mkdir -p "$MNT/etc"
cp -a "$MNT/var/guix/profiles/system/etc/." "$MNT/etc/"
```

可行是因为这个 `etc/` 就是每次开机 activation 往 /etc 拷贝的同一份模板，含 fstab、hosts、pam.d、profile、sudoers、udev 等全部静态内容，其中 hostname、machine-id 等是**指向 store 的符号链**，`cp -a` 原样保留，挂好 `/gnu` 后这些 store 路径全部有效。局限（实测确认）：它是**静态快照**，不含 activation 运行时生成的 `/etc/passwd`、`/etc/shadow`、`/etc/group`（账户数据库）与 `/etc/mtab`。也就是说 chroot 本身没问题（bash 不查 passwd），`guix system reconfigure` 也没问题（它最后跑的 activation 会把账户全部建回来），但**别指望用这份 /etc 起 sshd 或查用户**。

**方案二（完整）：在 chroot 里跑真正的 activation**

进 chroot 后（第 6 步）执行：

```sh
/var/guix/profiles/system/activate
```

会发生什么：先用 store 的 guile 执行；`activate-current-system` 建立 `/run/current-system` 符号链；随后依序加载每个服务的 `activate-service.scm`——etc 服务把模板拷进 /etc，accounts 服务生成 passwd / shadow / group / guixbuild 构建用户等。每个服务的加载都包在 `guard` 里，**单个失败只打 warning 不中断**。前置条件是 `/gnu`、`/var/guix` 已挂；脚本自己 `mkdir-p /var/run`、`/var/log`，不需要 shepherd 在跑（activation 只建立状态，不启动服务）。风险与副作用：它是为「正在启动的系统」设计的，在 chroot 里跑属于借道——会写 chroot 内的 `/run/current-system`（无害，下次正常启动会重设），并把该代声明的所有服务状态目录都建立一遍。它激活的是 `profiles/system` 指向的那一代；如果最后那次 reconfigure 就是肇事者，可改跑旧代的，例如 `/var/guix/profiles/system-698-link/activate`（代号按 `ls /var/guix/profiles/` 现查）。

怎么选：想尽快进 chroot 修东西就用方案一（一条 `cp`，chroot 前完成，无副作用）；需要 chroot 里有完整账户 / 构建用户，或想「原样复活」一次，就用方案二。实践上**先方案一进 chroot，进去后若有需要再补跑方案二**——两者不冲突，activate 会把模板重新拷一遍并补上运行时文件。

### 6. chroot 进入（注意 /bin 不存在）

**坑**：通用教程的 `chroot /mnt /bin/sh` 在本机**必然失败**——tmpfs 根下关机态连 `/bin` 都没有（运行系统里的 `/bin/sh` 是启动过程建出来的符号链）。解法是用 store 里的 bash，稳定入口是系统 profile 的符号链（代际无关）：

```sh
chroot "$MNT" /var/guix/profiles/system/profile/bin/bash --login
```

`--login` 会读 /etc/profile（第 5 步之后它已存在），把 PATH 等配好。如果方案一都还没做、`/etc/profile` 不在，就先裸进再手动 source：

```sh
chroot "$MNT" /var/guix/profiles/system/profile/bin/bash
# 进去后：
source /var/guix/profiles/system/profile/etc/profile
export PATH=/var/guix/profiles/per-user/root/current-guix/bin:$PATH   # guix 命令入口
```

兜底：profile 里没有 bash 时（极少见），直接挑 store 里的——`ls -d /mnt/gnu/store/*-bash-*/bin/bash`，任选一个完整路径 `chroot` 进去；这些 `*-bash-*` store 条目长期存在（bash-static 也在）。

### 7. chroot 内的修复操作

**起 guix-daemon（最小形态）**：

```sh
/var/guix/profiles/per-user/root/current-guix/bin/guix-daemon \
  --build-users-group=guixbuild --disable-chroot &
```

`current-guix` 就是上次 `guix pull` 的成果，它带的 channels 与上次 reconfigure 一致，是首选的 guix。`guixbuild` 账户从哪来：它是 activation 生成的（方案二），方案一**没有**——只有方案一时用空构建组，构建以 root 跑（救援场景可接受）：

```sh
/var/guix/profiles/per-user/root/current-guix/bin/guix-daemon \
  --build-users-group= --disable-chroot &
```

大多数包走 substitutes 下载，不需要本地构建；断网时本地构建慢但可行。

**拿到配置仓库**：首选无需网络的 `/data/Projects/Config/Guix-configs`（第 3 步挂好 `/data` 后直接用，仓库物理上就住在 `DATA/Share` 上）。blue 入口在 `/home/brokenshine/.guix-home/profile/bin/blue`（blue 本体，依赖都在 store 里）：仓库根目录下 `blue --dry-run rebuild` 验证，然后 `blue rebuild`（救援 chroot 里你已经是 root）。仓库真丢了再走网络 clone 到 `/data/Projects/` 下同路径。store 里的 `configuration.scm` 只能当参考——它开头是 `(load "../source/information.scm")` 这类相对路径引用，脱离仓库布局无法求值，但完整记录了该代的最终源码，对照排查极有用。

**reconfigure（修配置后固化）**：

```sh
cd /data/Projects/Config/Guix-configs
blue rebuild        # tangle config.org → tmp/config.scm 并 reconfigure（系统 + Home 一次完成）
```

blue 不可用时手动：先把 `tmp/config.scm` tangle 出来（见 [emergency-blue.md](emergency-blue.md)），再 `guix system reconfigure tmp/config.scm`。reconfigure 会同时构建新代、更新 `/var/guix/profiles/system` 链、**重写 limine.conf 并用 ukify 重新生成全部 UKI**。

**回滚旧代**：本次临时启动可在 Limine 菜单里选 `old configurations` 下的条目，标签自带 `#N` 代号；旧代 UKI 的内核 cmdline 内嵌 `gnu.system=/var/guix/profiles/system-N-link`，所以旧代能独立于当前链启动。注意**仅改 `/var/guix/profiles/system` 符号链不会改变默认启动项**——`CURRENT.EFI` 的 cmdline 里烧录的是当时 reconfigure 的 store 路径；永久回滚要在旧代系统里跑 `sudo guix system roll-back`（会重装引导、重写 UKI），或修好配置后直接 reconfigure。手改引导（低层兜底）：`/efi/EFI/BOOT/limine.conf` 是**纯文本**，条目形如 `/GNU system, old configurations...` / `//GNU with Linux-Cachyos-Lts 6.18.48-2 (#698, 2026-09-21 20:09)` / `protocol: efi` / `path: boot():/EFI/Guix/OLD-1.EFI`——想临时从 OLD-1 启动，把这段挪到文件最前（或加 `default_entry:` 指向它）；UKI 文件本身都在 `/efi/EFI/Guix/` 下。

**Limine 本体损坏 / ESP 被清**：只丢了 `BOOTX64.EFI` 时从 store 拷回——`ls -d /gnu/store/*-limine-*/share/limine/BOOTX64.EFI`，复制到 `/efi/EFI/BOOT/BOOTX64.EFI`（removable 路径，固件自动认，无需 efibootmgr）。UKI（`CURRENT.EFI` / `OLD-N.EFI`）丢失跑一次 reconfigure 即会全部重建，无需单独操作。

### 8. 退出清理（逆序）

```sh
umount "$MNT/dev" "$MNT/proc" "$MNT/sys"          # rbind 先撤
umount "$MNT/efi"
# 子卷从叶子到根：
umount "$MNT/etc/"{guix,NetworkManager,ssh} "$MNT"/var/lib/flatpak "$MNT"/var/lib/libvirt 2>/dev/null
umount "$MNT"/{var/lib,var/log,var/cache,var/db,var/tmp,var/guix,tmp,root/.cache,nix,boot,home,data,gnu}
cryptsetup close root
```

umount 报 target busy 时查 `fuser -vm $MNT` 或 `lsof +D $MNT`，多半是有 shell 还在 chroot 里。

### 9. 一键脚本

`tools/rescue-chroot.sh` 把第 2-6 步串成一条龙（解密 → 全子卷挂载 → ESP → rbind → 拷 /etc → resolv.conf），并支持 `chroot`（store bash 自动定位 + 自动 source profile）与逆序 `umount`：

```sh
sudo tools/rescue-chroot.sh status            # 任意时候安全（只读）
sudo tools/rescue-chroot.sh mount /mnt        # dry-run：只打印计划
sudo tools/rescue-chroot.sh mount /mnt --go   # 真执行
sudo tools/rescue-chroot.sh chroot /mnt       # 进入（默认 dry-run 打印命令）
sudo tools/rescue-chroot.sh umount /mnt --go  # 逆序卸载并关 LUKS
```

不带 `--go` 一律 dry-run 只回显，交互输入 yes 也可执行。脚本检测到「当前就在运行中的 Guix 主机上」时会拒绝 mount/chroot（防止手滑把自己挂穿），`--force` 可越过（危险）。`mount` 阶段会问 /etc 重建方式：方案一拷模板、方案二只提示命令等你进 chroot 后手动跑 activate、跳过。

## 关键约束

**红线条目（救援现场）**：

- **绝不在 live 环境跑目标系统的 `activate` 脚本**——脚本里全是 `/etc`、`/var` 绝对路径，在 live 环境跑会把 live 系统自己写坏。
- **不跑 `guix gc`**，尤其是 `-d`：`/var/guix/profiles/system-*-link` 是 gc root，旧代 UKI 的 cmdline 还引用着这些 store 路径，gc 掉任何一条都可能让某个启动项永久失效；同理**不删 `system-*-link`**。
- 不 `mkswap` / 格式化 swap 分区（`169557cc-…`）：它承担休眠镜像，救援时可 `swapon` 但别动数据。
- live 环境对 `DATA/Share`（/data）只读优先——那是有唯一副本的数据，明确要救数据时再写。
- 不跑 ESP 上残留的旧 `install-limine.scm`（陈年参数，会写出错误 UKI）。
- 不在 chroot 里跑 `herd` / shepherd（没有 PID 1，必然失败或产生误导）。
- btrfs 别手滑 `balance` / `reshape`；单设备盘没有冗余可挥霍。

**为什么 chroot 时 /etc 是空的**：根目录 `/` 整个是 **tmpfs，关机即清空**；Guix 标准机制下 /etc 不是磁盘上的静态目录，而是每次开机由 activation 服务从 store 里的 `-etc` 模板重建，并顺带生成 `passwd`、`shadow`、`group` 等账户文件。上表里 `@etc/*` 四个子卷叠在 /etc 内部，**它们才真正住在磁盘上**（实测：etc 模板里根本没有 passwd/shadow/group/mtab）。所以磁盘上不存在一份现成的 /etc 等着你挂载，必须在 chroot 前自己重建。

**拓扑解析契约**（改 `information.scm` 布局时必看）：live 环境没有 guile，脚本用 sed / grep 做受限文本解析，要求 `information.scm` 的磁盘拓扑段保持「一行一个 `(define %var "...")` 顶格」、`%btrfs-subvolumes` 的首条目与 `'(` 同行、条目形如 `("子卷" "挂载点")` 二元组。解析失败即中止——宁可拒绝运行也不用陈旧拓扑动磁盘。`information.scm` 定位顺序：`INFO_SCM` 环境变量 > 脚本同目录（U 盘救援时两文件拷在一起即可）> 脚本所在 `tools/` 的 `../source/`。`/home` 子卷被有意排除（家目录持久化靠运行时 bind-mount，救援 chroot 用不到）；`/data` 单独必挂（配置仓库所在）。

## 排障

| 场景                             | 处理                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 配置改崩起不来                   | 走完第 2-6 步进 chroot → 进 `/data/Projects/Config/Guix-configs` → `git diff` 看上次改动 → `blue rebuild` 或临时 `git revert`。来不及改：Limine 菜单选旧代先进系统，回系统里再修                                                                                                                                                                                                                                                                                                 |
| Limine / UKI 坏                  | 三板斧：手编 `limine.conf` → 从 store 拷回 `BOOTX64.EFI` → reconfigure 全量重写                                                                                                                                                                                                                                                                                                                                                                                                  |
| `/gnu` 损坏（最后一招）          | 先试无损手段：live 环境 `btrfs scrub start -B /dev/mapper/root`（单设备无冗余，scrub 只能**发现**坏块不能修复）；`/var/guix` 坏了可对照 `ls /var/guix/profiles/` 重建符号链。真到 store 大面积损坏：官方 Guix ISO（或本仓库 `blue build-iso` 的自建 ISO，见 [iso-build.md](iso-build.md)）启动 → 解密挂载同上 → `guix system init /data/Projects/Config/Guix-configs/tmp/config.scm /mnt` 重建系统（存量 store 条目会复用）→ 全新安装路线见 `tools/bootstrap.sh` 与 `README.org` |
| umount 报 target busy            | `fuser -vm $MNT` 或 `lsof +D $MNT`，多半是有 shell 还在 chroot 里                                                                                                                                                                                                                                                                                                                                                                                                                |
| `mount: /mnt/xxx: wrong fs type` | live 环境缺 `mount.btrfs`（装 btrfs-progs）                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| 脚本拒绝执行                     | 检测到当前就是运行中的 Guix 主机；确认要冒险再 `--force`                                                                                                                                                                                                                                                                                                                                                                                                                         |

**LUKS header 损坏**（预防 + 抢救）：header 坏 = 整盘数据不可见。预防**现在就该做**——在正常系统里把 header 备份到 /data 之外的离线介质（如 U 盘）：

```sh
sudo cryptsetup luksHeaderBackup /dev/nvme0n1p2 \
  --header-backup-file /run/media/<U盘>/luks-header-$(date +%F).img
```

抢救：`sudo cryptsetup luksHeaderRestore /dev/nvme0n1p2 --header-backup-file <img>`。header 与盘一一对应（UUID / 槽位 / metadata size），换盘换版本未必能用；每次动 LUKS 相关配置后重新备份。

## 相关

- `tools/rescue-chroot.sh`——一键脚本本体
- `source/information.scm`——存储拓扑的单一真源，脚本运行时解析它
- [emergency-blue.md](emergency-blue.md)——chroot 里 blue 不可用时的手动部署序列
- [iso-build.md](iso-build.md)——自建救援 ISO
