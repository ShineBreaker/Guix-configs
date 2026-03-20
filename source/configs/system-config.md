# 系统配置

此系统配置的关键在于 **让系统能够正常启动** ，所以会尽量精简软件包以及相关服务的数量

待系统成功安装并进入系统之后，则可以直接手动应用用户配置

---

## 模块

- [Main](#Main) **全配置文件的基本骨架**，建议优先查看这里的结构

- [Information](#information)
- [Modules](#modules)
- [Bootloader](#bootloader)
- [FileSystems](#filesystems)
- [Kernel](#kernel)
- [Packages](#packages)
- [Services](#services)
- [Skeletons](#skeletons)
- [Users](#users)

---

## Information

### 包含了一些系统的基本信息

```scheme
(load "../source/information.scm")
```

## Modules

### 一些通用的模块

```scheme

(use-modules (gnu)
             (gnu system accounts)
             (gnu system nss)
             (gnu system pam)

             (guix channels)
             (guix gexp)
             (guix modules)

             (ice-9 session)

             (rosenthal utils packages))
```

## Bootloader

### 在这里使用了由 `rosenthal` 频道提供的 **Limine**

```scheme

(use-modules (rosenthal bootloader limine))

(define %bootloader-config
  (bootloader-configuration
    (bootloader limine-efi-removable-bootloader)
    (targets '("/boot"))))
```

## FileSystems

这里的配置文件需要根据自己的实际情况进行修改，我目前是使用了 **LUKS + Btrfs** 的架构，同时高强度地使用subvol功能

具体的subvol配置放置在 [information.scm](../information.scm) 中，方便我直接做相应地修改

```scheme
(use-modules (ice-9 match))

(define %mapped-devices-config
  (list (mapped-device
          (source (uuid "327f2e02-1e4f-48b2-87f0-797c481850c9"))
          (target "root")
          (type luks-device-mapping))))

(define %tmpfs
  (list (file-system
          (mount-point "/")
          (device "tmpfs")
          (type "tmpfs")
          (flags '(no-atime))
          (options "mode=0755,nr_inodes=1m,size=10%")
          (check? #f))
        (file-system
          (mount-point "/tmp")
          (device "tmpfs")
          (type "tmpfs")
          (options "mode=1777,nr_inodes=1m,size=75%")
          (create-mount-point? #t)
          (check? #f))
        (file-system
          (device "tmpfs")
          (mount-point "/var/lock")
          (type "tmpfs")
          (flags '(no-suid no-dev strict-atime))
          (options "mode=1777,nr_inodes=800k,size=20%")
          (create-mount-point? #t)
          (check? #f))))

(define %persist-filesystem
  (map (match-lambda
         ((subvol mount-point)
          (file-system
            (device (file-system-label "Linux"))
            (mount-point mount-point)
            (type "btrfs")
            (dependencies %mapped-devices-config)
            (options (string-append "subvol=" subvol ",compress=zstd:6"))
            (create-mount-point? #t)
            (needed-for-boot? #t)
            (check? (string=? mount-point "/gnu"))))) %btrfs-subvolumes))

(define %data-filesystem
  (file-system
    (device (file-system-label "Linux"))
    (mount-point "/data")
    (type "btrfs")
    (dependencies %mapped-devices-config)
    (options (string-append "subvol=" %btrfs-subvol-data ",compress=zstd:6"))
    (create-mount-point? #t)))

(define %bind-mounts
  (map (lambda (dirs)
         (file-system
           (mount-point (string-append "/home/" username "/" dirs))
           (device (string-append "/data/" dirs))
           (type "none")
           (flags '(bind-mount))
           (dependencies (list %data-filesystem))
           (create-mount-point? #t))) %data-dirs))

(define %file-systems-config
  (append %bind-mounts %persist-filesystem %tmpfs
          (list %data-filesystem
                (file-system
                  (device (uuid "9699-52A2"
                                'fat))
                  (mount-point "/boot")
                  (type "vfat")
                  (create-mount-point? #t))) %base-file-systems))
```

## Kernel

### 导入 `nonguix` 固件

使用 `nonguix` 频道提供的固件和内核，以让系统能够在现代硬件中正常运行

```scheme
(use-modules (gnu packages firmware)

             (nongnu packages firmware)
             (nongnu packages linux)
             (nongnu system linux-initrd))

(define %initrd-config
  microcode-initrd)

(define %firmware-config
  (list bluez-firmware linux-firmware ovmf-x86-64 sof-firmware))

(define %kernel-config
  linux-6.19)
```

### 内核参数修改

```scheme
(use-service-modules linux pam-mount sysctl)

(define %kernel-arguments-config
  (cons* "kernel.sysrq=1"
         "modprobe.blacklist=wacom,hid_uclogic"
         "snd-intel-dspcfg.dsp_driver=3"
         "usbcore.autosuspend=120"
         "zswap.enabled=1"
         "zswap.max_pool_percent=90"
         %default-kernel-arguments))

(define %kernel-services
  (list (simple-service 'extend-kernel-module-loader
                        kernel-module-loader-service-type
                        '("ip_tables" "iptable_nat" "kvm_intel" "sch_fq_pie"
                          "tcp_bbr" "uinput"))

        (simple-service 'extend-sysctl sysctl-service-type
                        '(("fs.inotify.max_user_watches" . "524288")
                          ("fs.file-max" . "2097152")
                          ("fs.nr_open" . "2097152")

                          ("vm.max_map_count" . "2147483642")
                          ("vm.compaction_proactiveness" . "0")
                          ("vm.vfs_cache_pressure" . "50")
                          ("vm.page_lock_unfairness" . "1")
                          ("vm.stat_interval" . "120")

                          ("net.core.default_qdisc" . "fq_pie")
                          ("net.core.rmem_max" . "7500000")
                          ("net.core.wmem_max" . "7500000")
                          ("net.ipv4.ip_forward" . "1")
                          ("net.ipv4.tcp_congestion_control" . "bbr")
                          ("net.ipv4.tcp_low_latency" . "1")
                          ("net.ipv4.tcp_fastopen" . "3")
                          ("net.ipv6.conf.all.forwarding" . "1")

                          ("kernel.numa_balancing" . "0")
                          ("kernel.sched_autogroup_enabled" . "1")
                          ("kernel.sched_child_runs_first" . "0")))

        (service pam-limits-service-type
                 (list (pam-limits-entry "@audio"
                                         'both
                                         'rtprio 90)
                       (pam-limits-entry "@audio"
                                         'both
                                         'memlock
                                         'unlimited)
                       (pam-limits-entry "*"
                                         'both
                                         'nofile 1048576)))))
```

## Packages

一些需要用到的软件包， **非必要不修改**

```scheme
(define %packages-config
  (append (specs->pkgs+out
           ;; Core System Tools
           "cpufrequtils"
           "cryptsetup"
           "dialog"
           "iproute2"
           "iptables-nft"
           "pinentry"
           "rtkit"
           "strace"

           ;; Networking & Connectivity
           "adb"
           "bluez"
           "curl"
           "fprintd"
           "mihomo"
           "netcat-openbsd"
           "wget"

           ;; Development Tools
           "gcc-toolchain"
           "git"
           "git-filter-repo"
           "git-lfs"

           ;; Desktop Environment
           "brightnessctl"
           "dconf-editor"
           "gvfs"
           "niri"
           "poweralertd"
           "setxkbmap"
           "swayidle"
           "xdg-dbus-proxy"
           "xdg-desktop-portal-gnome"
           "xdg-desktop-portal-gtk"
           "xdg-user-dirs"
           "xdg-utils"
           "xprop"
           "xwayland-satellite"

           ;; Desktop Services
           "gnome-keyring"
           "libgnome-keyring"
           "libnotify"
           "libsecret"
           "polkit-gnome"

           ;; File Management
           "exo"
           "file-roller"
           "thunar"
           "thunar-archive-plugin"
           "thunar-media-tags-plugin"
           "thunar-volman"
           "thunar-vcs-plugin"
           "tumbler"
           "xfconf"

           ;; Multimedia
           "gstreamer"
           "gst-plugins-base"
           "gst-plugins-good"
           "gst-plugins-bad"
           "gst-plugins-ugly-full"

           ;; Fonts
           "font-awesome"
           "font-google-noto-emoji"
           "font-nerd-fonts-iosevka"
           "font-maple-font-nf-cn"
           "font-sarasa-gothic"

           ;; Terminal & Shell
           "fastfetch-minimal"
           "fish"
           "foot"

           ;; Virtualization & Containers
           "distrobox"
           "libvirt"
           "podman"
           "podman-compose"
           "qemu"
           "runc"
           "spice"

           ;; Package Management
           "flatpak"
           "flatpak-xdg-utils"
           "nix"

           ;; Utilities
           "gzip"
           "ntfs-3g"
           "tpm2-abrmd"
           "tpm2-pkcs11"
           "tpm2-tools"
           "tpm2-tss"
           "unzip"
           "zip") %base-packages))
```

## Services

```scheme
(use-modules (gnu home services guix)
             (guix channels)

             (jeans services hardware)
             (px services audio))

(use-service-modules authentication desktop linux sound)
```

### 基础服务

```scheme
(define %base-services
  (append (map (lambda (tty)
                 (service kmscon-service-type
                          (kmscon-configuration (virtual-terminal tty)
                                                (font-engine "pango")
                                                (font-size 24))))
               '("tty2" "tty3" "tty4" "tty5" "tty6"))

          (list (service fprintd-service-type)
                (service gnome-keyring-service-type)
                (service gvfs-service-type)
                (service opentabletdriver-service-type)
                (service rtkit-daemon-service-type)

                (simple-service 'home-channels home-channels-service-type
                                guix-channels)

                (simple-service 'root-services shepherd-root-service-type
                                (list (shepherd-timer '(guix-gc)
                                                      #~(calendar-event
                                                                        #:days-of-week '
                                                                        (sunday)
                                                                        #:hours '
                                                                        (18)
                                                                        #:minutes '
                                                                        (0))
                                                      #~("/run/current-system/profile/bin/guix"
                                                         "gc"
                                                         "--delete-generations=14d")
                                                      #:requirement '(user-processes
                                                                      guix-daemon)))))))
```

### GUI相关服务

在此也定义了Guix相关的配置

```scheme

(use-modules (guix channels)

             (rosenthal services base)
             (rosenthal packages wm)
             (rosenthal services desktop))

(use-package-modules glib package-management wm)

(define %desktop-services
  (modify-services %rosenthal-desktop-services/tuigreet
    (delete console-font-service-type)

    (greetd-service-type config =>
                         (greetd-configuration (inherit config)
                                               (greeter-supplementary-groups '
                                                                             ("video"
                                                                              "audio"))
                                               (terminals (list (greetd-terminal-configuration
                                                                 (terminal-vt
                                                                  "7")
                                                                 (terminal-switch
                                                                  #t)
                                                                 (default-session-command
                                                                  (greetd-tuigreet-session))
                                                                 (initial-session-user
                                                                  username)
                                                                 (initial-session-command
                                                                  (program-file
                                                                   "niri-session"
                                                                   #~(execl #$
                                                                      (file-append
                                                                       dbus
                                                                       "/bin/dbus-run-session")
                                                                      "dbus-run-session"

                                                                      (string-append
                                                                       "--dbus-daemon="
                                                                       #$(file-append
                                                                          dbus
                                                                          "/bin/dbus-daemon"))
                                                                      #$(file-append
                                                                         niri
                                                                         "/bin/niri")
                                                                      "--session"))))))))

    (guix-service-type config =>
                       (guix-configuration (inherit config)
                                           (channels guix-channels)
                                           (guix (guix-for-channels
                                                  guix-channels))
                                           (substitute-urls (append (list
                                                                     "https://mirror.sjtu.edu.cn/guix"
                                                                     "https://mirrors.sjtug.sjtu.edu.cn/guix-bordeaux"
                                                                     "https://substitutes.guix.gofranz.com"
                                                                     "https://cache-cdn.guix.moe"
                                                                     "https://substitutes.nonguix.org")
                                                             %default-substitute-urls))
                                           (authorized-keys (append (list (plain-file
                                                                           "guix-moe.pub"
                                                                           "(public-key (ecc (curve Ed25519) (q #552F670D5005D7EB6ACF05284A1066E52156B51D75DE3EBD3030CD046675D543#)))")

                                                                          (plain-file
                                                                           "nonguix.pub"
                                                                           "(public-key (ecc (curve Ed25519) (q #C1FD53E5D4CE971933EC50C9F307AE2171A2D3B52C804642A7A35F84F3A4EA98#)))")

                                                                          (plain-file
                                                                           "panther.pub"
                                                                           "(public-key (ecc (curve Ed25519) (q #0096373009D945F86C75DFE96FC2D21E2F82BA8264CB69180AA4F9D3C45BAA47#)))"))
                                                             %default-authorized-guix-keys))
                                           (extra-options (list "--cores=20"
                                                           "--max-jobs=6"))
                                           (http-proxy "http://127.0.0.1:7890")
                                           (discover? #f)
                                           (privileged? #f)
                                           (tmpdir "/var/tmp")))))
```

### 文件系统相关服务

在这里就是一些负责维护文件系统树的服务

- **fixed-machine-id** 负责固定 `/etc/machine-id` 这个文件中的内容，具体的算法在 [information.scm](../information.scm) 中
- **fix-data-perms** 负责修复 `/data` 目录下所有文件夹的权限
- **create-xdg-dirs** 负责在 `/data` 目录和 `/home/user` 目录中创建同名的文件夹，以用于bind-mount

```scheme

(use-service-modules desktop)

(define %filesystem-services
  (list (simple-service 'fixed-machine-id etc-service-type
                        (list `("machine-id" ,(plain-file "machine-id"
                                                          fixed-machine-id))))

        (simple-service 'fix-data-perms activation-service-type
                        #~(begin
                            (use-modules (guix build utils))
                            (mkdir-p "/data")
                            (chmod "/data" #o1777)))

        (simple-service 'create-xdg-dirs activation-service-type
                        (with-imported-modules (source-module-closure '((guix
                                                                         build
                                                                         utils)))
                                               #~(begin
                                                   (use-modules (guix build
                                                                      utils))
                                                   (let* ((pw (getpwnam #$username))
                                                          (uid (passwd:uid pw))
                                                          (gid (passwd:gid pw))
                                                          (home (string-append
                                                                 "/home/"
                                                                 #$username)))
                                                     (for-each (lambda (dir)
                                                                 (let ((path (string-append
                                                                              home
                                                                              "/"
                                                                              dir)))
                                                                   (mkdir-p
                                                                    path)
                                                                   (chown path
                                                                    uid gid)
                                                                   (chmod path
                                                                    #o755)))
                                                               '#$%data-dirs)))))))
```

### 网络相关配置

```scheme
(use-modules (rosenthal packages networking)
             (rosenthal services networking))

(use-service-modules networking shepherd)

(define %networking-services
  (list (service nftables-service-type
                 (nftables-configuration (ruleset (local-file
                                                   "../source/files/nftables.conf"))))
        (simple-service 'mihomo-services shepherd-root-service-type
                        (list (shepherd-service (documentation
                                                 "Run the mihomo daemon.")
                                                (provision '(mihomo-daemon))
                                                (requirement '(user-processes))
                                                (start #~(make-forkexec-constructor
                                                          (list #$(file-append
                                                                   mihomo
                                                                   "/bin/mihomo")
                                                                "-f"
                                                                (string-append
                                                                 "/home/"
                                                                 #$username
                                                                 "/.config/mihomo/config.yaml"))
                                                          #:log-file
                                                          "/var/log/mihomo.log"))
                                                (stop #~(make-kill-destructor))
                                                (auto-start? #t)
                                                (respawn? #t))))))
```

### `Nix`包管理器相关配置

```scheme
(use-service-modules nix shepherd)

(define %nix-services
  (list (service nix-service-type
                 (nix-configuration (extra-config (list (string-append
                                                         "trusted-users"
                                                         " = root " username)))))

        (simple-service 'non-nixos-gpu shepherd-root-service-type
                        (list (shepherd-service (documentation
                                                 "Install GPU drivers for running GPU accelerated programs from Nix.")
                                                (provision '(non-nixos-gpu))
                                                (requirement '(nix-daemon))
                                                (start #~(make-forkexec-constructor '
                                                          ("/run/current-system/profile/bin/ln"
                                                           "-nsf"
                                                           "/var/lib/non-nixos-gpu"
                                                           "/run/opengl-driver")))
                                                (stop #~(make-kill-destructor))
                                                (auto-start? #t)
                                                (one-shot? #t))))))
```

### UDEV规则

```scheme
(use-package-modules android games)

(use-service-modules linux)

(define %udev-services
  (list (udev-rules-service 'android android-udev-rules
                            #:groups '("adbusers"))
        (udev-rules-service 'steam-devices steam-devices-udev-rules)
        (udev-rules-service 'controller
                            (udev-rule "60-controller-permission.rules"
                             "KERNEL==\"event*\", ATTRS{idVendor}==\"045e\", ATTRS{idProduct}==\"028e\", MODE=\"0660\", GROUP=\"users\""))
        (udev-rules-service 'cpu-dma
                            (udev-rule "99-cpu-dma-latency.rules"
                             "DEVPATH==\"/devices/virtual/misc/cpu_dma_latency\", OWNER=\"root\", GROUP=\"audio\", MODE=\"0660\""))))
```

### 虚拟化相关服务

```scheme

(use-service-modules containers dns networking virtualization)

(define %virtualization-services
  (list (service dnsmasq-service-type
                 (dnsmasq-configuration (shepherd-provision '(dnsmasq-virbr0))
                                        (extra-options (list
                                                        "--except-interface=lo"
                                                        "--interface=virbr0"
                                                        "--bind-dynamic"
                                                        "--dhcp-range=192.168.10.2,192.168.10.254"))))

        (service rootless-podman-service-type
                 (rootless-podman-configuration (subuids (list (subid-range (name
                                                                             "brokenshine")
                                                                            (start
                                                                             100000)
                                                                            (count
                                                                             65536))))
                                                (subgids (list (subid-range (name
                                                                             "brokenshine")
                                                                            (start
                                                                             100000)
                                                                            (count
                                                                             65536))))))

        (service static-networking-service-type
                 (list (static-networking (provision '(network-manager))
                                          (links (list (network-link (name
                                                                      "virbr0")
                                                                     (type 'bridge)
                                                                     (arguments '()))))
                                          (addresses (list (network-address (device
                                                                             "virbr0")
                                                                            (value
                                                                             "192.168.10.1/24")))))))

        (service libvirt-service-type
                 (libvirt-configuration (unix-sock-group "libvirt")))
        (service virtlog-service-type)))

(define %services-config
  (append %base-services
          %udev-services
          %networking-services
          %virtualization-services
          %kernel-services
          %nix-services
          %filesystem-services
          %desktop-services))
```

## Skeletons

负责处理 **用户骨架** (/etc/skel) 目录下的文件

该目录下的所有文件都会在用户第一次创建时写入到用户的目录中

适合在此放置一些需要经常修改的模板类服务

```scheme

(define %skeletons-config
  `((".config/mihomo/config.yaml" ,(local-file "../source/files/mihomo.yaml"))
    (".config/noctalia/settings.json" ,(local-file
                                        "../source/files/noctalia.json"))))
```

## Users

用户信息

其中的password默认设置为了 `guix-awesome` ，需要你在进入账户之后再重新修改对应的密码

```scheme
(use-modules (gnu packages shells))

(define %timezone-config
  "Asia/Shanghai")
(define %locale-config
  "zh_CN.utf8")
(define %host-name-config
  "BrokenShine-Desktop")
(define %users-config
  (cons* (user-account
           (inherit %root-account)
           (password #f)
           (shell (file-append (spec->pkg "fish") "/bin/fish")))
         (user-account
           (name username)
           (group "users")
           (password (crypt "guix-awesome" "$6$abc"))
           (supplementary-groups '("adbusers" "audio"
                                   "cgroup"
                                   "input"
                                   "kvm"
                                   "libvirt"
                                   "netdev"
                                   "video"
                                   "wheel"))
           (shell (file-append (spec->pkg "fish") "/bin/fish")))
         %base-user-accounts))
```

## Main

导入所有配置

一个 `operating-system` 块必须包含以下的所有内容

```scheme
(operating-system
  (initrd %initrd-config)
  (firmware %firmware-config)
  (kernel %kernel-config)
  (kernel-arguments %kernel-arguments-config)
  (keyboard-layout (keyboard-layout "us" #:options '("ctrl:swapcaps")))

  (timezone %timezone-config)
  (locale %locale-config)
  (host-name %host-name-config)

  (users %users-config)

  (bootloader %bootloader-config)

  (mapped-devices %mapped-devices-config)
  (file-systems %file-systems-config)

  (packages %packages-config)

  (services
   %services-config)
  (skeletons %skeletons-config)

  (name-service-switch %mdns-host-lookup-nss))
```
