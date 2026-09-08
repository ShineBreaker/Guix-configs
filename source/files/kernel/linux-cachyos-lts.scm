;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT
;;;
;;; linux-cachyos-lts —— CachyOS LTS 裁剪内核，本目录即配置全集
;;;
;;; CachyOS 官方预拼补丁的 6.18 LTS tarball（Cachy Sauce + EEVDF）为源，
;;; nonguix linux-6.18 出构建配方，customize-linux 换源换配置；defconfig
;;; 用 Testament 作者 hako 的 kernel-config defconfig_server（钉 49c98a1）。
;;; config.org 只 load 本文件一行，三条维护路径：
;;;
;;;   升级  只改下方 %cachyos-lts-version 与 origin 里的 base32 两处
;;;   换机  新建 machines/<设备>.scm（导出 %machine-configs）+ 改下方 load 一行
;;;   调优  改通用档或 machines/ 侧；符号与 defconfig 漂移冲突由构建期
;;;         verify-config 点名报错，按提示补删清单行即可收敛
;;;
;;; 目录构成：linux-cachyos-lts.scm（本文件，包定义 + 通用桌面档）、
;;; defconfig-cachyos-lts（pristine，永不手改）、machines/<设备>.scm
;;; + <设备>-trim.kconfig（钉住与裁剪，硬件事实写在 machine 文件头）。

;; —— 当前设备（换机改这一行）——
(load (string-append (dirname (current-filename))
                     "/machines/redmibook-pro-16-2024.scm"))

;; —— 版本与源（升级只改 %cachyos-lts-version 与 base32）——
(define %cachyos-lts-version "6.18.48-2")

(define %cachyos-lts-origin
  (origin
   (method url-fetch)
   (uri (string-append
         "https://github.com/CachyOS/linux/releases/download/cachyos-"
         %cachyos-lts-version "/cachyos-" %cachyos-lts-version ".tar.gz"))
   ;; 不用 (sha256 …) 兼容写法也不用 (content-hash bv sha256)：两者都靠
   ;; syntax-case 的 sha256 字面量匹配，而本模块作用域里 (gcrypt hash) 的
   ;; 同名绑定会让匹配失效；字符串单参形式的默认算法经卫生展开引入
   ;; sha256，不受遮蔽影响
   (hash (content-hash
          "1ayb463hzqdfflvk4b3w2bqqnw9k7xl6rx6yx9hp2a9lhja8py4z"))))

