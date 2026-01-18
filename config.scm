;;; 主系统配置文件
;;; 该文件加载并组合所有子配置

(load "./configs/channel.scm")
(load "./configs/information.scm")

(load "./configs/system/modules.scm")
(load "./configs/system/kernel.scm")
(load "./configs/system/users.scm")
(load "./configs/system/bootloader.scm")
(load "./configs/system/filesystems.scm")
(load "./configs/system/packages.scm")
(load "./configs/system/services.scm")

(operating-system
  (initrd %initrd-config)
  (firmware %firmware-config)
  (kernel %kernel-config)
  (kernel-arguments %kernel-arguments-config)

  (timezone %timezone-config)
  (locale %locale-config)
  (host-name %host-name-config)

  (users %users-config)

  (bootloader %bootloader-config)

  (mapped-devices %mapped-devices-config)
  (file-systems %file-systems-config)

  (packages %packages-config)

  (services %services-config)

  (name-service-switch %mdns-host-lookup-nss))
