# Chroot 救援手册 — tmpfs 根 + LUKS + Btrfs 子卷 + Limine

> 面向「未来的恐慌中的自己」。拓扑数据核对自 `source/information.scm`（2026-09-22，与本机 `/proc/mounts` 逐项比对一致）。
> 配套脚本：`tools/rescue-chroot.sh`（默认 dry-run，只打印将执行的命令）。
> **改了 `information.scm` 的拓扑，就要同步本文档和脚本顶部的变量块**——两处 + 源码，共三份真源。

---

## 1. 适用场景

什么时候用这份手册（在任意 live 发行版 U 盘里）：

- 能看到 Limine 菜单，但系统启动失败（内核 panic、shepherd 卡在某个服务、file-systems 失败等）
- `guix system reconfigure` 之后起不来（配置改崩）
- `/gnu`、`/var/guix` 出问题导致启动中断，需要重建或回滚
- 引导相关文件损坏（`limine.conf`、`BOOTX64.EFI`、UKI `.EFI` 条目）

什么时候**不需要** chroot：

- 只是救用户数据：解开 LUKS 直接挂 `DATA/Share`（/data）就行，见 §2。
- LUKS header 本身坏了：先看 §5.3（那是另一套流程，本手册解决不了）。

---

## 2. 本机存储拓扑速查表

### 2.1 分区层

| 分区（本机实测） | UUID | 内容 |
| --- | --- | --- |
| `/dev/nvme0n1p1` | `9699-52A2`（vfat 短 UUID，label `SYSTEM`） | ESP。Limine 本体 + 全部 UKI 启动项 |
| `/dev/nvme0n1p2` | `327f2e02-1e4f-48b2-87f0-797c481850c9` | LUKS2，解锁后叫 `/dev/mapper/root`，内含整个 Btrfs（label **`Linux`**） |
| `/dev/nvme0n1p3` | `169557cc-00a4-448c-9bb6-7bd80fc2b023` | **明文 swap**（休眠镜像住这，内核参数 `resume=UUID=169557cc-…`） |

### 2.2 Btrfs 子卷 → 挂载点（label `Linux`，共 19 个子卷 / 18 条系统挂载 + /data）

| 子卷 | 挂载点 | 救援时 |
| --- | --- | --- |
| `SYSTEM/Guix/@gnu` | `/gnu` | **必挂**（store，一切的前提） |
| `SYSTEM/Guix/@persist/guix` | `/var/guix` | **必挂**（system 代链、daemon 数据库都在这） |
| `SYSTEM/Guix/@boot` | `/boot` | **必挂**（reconfigure 重装引导用；ESP 独立在外面） |
| `SYSTEM/Guix/@data` | `/var/lib` | 建议（machines/services 状态） |
| `DATA/Share` | `/data` | **必挂**（配置仓库在 `/data/Projects/Config/Guix-configs`） |
| `DATA/Home/Guix` | `/home` | 建议（blue 入口在 `~/.local/bin`、`.guix-home`） |
| `DATA/Flatpak` | `/var/lib/flatpak` | 可选 |
| `DATA/LibVirt` | `/var/lib/libvirt` | 可选 |
| `SYSTEM/Guix/@nix` | `/nix` | 可选（不修 nix 就不用） |
| `SYSTEM/Guix/@persist/cache/root` | `/root/.cache` | 可选 |
| `SYSTEM/Guix/@persist/cache/var` | `/var/cache` | 可选 |
| `SYSTEM/Guix/@persist/db` | `/var/db` | 可选 |
| `SYSTEM/Guix/@persist/log` | `/var/log` | 建议（救日志时需要） |
| `SYSTEM/Guix/@persist/tmp` | `/var/tmp` | 可选 |
| `SYSTEM/Guix/@tmp` | `/tmp` | 可选（系统配置里它才是唯一非开机挂载） |
| `SYSTEM/Guix/@etc/guix` | `/etc/guix` | 建议（guix ACL/配置持久层） |
| `SYSTEM/Guix/@etc/libvirt` | `/etc/libvirt` | 可选 |
| `SYSTEM/Guix/@etc/NetworkManager` | `/etc/NetworkManager` | 建议（WiFi 配置住这） |
| `SYSTEM/Guix/@etc/ssh` | `/etc/ssh` | 建议（host key 住这） |

