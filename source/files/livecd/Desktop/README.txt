Guix Rescue / Install Live
==========================

账户：live / live（sudo 可用）· root / live · sshd 已自启
tty3-6 是 root 免密 shell（Ctrl-Alt-F3 切换，Ctrl-Alt-F7 回桌面）

联网
----
托盘图标（nm-applet）点选 WiFi，或终端跑：nmtui

救砖（修复本机已装的 Guix 系统）
------------------------------
  sudo rescue-chroot.sh status          # 查看解锁/挂载状态（只读，安全）
  sudo rescue-chroot.sh mount /mnt      # 解密 LUKS + 挂全部子卷（默认 dry-run，确认后执行）
  sudo rescue-chroot.sh chroot /mnt     # 进 chroot 修系统
  sudo rescue-chroot.sh umount /mnt     # 逆序卸载
详细手册：~/Guix-configs/docs/rescue-chroot.md

装机（全新安装本仓库配置）
------------------------
  cp -r ~/Guix-configs ~/cfg            # 骨架文件只读，先复制可写副本
  # 分区/加密/挂载好目标盘到 /mnt 后：
  cd ~/cfg && ./tools/emergency-blue.sh init /mnt
  # 或跑图形化安装器：sudo guix-system-installer
手册：~/Guix-configs/docs/emergency-blue.md

常用排障
--------
  smartctl -a /dev/nvme0n1              # 磁盘健康
  btrfs check /dev/mapper/root          # Btrfs 检查（勿加 --repair 除非走投无路）
  efibootmgr -v                         # 启动项
  dmesg | less                          # 内核日志
  info guix                             # Guix 手册（离线）
