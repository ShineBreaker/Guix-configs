;;; 主系统配置文件
;;; 该文件加载并组合所有子配置

(load "./configs/channel.scm")
(load "./configs/information.scm")

(load "./configs/system/modules.scm")
(load "./configs/system/kernel.scm")
(load "./configs/system/users.scm")
(load "./configs/system/bootloader.scm")
(load "./configs/system/luks.scm")
(load "./configs/system/filesystems.scm")
(load "./configs/system/packages.scm")
(load "./configs/system/services.scm")

(operating-system
  ;; 内核和固件配置
  (initrd %initrd-config)
  (firmware %firmware-config)
  (kernel %kernel-config)
  (kernel-arguments %kernel-arguments-config)

  ;; 基本系统配置
  (timezone %timezone-config)
  (locale %locale-config)
  (host-name %host-name-config)

  ;; 用户账户配置
  (users %users-config)

  ;; 引导加载器配置
  (bootloader %bootloader-config)

  ;; LUKS 加密配置
  (mapped-devices %mapped-devices-config)

  ;; 文件系统配置
  (file-systems %file-systems-config)

  ;; 软件包配置
  (packages %packages-config)

  ;; 系统服务配置
  (services %services-config)

  (name-service-switch %mdns-host-lookup-nss))