其他运行时挂载（救援时**不需要**复刻）：`/` 与 `/var/lock` 是 tmpfs；`/gnu/store` 以只读 bind 叠在 `/gnu` 上；`/home/<user>/<dir>` 是从 `/data/<dir>` 来的一堆 bind（`%data-dirs`）。

`machine-id` 固定为 `7edb01e408858012cb48ab345b029b63`（= md5("brokenshine")，见 `information.scm` 的 `generate-machine-id`），随 etc 模板部署。

### 2.3 为什么 chroot 时 /etc 是空的（根因）

根目录 `/` 整个是 **tmpfs，关机即清空**。Guix 标准机制下 /etc 不是磁盘上的静态目录，而是**每次开机由 activation 服务从 store 模板重建**的：

1. 开机 → shepherd 跑当前代的 activation 脚本（`/gnu/store/<hash>-system/activate`）；
2. activation 把 store 里 `-etc` 模板的内容拷进 `/etc`，并生成账户（`/etc/passwd`、`/etc/shadow`、`/etc/group`）、`/etc/mtab` 等运行时文件；
3. 上面表格里 `@etc/*` 四个子卷叠在 `/etc` 内部，**它们才真正住在磁盘上**。

本机实测证据（2026-09-22）：

- `/etc/passwd`、`/etc/group`、`/etc/shadow` 的 mtime = 本次开机时刻（与 `/run/current-system` 符号链同时刻）；
- etc 模板 `/var/guix/profiles/system/etc/` 里**没有** passwd/shadow/group/mtab——它们是 activation 运行时生成的，不在模板里。

所以磁盘上根本不存在一份现成的 /etc 等着你挂载——必须**在 chroot 前自己重建**（§3.4），这正是本手册与通用教程的核心差异。

---

## 3. 完整流程（任意 live 发行版）

以下以目标根挂载点 `MNT=/mnt` 为例。**每一步都假设你以 root 运行。**

### 3.0 依赖

| 工具 | Arch | Debian/Ubuntu |
| --- | --- | --- |
| `cryptsetup` | `pacman -S cryptsetup` | `apt install cryptsetup` |
| `mount.btrfs` | `pacman -S btrfs-progs` | `apt install btrfs-progs` |
| `findmnt/mount/umount` | util-linux（自带） | util-linux（自带） |

先把网络配好（后面 reconfigure 下载 substitutes 要用）。

### 3.1 解密 LUKS

```sh
cryptsetup open UUID=327f2e02-1e4f-48b2-87f0-797c481850c9 root
# 设备名可能漂移，等价写法: cryptsetup open /dev/nvme0n1p2 root
```

解锁后 Btrfs 在 `/dev/mapper/root`。若提示设备已存在，说明已经解开了，跳过即可。

### 3.2 挂载 Btrfs 子卷

按依赖顺序（父挂载点在前）。`-o subvol=…,compress=zstd:3` 与系统日常一致：

