(load "./configs/channel.scm")

(use-modules (gnu)
             (gnu home services guix)
             (gnu system nss)
             (gnu system accounts)
             (gnu services networking)
             (gnu services containers)
             (gnu services pm)

             (guix channels)

             (nonguix transformations)
             (nongnu packages firmware)
             (nongnu packages linux)
             (nongnu system linux-initrd)

             (cast packages gtklock)

             (rde packages fonts)

             (rosenthal)
             (rosenthal bootloader uki)
             (rosenthal packages networking)

             (saayix packages binaries)
             (saayix packages fonts))

(use-service-modules dbus sddm sysctl xorg)

(use-package-modules admin
                     audio
                     bash
                     bootloaders
                     compression
                     containers
                     cinnamon
                     curl
                     cryptsetup
                     fcitx5
                     fonts
                     freedesktop
                     games
                     glib
                     gnome
                     gnome-xyz
                     gnupg
                     kde-frameworks
                     image-viewers
                     linux
                     package-management
                     password-utils
                     polkit
                     python
                     qt
                     rust-apps
                     terminals
                     text-editors
                     shells
                     shellutils
                     version-control
                     wget
                     wm
                     xdisorg
                     xfce
                     xorg)

(operating-system
  (initrd microcode-initrd)
  (firmware (list linux-firmware sof-firmware))

  (kernel linux-xanmod)
  (kernel-arguments (cons* "kernel.sysrq=1" "zswap.enabled=1"
                           "zswap.max_pool_percent=90"
                           "modprobe.blacklist=amdgpu,pcspkr,hid_nintendo"
                           %default-kernel-arguments))

  (timezone "Asia/Shanghai")
  (locale "zh_CN.utf8")

  (users (cons (user-account
                 (name "brokenshine")
                 (group "users")
                 (password
                  "$6$C2H4Td9gJHEa4qFi$fN.tnh2XibU1aqHpwcq.zewxyMeHR83EyP0r8UROzjj6l88VijpOogCbVarmrlCnig8k967wT7ifcJAZunZ.l.")
                 (supplementary-groups '("cgroup" "wheel" "netdev" "audio"
                                         "video"))
                 (shell (file-append fish "/bin/fish"))) %base-user-accounts))

  (host-name "BrokenShine-Desktop")

  (bootloader (bootloader-configuration
                (bootloader uefi-uki-removable-bootloader)
                (theme (grub-theme (inherit (grub-theme))
                                   (gfxmode '("1024x786x32" "auto"))))
                (targets '("/efi"))
                (extra-initrd "/SYSTEM/Guix/@/boot/cryptroot.cpio")))

  (mapped-devices (list (mapped-device
                          (source (uuid "327f2e02-1e4f-48b2-87f0-797c481850c9"))
                          (target "root")
                          (type luks-device-mapping)
                          (arguments '(#:key-file "/cryptroot.key")))))

  (file-systems (append (list (file-system
                                (device (file-system-label "Linux"))
                                (mount-point "/")
                                (type "btrfs")
                                (options
                                 "subvol=SYSTEM/Guix/@,compress=zstd:6")
                                (dependencies mapped-devices)
                                (create-mount-point? #t))
                              (file-system
                                (device (file-system-label "Linux"))
                                (mount-point "/home")
                                (type "btrfs")
                                (options
                                 "subvol=DATA/Home/Guix,compress=zstd:6")
                                (dependencies mapped-devices)
                                (create-mount-point? #t))
                              (file-system
                                (device (file-system-label "Linux"))
                                (mount-point "/data")
                                (type "btrfs")
                                (options "subvol=DATA/Share,compress=zstd:6")
                                (dependencies mapped-devices)
                                (create-mount-point? #t))
                              (file-system
                                (device (file-system-label "Linux"))
                                (mount-point "/var/lib/flatpak")
                                (type "btrfs")
                                (options "subvol=DATA/Flatpak,compress=zstd:6")
                                (dependencies mapped-devices)
                                (create-mount-point? #t))
                              (file-system
                                (device (uuid "9699-52A2"
                                              'fat))
                                (mount-point "/efi")
                                (type "vfat")
                                (create-mount-point? #t)))

                        %base-file-systems))

  (packages (append (list glib
                          gtklock
                          gvfs
                          light
                          niri
                          swayidle
                          wl-clipboard
                          xdg-desktop-portal
                          xdg-desktop-portal-gnome
                          xdg-desktop-portal-gtk
                          xwayland-satellite

                          easyeffects
                          file-roller
                          kvantum
                          nomacs
                          qt5ct
                          qt6ct
                          thunar
                          thunar-archive-plugin
                          thunar-media-tags-plugin
                          thunar-volman
                          libsecret
                          pipewire
                          polkit-gnome
                          wireplumber
                          xdg-user-dirs

                          font-awesome
                          font-google-noto-emoji
                          font-iosevka-nerd
                          font-nerd-noto
                          font-sarasa-gothic

                          bibata-cursor-theme
                          gsettings-desktop-schemas
                          orchis-theme
                          papirus-icon-theme

                          bat
                          btop
                          direnv
                          distrobox
                          eza
                          fastfetch
                          fish
                          foot
                          fzf
                          helix
                          mihomo
                          starship
                          zoxide

                          curl
                          cryptsetup
                          flatpak
                          git
                          gzip
                          podman
                          podman-compose
                          python
                          unzip
                          wget) %base-packages))

  (services
   (append (list (service nftables-service-type)
                 (service tlp-service-type)

                 (service sddm-service-type
                          (sddm-configuration (auto-login-user "brokenshine")
                                              (auto-login-session
                                               "niri.desktop")))
                 (service screen-locker-service-type
                          (screen-locker-configuration (name "gtklock")
                                                       (program (file-append
                                                                 gtklock
                                                                 "/bin/gtklock"))
                                                       (allow-empty-password?
                                                                              #f)))

                 (service rootless-podman-service-type
                          (rootless-podman-configuration (subuids (list (subid-range
                                                                         (name
                                                                          "brokenshine")
                                                                         (start
                                                                          100000)
                                                                         (count
                                                                          65536))))
                                                         (subgids (list (subid-range
                                                                         (name
                                                                          "brokenshine")
                                                                         (start
                                                                          100000)
                                                                         (count
                                                                          65536))))))
                 (simple-service 'extend-kernel-module-loader
                                 kernel-module-loader-service-type
                                 '("sch_fq_pie" "tcp_bbr"))

                 (simple-service 'extend-sysctl sysctl-service-type
                                 '(("fs.inotify.max_user_watches" . "524288")

                                   ("vm.max_map_count" . "2147483642")
                                   ("vm.compaction_proactiveness" . "0")
                                   ("vm.vfs_cache_pressure" . "50")
                                   ("vm.page_lock_unfairness" . "1")
                                   ("vm.stat_interval" . "120")

                                   ("net.core.default_qdisc" . "fq_pie")
                                   ("net.core.rmem_max" . "7500000")
                                   ("net.core.wmem_max" . "7500000")
                                   ("net.ipv4.tcp_congestion_control" . "bbr")
                                   ("net.ipv4.tcp_low_latency" . "1")
                                   ("net.ipv4.tcp_fastopen" . "3")

                                   ("kernel.numa_balancing" . "0")
                                   ("kernel.sched_autogroup_enabled" . "1")
                                   ("kernel.sched_child_runs_first" . "0")))

                 (simple-service 'home-channels home-channels-service-type
                                 guix-channels)

                 (simple-service 'mihomo-daemon shepherd-root-service-type
                                 (list (shepherd-service (documentation
                                                          "Run the mihomo daemon.")
                                                         (provision '(mihomo-daemon))
                                                         (requirement '(user-processes))
                                                         (start #~(make-forkexec-constructor
                                                                   (list #$(file-append
                                                                            mihomo
                                                                            "/bin/mihomo")
                                                                    "-f"
                                                                    "/home/brokenshine/.config/mihomo/config.yaml")
                                                                   #:log-file
                                                                   "/var/log/mihomo.log"))
                                                         (stop #~(make-kill-destructor))
                                                         (respawn? #t))))

                 (service pam-limits-service-type
                          (list (pam-limits-entry "@realtime"
                                                  'both
                                                  'rtprio 99)
                                (pam-limits-entry "@realtime"
                                                  'both
                                                  'memlock
                                                  'unlimited))))

           (modify-services %desktop-services
             (delete gdm-service-type)
             (udev-service-type config =>
                                (udev-configuration (inherit config)
                                                    (rules (append (udev-configuration-rules
                                                                    config)
                                                                   (list
                                                                    steam-devices-udev-rules
                                                                    (plain-file
                                                                     "99-sayodevice.rules"
                                                                     "KERNEL==\"hidraw*\" , ATTRS{idVendor}==\"8089\" , MODE=\"0666\""))))))
             (guix-service-type config =>
                                (guix-configuration (inherit config)
                                                    (channels guix-channels)
                                                    (guix (guix-for-channels
                                                           guix-channels))
                                                    (substitute-urls (append (list
                                                                              "https://mirror.sjtu.edu.cn/guix"
                                                                              "https://cache-cdn.guix.moe"
                                                                              "https://substitutes.nonguix.org")
                                                                      %default-substitute-urls))
                                                    (authorized-keys (append (list
                                                                              (plain-file
                                                                               "guix-moe.pub"
                                                                               "(public-key (ecc (curve Ed25519) (q #552F670D5005D7EB6ACF05284A1066E52156B51D75DE3EBD3030CD046675D543#)))")

                                                                              
                                                                              (plain-file
                                                                               "nonguix.pub"
                                                                               "(public-key (ecc (curve Ed25519)(q #C1FD53E5D4CE971933EC50C9F307AE2171A2D3B52C804642A7A35F84F3A4EA98#)))"))
                                                                      %default-authorized-guix-keys))
                                                    (discover? #f))))))

  (name-service-switch %mdns-host-lookup-nss))