;; —— 通用桌面档（与设备无关，与 hako defconfig 强耦合）——
(define %kernel-common-configs
  (list
   ;; —— default-y 门控钉住 ——
   ;; hako defconfig 是最小化的（savedefconfig 风格），default y 的
   ;; menuconfig 门控不在其中；conf --defconfig 求值时这些门控会被翻成
   ;; n，连锁屠掉整个子树（网络设备/无线/以太网/IIO 传感器/静态键），
   ;; 且翻转与否取决于其余输入的组合，无单行可循。必须显式钉住。
   "CONFIG_NETDEVICES=y"
   "CONFIG_WLAN=y"
   "CONFIG_ETHERNET=y"
   "CONFIG_IIO=y"
   "CONFIG_JUMP_LABEL=y"
   "CONFIG_MPLS=y"
   "CONFIG_NET_SWITCHDEV=y"
   ;; 连带钉住：门控翻 n 时被拖走的 default-y 子项
   "CONFIG_FAILOVER=y"
   "CONFIG_USB_WDM=m"
   "CONFIG_MAC80211_LEDS=y"
   "CONFIG_PAGE_POOL_STATS=y"
   "CONFIG_FONT_8x16=y"

   ;; —— Cachy Sauce（server defconfig 默认关，桌面档打开）——
   "CONFIG_CACHY=y"

   ;; —— 桌面档优化（2026-09-08 QEMU KVM 消融验证，方法见
   ;; kernel/AGENTS.md「消融实验」节，数据 /var/tmp/kopt/results/）——
   ;; 桌面不需要调度统计与调度 tracer；SCHED_INFO 是无 prompt 的
   ;; 隐式符号（被 select 锁定），反选会被 verify-config 拦截，保持 y
   "CONFIG_SCHEDSTATS"
   "CONFIG_SCHED_TRACER"
   ;; 反选 hako defconfig 的 MAXSMP（发行档通用性遗留）：它把 NR_CPUS
   ;; range 钉死 [8192,8192]，连带 CPUMASK_OFFSTACK=y（堆分配位图）与
   ;; NODES_SHIFT=10；反选后位图回栈上操作，调度热路径受益（消融 fork
   ;; +1.7%/syscall +4.6%）。任何 ≤512 CPU 的桌面机通用；NR_CPUS 的
   ;; 具体值与单节点 numa balancing 关默认属设备拓扑事实，在 machine 层
   "CONFIG_MAXSMP"

   ;; —— 1000Hz + idle dynticks（NO_HZ_FULL 对重编译型负载有上下文跟踪开销）——
   "CONFIG_HZ_300"
   "CONFIG_HZ_1000=y"
   "CONFIG_HZ=1000"
   "CONFIG_HZ_PERIODIC"
   "CONFIG_NO_HZ_FULL"
   "CONFIG_NO_HZ_IDLE=y"
   "CONFIG_NO_HZ=y"
   "CONFIG_NO_HZ_COMMON=y"
   ;; RCU_LAZY 依赖 RCU_NOCB_CPU（其默认仅在 NO_HZ_FULL 下为 y），
   ;; 改 idle dynticks 后连带失效，显式反选
   "CONFIG_RCU_LAZY"
   "CONFIG_RCU_LAZY_DEFAULT_OFF"

   ;; —— 动态抢占，默认 full（启动参数可切 none/voluntary/lazy）——
   "CONFIG_PREEMPT_DYNAMIC=y"
   "CONFIG_PREEMPT=y"
   "CONFIG_PREEMPT_VOLUNTARY"
   "CONFIG_PREEMPT_LAZY"
   "CONFIG_PREEMPT_NONE"

   ;; —— -O3 ——
   "CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE"
   "CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE_O3=y"

   ;; —— BBR 默认拥塞控制 + fq 队列（内核模块服务即为此加载）——
   "CONFIG_DEFAULT_CUBIC"
   "CONFIG_DEFAULT_BBR=y"
   "CONFIG_DEFAULT_TCP_CONG=\"bbr\""

   ;; —— THP always ——
   "CONFIG_TRANSPARENT_HUGEPAGE_MADVISE"
   "CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS=y"

   ;; —— Guix 基建 ——
   ;; 构建沙箱依赖用户命名空间
   "CONFIG_USER_NS=y"
   ;; 编译提速最大头：反选 debuginfo 全家（DWARF5/BTF/GDB 脚本）。
   ;; BTF 关闭的连带牺牲（均硬依赖 DEBUG_INFO_BTF）：sched_ext(e6)
   ;; 调度器类与 BPF qdisc
   "CONFIG_DEBUG_INFO"
   "CONFIG_DEBUG_INFO_DWARF5"
   "CONFIG_DEBUG_INFO_BTF"
   "CONFIG_GDB_SCRIPTS"
   "CONFIG_SCHED_CLASS_EXT"
   "CONFIG_NET_SCH_BPF"

   ;; —— 通用桌面模块需求（防上游 defconfig 漂移）——
   ;; libvirt/podman 网络与嵌套虚拟化；游戏 ntsync；OBS v4l2loopback
   ;; 需 uinput；蓝牙键盘鼠标需 uhid
   "CONFIG_KVM_INTEL=m"
   "CONFIG_NTSYNC=m"
   "CONFIG_INPUT_UINPUT=m"

   ;; —— initrd 必需符号（%default-initrd-modules 全套）——
   "CONFIG_NLS_ISO8859_1=m"
   "CONFIG_CRYPTO_SERPENT=m"
   "CONFIG_CRYPTO_WP512=m"
   "CONFIG_DM_CRYPT=m"
   "CONFIG_BLK_DEV_NVME=m"
   "CONFIG_MMC_BLOCK=m"
   "CONFIG_SATA_AHCI=m"
   "CONFIG_USB_STORAGE=m"
   "CONFIG_USB_UAS=m"
   "CONFIG_PATA_ACPI=m"
   "CONFIG_PATA_ATIIXP=m"
   "CONFIG_SCSI_ISCI=m"
   "CONFIG_HW_RANDOM_VIRTIO=m"
   "CONFIG_SCSI_VIRTIO=m"
   "CONFIG_VIRTIO_BALLOON=m"
   "CONFIG_VIRTIO_BLK=m"
   "CONFIG_VIRTIO_CONSOLE=m"
   "CONFIG_VIRTIO_MMIO=m"
   "CONFIG_VIRTIO_NET=m"
   "CONFIG_VIRTIO_PCI=m"
   "CONFIG_HID_GENERIC=m"
   "CONFIG_USB_HID=m"
   "CONFIG_HID_APPLE=m"))

;; —— 组装 ——
;; 钉住在前、裁剪在后：modify-defconfig 同键后者胜，钉住优先于反选。
;; hako defconfig 是发行档级硬件底座（BTRFS=y、NLS、NTSYNC、IWLWIFI、
;; I915+XE、SOF 音频、KVM、VIRTIO）
(define linux-cachyos-lts
  (let ([kernel
         (customize-linux
          #:name "linux-cachyos-lts"
          #:linux linux-6.18
          #:source %cachyos-lts-origin
          #:defconfig (local-file
                       (string-append (dirname (current-filename))
                                      "/defconfig-cachyos-lts"))
          #:configs (append %kernel-common-configs %machine-configs))])
    (package
     (inherit kernel)
     (version %cachyos-lts-version))))