```sh
MNT=/mnt; mkdir -p "$MNT"

# --- 最小集合（能 reconfigure 就靠这四个 + /data） ---
mount -t btrfs -o subvol=SYSTEM/Guix/@gnu,compress=zstd:3         /dev/mapper/root "$MNT/gnu"
mount -t btrfs -o subvol=SYSTEM/Guix/@persist/guix,compress=zstd:3 /dev/mapper/root "$MNT/var/guix"
mount -t btrfs -o subvol=SYSTEM/Guix/@boot,compress=zstd:3        /dev/mapper/root "$MNT/boot"
mount -t btrfs -o subvol=DATA/Share,compress=zstd:3               /dev/mapper/root "$MNT/data"

# --- 建议集合（其余按 §2.2 表按需） ---
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

注意：`@etc/*` 要**先于** §3.4 的 /etc 拷贝挂好（先挂会被拷贝内容填充，后挂则会盖住拷进去的同名目录——两种顺序都不会坏数据，但先挂更干净）。

### 3.3 bind /proc /sys /dev 与 ESP

```sh
mount --rbind /dev  "$MNT/dev";  mount --make-rslave "$MNT/dev"
mount --rbind /proc "$MNT/proc"; mount --make-rslave "$MNT/proc"
mount --rbind /sys  "$MNT/sys";  mount --make-rslave "$MNT/sys"

# ESP（Limine 与 UKI 都在这）
mkdir -p "$MNT/efi"
mount UUID=9699-52A2 "$MNT/efi"
```

### 3.4 重建 /etc（本手册的灵魂）

前提：`$MNT/gnu` 与 `$MNT/var/guix` 已挂。当前代 profile 链是：

```
$MNT/var/guix/profiles/system  →  system-<N>-link  →  /gnu/store/<hash>-system
```

`<hash>-system` 目录里有：`activate`（activation 脚本）、`etc`（→ store 的 `-etc` /etc 模板）、`profile`（系统 union profile）、`configuration.scm`、`channels.scm`、`kernel`、`initrd`、`parameters`、`provenance` 等。

#### 方案一（推荐，简单）：拷贝 etc 模板

```sh
mkdir -p "$MNT/etc"
cp -a "$MNT/var/guix/profiles/system/etc/." "$MNT/etc/"
```

- **为什么可行**：这个 `etc/` 就是每次开机 activation 往 /etc 拷贝的同一份模板。它包含 fstab、hosts、pam.d、profile、sudoers、udev 等全部静态内容，其中 hostname、machine-id 等是**指向 store 的符号链**，`cp -a` 原样保留符号链，而这些 store 路径在挂好 `/gnu` 后全部有效。
- **局限（实测确认）**：它是**静态快照**，不含 activation 运行时生成的文件——最关键的三个是 `/etc/passwd`、`/etc/shadow`、`/etc/group`（账户数据库），还有 `/etc/mtab` 等。这意味着：chroot 本身没问题（bash 不查 passwd），`guix system reconfigure` 也没问题（它最后跑的 activation 会把账户全部建回来），但**别指望用这份 /etc 起 sshd 或查用户**；起 guix-daemon 时要留意 §3.6 的 `guixbuild` 说明。

#### 方案二（完整）：在 chroot 里跑真正的 activation

进 chroot 后（§3.5）执行：

```sh
/var/guix/profiles/system/activate
```

- **会发生什么**（读过本机 store 里该脚本本体，非猜测）：先用 store 的 guile 执行；`activate-current-system` 建立 `/run/current-system` 符号链；随后**依序加载每个服务的 `activate-service.scm`**——etc 服务把模板拷进 /etc，accounts 服务生成 passwd/shadow/group/guixbuild 构建用户等。每个服务的加载都包在 `guard` 里，**单个失败只打 warning 不中断**。
- **前置条件**：`/gnu`、`/var/guix` 已挂；脚本会自己 `mkdir-p /var/run`、`/var/log`。不需要 shepherd 在跑——activation 只建立状态，不启动服务。
- **风险与副作用（如实说）**：它是为「正在启动的系统」设计的，在 chroot 里跑属于借道：会写 chroot 内的 `/run/current-system`（无害，下次正常启动会重设）；会把该代声明的所有服务状态目录都建立一遍（绝大多数正是你要的）。它激活的是 `profiles/system` 指向的那一代——如果最后那次 reconfigure 就是肇事者，可以改跑旧代的，例如 `/var/guix/profiles/system-698-link/activate`（代号按 `ls /var/guix/profiles/` 现查）。
- **绝对禁止**在 live 环境（chroot 之外）直接跑它——脚本里全是 `/etc`、`/var` 绝对路径，在 live 环境跑会写坏 live 系统自己的目录。

#### 两方案怎么选

| | 方案一（拷模板） | 方案二（跑 activate） |
| --- | --- | --- |
| /etc 完整度 | 静态部分；缺 passwd/shadow/group | 完整（含账户、guixbuild） |
| 操作成本 | 一条 cp，chroot 前完成 | 需先进 chroot |
| 副作用 | 无 | 多服务状态目录重建；个别服务 activation 可能告警 |
| 适合 | 想尽快进 chroot 修东西（**默认选这个**） | 需要 chroot 里有完整账户/构建用户，或想「原样复活」一次 |

实践推荐：**先方案一进 chroot，进去后若有需要再补跑方案二**（两者不冲突，activate 会把模板重新拷一遍并补上运行时文件）。

### 3.5 chroot 进入（注意 /bin 不存在）

**坑**：通用教程的 `chroot /mnt /bin/sh` 在本机**必然失败**——tmpfs 根下关机态连 `/bin` 都没有（运行系统里的 `/bin/sh` 是启动过程建出来的符号链）。解法：用 store 里的 bash。稳定入口是系统 profile 的符号链（代际无关，2026-09-22 验证存在）：

```sh
chroot "$MNT" /var/guix/profiles/system/profile/bin/bash --login
```

- `--login` 会读 /etc/profile（方案一/二之后它已存在），把 PATH 等配好。
- 如果方案一都还没做，`/etc/profile` 不在，就先裸进再手动 source：

```sh
chroot "$MNT" /var/guix/profiles/system/profile/bin/bash
# 进去后：
source /var/guix/profiles/system/profile/etc/profile
export PATH=/var/guix/profiles/per-user/root/current-guix/bin:$PATH   # guix 命令入口
```

- 兜底：profile 里没有 bash 时（极少见），直接挑 store 里的：`ls -d /mnt/gnu/store/*-bash-*/bin/bash`，任选一个完整路径 `chroot` 进去。这些 `*-bash-*` store 条目长期存在（bash-static 也在）。
- 别忘了网络：`cp -L /etc/resolv.conf "$MNT/etc/resolv.conf"`（live 的 resolv.conf 常是符号链，`-L` 取真身）。

### 3.6 进去之后的修复操作

#### 起 guix-daemon（最小形态）

```sh
/var/guix/profiles/per-user/root/current-guix/bin/guix-daemon \
  --build-users-group=guixbuild --disable-chroot &
