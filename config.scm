(load "./configs/channel.scm")

(use-modules (gnu)
             (gnu home services guix)
             (gnu system nss)
             (gnu system accounts)

             (guix channels)

             (nonguix transformations)
             (nongnu packages firmware)
             (nongnu packages linux)
             (nongnu system linux-initrd)

             (cast packages gtklock)

             (jeans packages fonts)

             (px packages document)
             (px packages tpm)

             (radix packages freedesktop)

             (rde packages fonts)

             (rosenthal)
             (rosenthal bootloader uki)
             (rosenthal packages networking)
             (rosenthal packages rust-apps)

             (saayix packages binaries)
             (saayix packages fonts))

(use-service-modules authentication
                     containers
                     dbus
                     linux
                     networking
                     pm
                     sddm
                     syncthing
                     sysctl
                     xorg)

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
                     hardware
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
                     syncthing
                     version-control
                     wget
                     wm
                     xdisorg
                     xfce
                     xorg)

(operating-system
  (initrd microcode-initrd)
  (firmware (list linux-firmware sof-firmware bluez-firmware))

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
                                   (gfxmode '("1024x786x32"))))
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

  (packages (append (list ;Desktop
                          bluez
                          brightnessctl
                          glib
                          gnome-keyring
                          gsettings-desktop-schemas
                          gtklock
                          gvfs
                          libnotify
                          niri
                          swayidle
                          swww
                          waybar
                          wl-clipboard
                          xdg-desktop-portal
                          xdg-desktop-portal-gnome
                          xdg-desktop-portal-gtk
                          xdg-dbus-proxy
                          xdg-utils
                          xdg-terminal-exec
                          xwayland-satellite

                          ;; Essential
                          dconf-editor
                          easyeffects
                          exo
                          file-roller
                          kvantum
                          libgnome-keyring
                          libsecret
                          pipewire
                          polkit-gnome
                          qt5ct
                          qt6ct
                          qtsvg
                          thunar
                          thunar-archive-plugin
                          thunar-media-tags-plugin
                          thunar-volman
                          wireplumber
                          xdg-user-dirs

                          ;; Fonts
                          font-awesome
                          font-google-noto-emoji
                          font-iosevka-nerd
                          font-maple-font-nf-cn
                          font-nerd-noto
                          font-sarasa-gothic

                          ;; Terminal
                          bat
                          btop
                          distrobox
                          eza
                          fastfetch
                          fish
                          foot
                          fzf
                          helix
                          mihomo
                          starship

                          ;; System
                          bluez
                          curl
                          cryptsetup
                          flatpak
                          flatpak-xdg-utils
                          git
                          git-filter-repo
                          git-lfs
                          gzip
                          pinentry
                          podman
                          podman-compose
                          python
                          tpm2-abrmd
                          tpm2-pkcs11
                          tpm2-tools
                          tpm2-tss
                          unzip
                          wget) %base-packages))

  (services
   (append (list (service fprintd-service-type)
                 (service gnome-keyring-service-type)
                 (service tlp-service-type)

                 (service kmscon-service-type
                          (kmscon-configuration (virtual-terminal "tty2")
                                                (font-engine "unifont")
                                                (font-size 26)))

                 (service nftables-service-type
                          (nftables-configuration (ruleset (plain-file
                                                            "nftables.conf"
                                                            "flush ruleset
                                table inet filter {
                                  chain input {
                                    type filter hook input priority 0; policy drop;
                                    ct state established,related accept
                                    iif lo accept
                                    tcp dport 22 accept   # SSH
                                    tcp dport 22000 accept  # Syncthing 同步端口
                                    udp dport 21027 accept  # Syncthing 本地发现
                                    # 可以添加其他需要的规则
                                  }
                                  chain forward {
                                    type filter hook forward priority 0; policy drop;
                                  }

                                  chain output {
                                    type filter hook output priority 0; policy accept;
                                  }
                                }"))))

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

                 (service screen-locker-service-type
                          (screen-locker-configuration (name "gtklock")
                                                       (program (file-append
                                                                 gtklock
                                                                 "/bin/gtklock"))
                                                       (allow-empty-password?
                                                                              #f)))

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

           (modify-services %rosenthal-desktop-services
             (delete console-font-service-type)
             (guix-service-type config =>
                                (guix-configuration (inherit config)
                                                    (channels guix-channels)
                                                    (guix (guix-for-channels
                                                           guix-channels))
                                                    (substitute-urls (append (list
                                                                              ;; "https://mirror.sjtu.edu.cn/guix"
                                                                              "https://cache-cdn.guix.moe"
                                                                              "https://substitutes.nonguix.org"
                                                                              "https://substitutes.guix.gofranz.com")
                                                                      %default-substitute-urls))
                                                    (authorized-keys (append (list
                                                                              (plain-file
                                                                               "guix-moe.pub"
                                                                               "(public-key (ecc (curve Ed25519) (q #552F670D5005D7EB6ACF05284A1066E52156B51D75DE3EBD3030CD046675D543#)))")

                                                                              
                                                                              (plain-file
                                                                               "nonguix.pub"
                                                                               "(public-key (ecc (curve Ed25519) (q #C1FD53E5D4CE971933EC50C9F307AE2171A2D3B52C804642A7A35F84F3A4EA98#)))")

                                                                              
                                                                              (plain-file
                                                                               "panther.pub"
                                                                               "(public-key (ecc (curve Ed25519) (q #0096373009D945F86C75DFE96FC2D21E2F82BA8264CB69180AA4F9D3C45BAA47#)))"))
                                                                      %default-authorized-guix-keys))
                                                    (discover? #f)))

             (udev-service-type config =>
                                (udev-configuration (inherit config)
                                                    (rules (append (udev-configuration-rules
                                                                    config)
                                                                   (list
                                                                    steam-devices-udev-rules
                                                                    (plain-file
                                                                     "99-sayodevice.rules"
                                                                     "KERNEL==\"hidraw*\" , ATTRS{idVendor}==\"8089\" , MODE=\"0666\""))))))

             (greetd-service-type config =>
                                  (greetd-configuration (terminals (list (greetd-terminal-configuration
                                                                          (terminal-vt
                                                                           "7")
                                                                          (terminal-switch
                                                                           #t)
                                                                          (default-session-command
                                                                           (greetd-user-session
                                                                            (command
                                                                             (file-append
                                                                              tuigreet
                                                                              "/bin/tuigreet"))
                                                                            (command-args '
                                                                             ("--time"
                                                                              "--time-format '%Y-%m-%d %l:%M:%S'"
                                                                              "--remember"
                                                                              "--cmd"
                                                                              "dbus-run-session niri --session"))))
                                                                          ;; 如果你还想要 autologin
                                                                          (initial-session-user
                                                                           "brokenshine") ;改成你的用户名
                                                                          (initial-session-command
                                                                           "dbus-run-session niri --session")))))))))

  (name-service-switch %mdns-host-lookup-nss))
