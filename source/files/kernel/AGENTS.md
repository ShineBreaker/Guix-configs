# kernel/ — CachyOS LTS 裁剪内核配置全集

自包含的内核定义目录：config.org 的 `cachyos-lts-kernel` 块只一行 load `linux-cachyos-lts.scm`，版本、源、defconfig 引用、通用桌面档、设备拼合**全部在本目录内维护**（架构取舍见 config.org「CachyOS LTS 内核」节，本文只讲操作）。

| 文件                               | 职责                                                                                                          |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `linux-cachyos-lts.scm`            | 包定义（`%cachyos-lts-version` + origin，**升级点**）+ 通用桌面档 `%kernel-common-configs` + 组装；导出 `linux-cachyos-lts` |
| `defconfig-cachyos-lts`            | pristine 的 hako defconfig（kernel-config @49c98a1），**永不手改**，只随上游 commit 整体替换                    |
| `machines/<设备>.scm`              | 设备层：硬件钉住 + trim 读取，导出单一 `%machine-configs`；文件头是实机采集的硬件事实（裁剪依据）                |
| `machines/<设备>-trim.kconfig`     | 大类裁剪清单（~2000 行）：**裸符号 = 反选**，`# —— 组名 ——` 分组注释，与 defconfig 同构、diff 友好               |

configs 拼合顺序：通用档 → 钉住 → 裁剪。modify-defconfig **同键后者胜**，钉住优先于反选；同一符号跨层重复出现会触发 "duplicate configurations" 构建错误。

## 维护路径

**升级**（CachyOS 出新版，最常见）：

```bash
# 1. 改 linux-cachyos-lts.scm 的 %cachyos-lts-version 与 origin base32 两处
guix hash <cachyos-新版本.tar.gz>          # 取 base32
# 2. defconfig 与片段通常不动；跑下方验证流程即可
# 3. 若 hako defconfig 也更新：整体替换 defconfig-cachyos-lts 后做对拍复验，diff 核对 trim 清单
```

注意 origin hash 必须用字符串单参 `(content-hash "...")` 形式——`(sha256 …)` 兼容写法在本模块作用域被 `(gcrypt hash)` 遮蔽失效。

**换机**：采集硬件事实（`lspci -nnk`、`lsusb`、`lsmod`、`cat /proc/asound/cards`、`ls /dev/mtd*`）写进新 `machines/<设备>.scm` 文件头 → 钉住本机硬件（`=m`/`=y`）+ 生成 `<设备>-trim.kconfig`（从 defconfig 符号全集挑非本机大类反选；生成器脚本未入库，参考现有清单的分组结构）→ 改 `linux-cachyos-lts.scm` 的 load 行 → 验证流程。

**调优**：通用偏好改通用档，设备相关改 machine 层；`CONFIG_USER_NS=y`（Guix 构建沙箱）与下方 critical 各符号不可裁。

## 验证流程（改任何 kconfig 后必做）

```bash
blue check                                            # 括号平衡
blue --dry-run rebuild                                # tangle 验证（不加载 scheme 求值）
# 真实构建（verify-config 硬校验在 configure 末尾，失败保留构建树）：
cat > /var/tmp/kernel-probe.scm <<'EOF'
(begin
  (chdir "/home/brokenshine/Projects/Config/Guix-configs/tmp")
  (set! %load-path (cons "." %load-path))
  (primitive-load "/home/brokenshine/Projects/Config/Guix-configs/tmp/config.scm")
  linux-cachyos-lts)
EOF
guix time-machine -C source/channel.lock -- build -f /var/tmp/kernel-probe.scm
```

verify-config 失败会逐条点名 mismatch 符号，按提示补删 trim/pin 行迭代收敛（通常 2-3 轮）。失败树在 `/var/tmp/guix-build-linux-cachyos-lts-*.drv-0`，树内 `make ARCH=x86_64 guix_defconfig` 可分钟级复现 configure，无需整链重跑。probe 依赖 `tmp/config.scm` 先经 tangle 生成——probe 报「加载失败：没有那个文件或目录」多半是 `tmp/` 被清（先跑 `blue --dry-run rebuild` 重建）。最后提醒用户手动 `blue rebuild`（agent 禁跑）。

## 裁剪方法论与坑

