;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT
;;;
;;; RedmiBook Pro 16 2024 内核配置（Intel Meteor Lake 平台）
;;;
;;; 硬件事实（2026-09 实机采集，裁剪依据）：
;;;   CPU    Core Ultra 7 155H（Meteor Lake，16C22T）
;;;   GPU    Arc 核显（i915 主用，xe 备）+ NPU（intel_vpu）
;;;   WiFi   AX211 CNVi（iwlwifi+iwlmvm）/ BT 8087:0033（btusb）
;;;   音频   SOF-MTL 拓扑 + Realtek ALC256 + DMIC（无独立功放）
;;;   触摸板 GXTP7300（i2c-hid + hid-multitouch）
;;;   指纹   Goodix 27c6:689a（USB，用户态 libfprint，无需内核驱动）
;;;   摄像头 USB UVC（内摄+外接均走 UVC，无 MIPI IPU）
;;;   存储   YMTC PC300 NVMe / TPM 2.0 CRB / TBT4 + USB4
;;;   扩展   USB 转接坞 AX88179 千兆网（cdc_ncm）
;;;
;;; 两段式：钉住本机硬件（防上游 defconfig 漂移）+ 大类裁剪
;;; （redmibook-trim.kconfig，裸符号=反选），拼合导出单一
;;; %machine-configs，由 linux-cachyos-lts.scm 与通用桌面档组装。
;;; 换设备：新建 machines/<设备>.scm（导出同名 %machine-configs）
;;; + <设备>-trim.kconfig，改 linux-cachyos-lts.scm 里一行 load。

(use-modules (ice-9 rdelim)
             (ice-9 textual-ports)
             (srfi srfi-1))

;; —— 本机硬件钉住 ——
(define %machine-pin-configs
  (list
   ;; 处理器：本机即目标机，-march=native（CachyOS 补丁符号）；
   ;; 选 native 后基线 ISA 档位符号不可见，连带反选
   "CONFIG_GENERIC_CPU"
   "CONFIG_MZEN4"
   "CONFIG_X86_NATIVE_CPU=y"
   "CONFIG_X86_64_VERSION"

   ;; 无线/蓝牙（CNVi）
   "CONFIG_IWLWIFI=m"
   "CONFIG_IWLMVM=m"
   "CONFIG_BT=m"
   "CONFIG_BT_HCIBTUSB=m"

   ;; 显示/GPU/NPU
   "CONFIG_DRM_I915=m"
   "CONFIG_DRM_XE=m"
   "CONFIG_DRM_ACCEL_IVPU=m"

   ;; 音频：SOF Meteor Lake + HDA codec 路径
   "CONFIG_SND_HDA_INTEL=m"
   "CONFIG_SND_HDA_CODEC_REALTEK=m"
   "CONFIG_SND_HDA_CODEC_HDMI=m"
   "CONFIG_SND_SOC_SOF_PCI=m"
   "CONFIG_SND_SOC_SOF_INTEL_TOPLEVEL=y"
   ;; 注意带 INTEL 前缀：mach 符号位于 SND_SOC_INTEL_ 命名空间，
   ;; 漏写前缀会变成不存在的符号，verify-config 报 mismatch
   "CONFIG_SND_SOC_INTEL_SKL_HDA_DSP_GENERIC_MACH=m"

   ;; 摄像头 / 输入（HID_APPLE 的 =m 已由 linux-cachyos-lts.scm 通用档
   ;; 的 initrd 符号钉住，此处不再重复列出）
   "CONFIG_USB_VIDEO_CLASS=m"
   "CONFIG_I2C_HID_ACPI=m"
   "CONFIG_HID_MULTITOUCH=m"

   ;; BIOS SPI NOR flash（/dev/mtd0-3，固件工具读写；曾在连带
   ;; 裁剪中被误判为孤儿，此为 default-y 翻转型受害者，显式钉住）
   "CONFIG_MTD_SPI_NOR=m"

   ;; 平台外设
   "CONFIG_I2C_I801=m"
   "CONFIG_SPI_INTEL_PCI=m"
   "CONFIG_PINCTRL_METEORLAKE=m"
   "CONFIG_INTEL_ISH_HID=m"
   "CONFIG_INTEL_MEI_ME=m"
   "CONFIG_INTEL_VSEC=m"
   "CONFIG_INTEL_PMC_CORE=m"
   ;; 6.18 起 THUNDERBOLT 符号已并入 USB4（模块名仍叫 thunderbolt），
   ;; 钉 USB4=m 即可，THUNDERBOLT 行会让 verify-config 报不存在符号
   "CONFIG_USB4=m"
   "CONFIG_TYPEC_UCSI=m"

   ;; USB 转接坞千兆网（defconfig 默认 m，此处显式钉住）
   "CONFIG_USB_NET_CDC_NCM=m"))

;; —— 大类裁剪：读同目录 kconfig 片段（裸符号=反选）——
;; 与 defconfig 同构、diff 友好；依赖不满足的连带符号若遗漏，
;; 构建期 verify-config 会点名报错，按提示补列即可。
(define %machine-trim-configs
  (filter (lambda (line) (not (string-null? line)))
          (string-split
           (call-with-input-file
               (string-append (dirname (current-filename))
                              "/redmibook-trim.kconfig")
             get-string-all)
           #\newline)))

;; —— 本机片段：钉住在前、裁剪在后（同键后者胜，钉住优先）——
(define %machine-configs
  (append %machine-pin-configs %machine-trim-configs))
