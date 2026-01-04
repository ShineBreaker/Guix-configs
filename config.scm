(load "./configs/channel.scm")
(load "./configs/home-config.scm")

(use-modules (gnu)
             (gnu system nss)
             (gnu system accounts)
             (gnu services networking)
             (gnu services containers)

             (guix channels)

             (nonguix transformations)
             (nongnu packages linux)
             (nongnu packages firmware)
             (nongnu system linux-initrd)

             (rosenthal)
             (rosenthal bootloader grub)
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
                     gnome
                     gnome-xyz
                     image-viewers
                     linux
                     lxqt
                     package-management
                     password-utils
                     polkit
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
                     xorg)

(operating-system
  (kernel linux-xanmod)
  (initrd microcode-initrd)
  (firmware (list linux-firmware))

  (timezone "Asia/Shanghai")
  (locale "zh_CN.utf8")

  (users (cons (user-account
                 (name "brokenshine")
                 (group "users")
                 (password
                  "$6$C2H4Td9gJHEa4qFi$fN.tnh2XibU1aqHpwcq.zewxyMeHR83EyP0r8UROzjj6l88VijpOogCbVarmrlCnig8k967wT7ifcJAZunZ.l.")
                 (supplementary-groups '("cgroup" "wheel" "netdev" "audio" "video"))
                 (shell (file-append fish "/bin/fish"))) %base-user-accounts))

  (host-name "BrokenShine-Desktop")

  (bootloader (bootloader-configuration
                (bootloader grub-efi-luks2-bootloader)
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

  (packages (append (list gvfs
                          light
                          niri
                          wl-clipboard
                          xwayland-satellite

                          easyeffects
                          file-roller
                          nemo
                          nomacs
                          qt5ct
                          qt6ct
                          kvantum

                          pipewire
                          polkit-gnome
                          wireplumber
                          xdg-user-dirs

                          font-google-noto-emoji
                          font-sarasa-gothic
                          font-nerd-fira-code

                          orchis-theme
                          papirus-icon-theme
                          bibata-cursor-theme

                          foot
                          helix
                          mihomo

                          bat
                          btop
                          curl
                          cryptsetup
                          direnv
                          distrobox
                          eza
                          fastfetch
                          fish
                          fzf
                          git
                          gzip
                          podman
                          podman-compose
                          starship
                          unzip
                          wget
                          zoxide

                          flatpak
                          plymouth) %base-packages))

  (services
   (append (list (service guix-home-service-type
                          `(("brokenshine" ,home-envs)))
                   (service nftables-service-type)
                  
                 (service rootless-podman-service-type
                                   (rootless-podman-configuration
                                     (subuids
                                      (list (subid-range
                                             (name "brokenshine")
                                             (start 100000)
                                             (count 65536))))
                                     (subgids
                                      (list (subid-range
                                             (name "brokenshine")
                                             (start 100000)
                                             (count 65536))))))

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

                 (service sddm-service-type
                          (sddm-configuration (auto-login-user "brokenshine")
                                              (auto-login-session
                                               "niri.desktop")))

                 (simple-service 'extend-sysctl sysctl-service-type
                                 '(("fs.inotify.max_user_watches" . "524288")

                                   ("vm.max_map_count" . "2147483642")
                                   ("vm.compaction_proactiveness" . "0")
                                   ("vm.vfs_cache_pressure" . "50")
                                   ("vm.page_lock_unfairness" . "1")
                                   ("vm.stat_interval" . "120")

                                   ("net.core.default_qdisc" . "fq")
                                   ("net.ipv4.tcp_congestion_control" . "bbr")
                                   ("net.ipv4.tcp_low_latency" . "1")
                                   ("net.ipv4.tcp_fastopen" . "3")

                                   ("kernel.numa_balancing" . "0")
                                   ("kernel.sched_autogroup_enabled" . "1")
                                   ("kernel.sched_child_runs_first" . "0")))

                 (service pam-limits-service-type
                          (list (pam-limits-entry "@realtime"
                                                  'both
                                                  'rtprio 99)
                                (pam-limits-entry "@realtime"
                                                  'both
                                                  'memlock
                                                  'unlimited)))

                 (simple-service 'guix-moe guix-service-type
                                 (guix-extension (authorized-keys (list (plain-file
                                                                         "guix-moe-old.pub"
                                                                         "(public-key (ecc (curve Ed25519) (q #374EC58F5F2EC0412431723AF2D527AD626B049D657B5633AAAEBC694F3E33F9#)))")
                                                                        (plain-file
                                                                         "guix-moe.pub"
                                                                         "(public-key (ecc (curve Ed25519) (q #552F670D5005D7EB6ACF05284A1066E52156B51D75DE3EBD3030CD046675D543#)))")))
                                                 (substitute-urls '("https://cache-cdn.guix.moe")))))

           (modify-services %desktop-services
             (delete gdm-service-type)

             (guix-service-type config =>
                                (guix-configuration (inherit config)
                                                    (channels guix-channels)
                                                    (guix (guix-for-channels
                                                           guix-channels))
                                                    (substitute-urls (append (list
                                                                              "https://mirror.sjtu.edu.cn/guix"
                                                                              "https://cache-cdn.guix.moe"
                                                                              "https://bordeaux.guix.gnu.org"
                                                                              "https://substitutes.nonguix.org")
                                                                      %default-substitute-urls))
                                                    (discover? #t)
                                                    (extra-options '("--cores=16")))))))

  (name-service-switch %mdns-host-lookup-nss))