```

- `current-guix` 就是上次 `guix pull` 的成果（已验证存在），它带的 channels 与上次 reconfigure 一致，是首选的 guix。
- **`guixbuild` 账户从哪来**：它是 activation 生成的（方案二）或 `/etc/passwd` 里现成的（方案一**没有**）。只有方案一时，用空构建组禁用构建用户（构建以 root 跑，救援场景可接受）：

```sh
/var/guix/profiles/per-user/root/current-guix/bin/guix-daemon \
  --build-users-group= --disable-chroot &
```

- 大多数包走 substitutes 下载，不需要本地构建；断网时本地构建慢但可行。

#### 拿到配置仓库

- 首选（无需网络）：仓库物理上住在 `/data`——`/data/Projects/Config/Guix-configs`（`Projects` 在 `%data-dirs` 里，源码即 `DATA/Share` 子卷上的实体）。§3.2 挂好 `/data` 后直接用。
- blue 入口：`/home/brokenshine/.local/bin/blue`（wrapper，实际落在 `/home/brokenshine/.guix-home/profile/bin/blue`，依赖都在 store 里）。仓库根目录下 `blue --dry-run rebuild` 验证，然后 `blue rebuild`（救援 chroot 里你已经是 root）。
- 仓库丢了再走网络 clone 到 `/data/Projects/` 下同路径。
- **store 里的 `configuration.scm` 只能当参考**：本机验证过它开头是 `(load "../source/information.scm")` 这类相对路径引用，脱离仓库布局无法求值；但它完整记录了该代的最终源码，对照排查极有用。

#### 重配置 / 回滚 / 修引导

- **reconfigure**（修配置后固化）：

  ```sh
  cd /data/Projects/Config/Guix-configs
  blue rebuild        # tangle config.org → tmp/config.scm 并 reconfigure（系统+Home 一次完成）
  ```

  blue 不可用时手动：先想办法把 `tmp/config.scm` tangle 出来，然后
  `guix system reconfigure tmp/config.scm`。reconfigure 会同时：构建新代、更新 `/var/guix/profiles/system` 链、**重写 limine.conf 并用 ukify 重新生成全部 UKI**。

- **回滚旧代**：
  - 本次临时启动：Limine 菜单里选 `old configurations` 下的条目，标签自带 `#N` 代号。旧代 UKI 的内核 cmdline 内嵌 `gnu.system=/var/guix/profiles/system-N-link`，所以旧代能独立于当前链启动。
  - **注意**：仅改 `/var/guix/profiles/system` 符号链**不会**改变默认启动项——`CURRENT.EFI` 的 cmdline 里烧录的是当时 reconfigure 的 store 路径。永久回滚要在旧代系统里跑 `sudo guix system roll-back`（会重装引导、重写 UKI），或修好配置后直接 reconfigure。
  - 手改引导（低层兜底）：`/efi/EFI/BOOT/limine.conf` 是**纯文本**，条目形如：

    ```
    /GNU system, old configurations...
    //GNU with Linux-Cachyos-Lts 6.18.48-2 (#698, 2026-09-21 20:09)
      protocol: efi
      path: boot():/EFI/Guix/OLD-1.EFI
    ```

    想临时从 OLD-1 启动：把这段挪到文件最前（或加 `default_entry:` 指向它）。UKI 文件本身都在 `/efi/EFI/Guix/` 下。