<critical>
1. **default-y 门控翻 n**：hako defconfig 是 savedefconfig 风格最小化文件，default-y 的 menuconfig 门控（NETDEVICES/WLAN/ETHERNET/IIO/JUMP_LABEL/MPLS/NET_SWITCHDEV）不在其中；conf --defconfig 求值时会被翻成 n 并**连锁屠掉整个子树**（IWLWIFI/TUN/MACVLAN 全消失）。门控钉住在通用档头部，**裁剪时不可删**。翻转取决于其余输入的组合（组合杀伤）：符号消失时单行二分无效，须逐组消元定位
2. **符号三态**：用户可见符号才可裁；select 隐式符号裁不掉（无 prompt，如 SCHED_INFO——反选会被 verify-config 拦截，2026-09-08 实证）；依赖不满足时写 n 只产生 warning "symbol value 'n' invalid"（int/bool 型如 X86_64_VERSION、IP_VS_TAB_BITS），无害可留
3. **6.18 符号改名**：THUNDERBOLT 已并入 USB4（模块名仍叫 thunderbolt）；SND_SOC mach 符号在 SND_SOC_INTEL_ 命名空间，漏 INTEL 前缀 = 不存在的符号
4. **本机不可裁**：CONFIG_MTD_SPI_NOR=m（BIOS flash，/dev/mtd0-3 在用）；initrd 必需符号全套（通用档尾部，对应 %default-initrd-modules）
5. **MAXSMP 锁死 NR_CPUS**：hako defconfig 带 `CONFIG_MAXSMP=y`（发行档通用性遗留），它 select CPUMASK_OFFSTACK，后者把 NR_CPUS range 压成 [8192,8192] 并隐藏 prompt——直接写 `CONFIG_NR_CPUS=64` 会被 conf 夹回 8192、verify-config 报 mismatch；必须先反选 MAXSMP 再设 NR_CPUS（通用档已做，连带收益：cpumask 回栈上位图、NODES_SHIFT 10→6）
</critical>

## 消融实验（性能改动定去留的测量法）

2026-09-08 定型的方法论，产物在 `/var/tmp/kopt/`（脚本可复用：`run-vm.sh`/`parse-log.sh`/`bench-variant.sh`/`compare.py`，数据 `results/*.tsv`）：

- **变体构建**：写 `/var/tmp/variant-<名>.scm`（load 仓库 kernel scm，configs 追加 %delta），`guix time-machine -C source/channel.lock -- build -K -f` 全量构建保证与基线工具链一致。**退出码别被 `| tail` 吃掉**（重定向到日志文件再取 exit）
- **QEMU 测量**：`guix pack -RR busybox stress-ng` 做 initramfs，无盘直跑（无需 virtio）；`-cpu host -smp 12 -m 8G`。**QEMU 必须 `taskset -c 0-11` pin 到 P 核**——155H P/E 混合架构下 vCPU 线程漂移是最大噪声源（不 pin 时两轮偏差可达 7-18%，pin 后多数项 <4%）
- **initramfs 两坑**：pack `-R` 的 `*R` 副本在 guest 里执行必崩（busybox run.c:692 断言）——重建 `bin/` 真目录直链**原始** store 项；guest init 的 shebang 用 pack 内 bash-static 绝对路径（busybox ash 作 PID1 读脚本会触发同款断言）
- **判定规则**：每变体两轮 VM（各 3 次取中位），变化超出 CTRL 双轮噪声带才算信号；`--cpu` 项作负对照（应恒 ≈0%）；stress-ng 高噪声项（hrtimers/timer）解读放宽
- **cmdline 类改动**（如 mitigations）：EXTRA_CMDLINE 环境变量注入 run-vm.sh，同 bzImage A/B；`/sys/devices/system/cpu/vulnerabilities/*` 输出验证生效
- 已有结论（2026-09-08）：numa_balancing 关（无倒退）、schedstats/tracer 关（中性）、MAXSMP 反选+NR_CPUS=64（fork +1.7%/syscall +4.6%）已落地——**分层放置**：schedstats/tracer/MAXSMP 在通用档（设备无关偏好与发行档遗留修正），numa_balancing/NR_CPUS 在 machine 层（单节点拓扑与 22 线程是设备事实）；BORE 6.8.0 补丁 pipe -7.7% 不采纳；spectre_bhi=off 在 MTL（BHI_DIS_S 硬件缓解）无收益，cmdline 不动

## 对拍复验（换 defconfig / 大改 / 重构后）

基线与脚本存 `/var/tmp/kernel-baseline/`（跨重启保留，丢了可按下法重建）：

- **配置层**：运行内核 `zcat /proc/config.gz` 对比新产物 `.config`，统计 y/m 三态差集
- **运行层**：`lsmod` 对产物 `.ko` 清单（`find <产物>/lib/modules -name '*.ko*'`）——**模块文件名用连字符（snd-hda-intel.ko）而 lsmod 显示下划线，必须归一化再比**，否则误报百级假缺失
- lsmod "Used by" 只显计数不列名时，`/sys/module/<m>/holders/` 是真依赖判据（空 = 自动加载残留，可裁）
- **不动内容的重构**：记「合并后 guix_defconfig + 最终 .config」双 md5 基线，重构后复刻对比，逐字节一致 = 语义零变化