- **Limine 本体损坏/ESP 被清**：
  - 只丢了 `BOOTX64.EFI`：从 store 拷回——`ls -d /gnu/store/*-limine-*/share/limine/BOOTX64.EFI`，复制到 `/efi/EFI/BOOT/BOOTX64.EFI`（removable 路径，固件自动认，无需 efibootmgr）。
  - UKI（`CURRENT.EFI`/`OLD-N.EFI`）丢失：跑一次 reconfigure 即会全部重建，无需单独操作。
  - ESP 上残留的 `/efi/install-limine.scm` 是**历史遗留**（核对过：内容还是今年 4 月旧内核代的参数），**不要执行它**。

### 3.7 退出清理（逆序）

```sh
umount "$MNT/dev" "$MNT/proc" "$MNT/sys"          # rbind 先撤
umount "$MNT/efi"
# 子卷从叶子到根：
umount "$MNT/etc/"{guix,NetworkManager,ssh} "$MNT"/var/lib/flatpak "$MNT"/var/lib/libvirt 2>/dev/null
umount "$MNT"/{var/lib,var/log,var/cache,var/db,var/tmp,var/guix,tmp,root/.cache,nix,boot,home,data,gnu}
cryptsetup close root
```

umount 报 target busy：查 `fuser -vm $MNT` 或 `lsof +D $MNT`，多半是有 shell 还在 chroot 里。

---

## 4. 常见修复场景索引

### 4.1 配置改崩，起不来

chroot（§3.1–3.5）→ 进 `/data/Projects/Config/Guix-configs` → `git diff` 看上次改动 → `blue rebuild` 或临时 `git revert`。来不及改：Limine 菜单选旧代先进系统，回系统里再修（见 §3.6 回滚）。

### 4.2 Limine / UKI 坏

见 §3.6「Limine 本体损坏」。三板斧：手编 limine.conf → 拷回 BOOTX64.EFI → reconfigure 全量重写。

### 4.3 LUKS header 损坏（预防 + 抢救）

header 坏 = 整盘数据不可见。**现在就该做**（在正常系统里，存到 **/data 之外的离线介质**，如 U 盘）：

```sh
sudo cryptsetup luksHeaderBackup /dev/nvme0n1p2 \
  --header-backup-file /run/media/<U盘>/luks-header-$(date +%F).img
```

抢救（header 坏后）：`sudo cryptsetup luksHeaderRestore /dev/nvme0n1p2 --header-backup-file <img>`。注意 header 与盘是一一对应的（UUID/槽位/metadata size），换盘换版本未必能用；每次动 LUKS 相关配置后重新备份。

### 4.4 /gnu 损坏（最后一招）

先试无损手段：live 环境 `btrfs scrub start -B /dev/mapper/root`（单设备无冗余，scrub 只能**发现**坏块不能修复）；`/var/guix` 坏了可对照 `ls /var/guix/profiles/` 与 store 重建符号链。真到 store 大面积损坏：

1. 官方 Guix ISO（或本仓库 `blue build-iso` 的自建 ISO，见 `docs/iso-build.md`）启动；
2. 解密挂载同 §3.1–3.2（/data 与 `@etc/*` 子卷完好保留）；
3. `guix system init /data/Projects/Config/Guix-configs/tmp/config.scm /mnt` 重建系统（存量 store 条目会复用）；
4. 新机全新安装路线见 `tools/bootstrap.sh` 与 `README.org`。

---

## 5. 禁止事项（救援现场红线条目）

- **绝不在 live 环境跑目标系统的 `activate` 脚本**——绝对路径会把 live 系统自己写坏（§3.4 方案二红字）。
- **不跑 `guix gc`**，尤其是 `-d`：`/var/guix/profiles/system-*-link` 是 gc root，旧代 UKI 的 cmdline 还引用着这些 store 路径，gc 掉任何一条都可能让某个启动项永久失效。同理**不删 `system-*-link`**。
- 不 `mkswap`/格式化 swap 分区（`169557cc-…`）：它承担休眠镜像；救援时可 `swapon` 但别动数据。
- live 环境对 `DATA/Share`（/data）只读优先——那是有唯一副本的数据；明确要救数据时再写。
- 不跑 ESP 上残留的旧 `install-limine.scm`（陈年参数，会写出错误 UKI）。
- 不在 chroot 里跑 `herd`/shepherd（没有 PID 1，必然失败或产生误导）。
- btrfs 别手滑 `balance`/`reshape`；单设备盘没有冗余可挥霍。

---

## 6. 一键脚本

`tools/rescue-chroot.sh` 把 §3.1–3.5 串成一条龙（解密 → 全子卷挂载 → rbind → 方案一拷 /etc → resolv.conf），并支持 `chroot`（store bash 自动定位 + 自动 source profile）、`umount`（逆序清理）、`status`（只读查状态）：

```sh
sudo tools/rescue-chroot.sh status            # 任意时候安全
sudo tools/rescue-chroot.sh mount /mnt        # dry-run：只打印计划
sudo tools/rescue-chroot.sh mount /mnt --go   # 真执行
sudo tools/rescue-chroot.sh chroot /mnt       # 进入（默认 dry-run 打印命令）
sudo tools/rescue-chroot.sh umount /mnt --go  # 逆序卸载并关 LUKS
```

脚本在检测到「当前就在运行中的 Guix 主机上」时会拒绝 mount/chroot（防止手滑把自己挂穿），拓扑常量硬编码在脚本顶部并标注了与 `source/information.scm` 的同步义务。
