;;; SPDX-FileCopyrightText: 2026 Copyright (C) 2024-2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(load "../information.scm")

(use-modules (cast packages gtklock)
             (gnu home services guix)
             (guix channels)
             (jeans packages linux)
             (rosenthal packages networking))

(use-package-modules games geo package-management)

(use-service-modules authentication
                     containers
                     databases
                     dbus
                     dns
                     linux
                     networking
                     nix
                     pam-mount
                     pm
                     sddm
                     syncthing
                     sysctl
                     virtualization
                     xorg)

(define %services-config
  (append (map (lambda (tty)
                 (service kmscon-service-type
                          (kmscon-configuration (virtual-terminal tty)
                                                (font-engine "pango")
                                                (font-size 24))))
               '("tty2" "tty3" "tty4" "tty5" "tty6"))

          (list (service fprintd-service-type)
                (service gnome-keyring-service-type)
                (service gvfs-service-type)
                (service tlp-service-type)

                (simple-service 'home-channels home-channels-service-type
                                guix-channels)

                (service nftables-service-type
                         (nftables-configuration (ruleset (local-file
                                                           "../files/nftables.conf"))))

                (service postgresql-service-type
                         (postgresql-configuration (postgresql (specification->package
                                                                "postgresql@16.4"))
                                                   (extension-packages (list
                                                                        postgis))
                                                   (config-file (postgresql-config-file
                                                                 (log-destination
                                                                  "stderr")
                                                                 (hba-file (local-file
                                                                            "../files/postgresql.conf"))
                                                                 (extra-config '
                                                                  (("session_preload_libraries"
                                                                    "auto_explain")
                                                                   ("random_page_cost"
                                                                    2)
                                                                   ("auto_explain.log_min_duration"
                                                                    "100 ms")
                                                                   ("work_mem"
                                                                    "500 MB")
                                                                   ("logging_collector"
                                                                    #t)
                                                                   ("log_directory"
                                                                    "/var/log/postgresql")))))))

                (service screen-locker-service-type
                         (screen-locker-configuration (name "gtklock")
                                                      (program (file-append
                                                                gtklock
                                                                "/bin/gtklock"))
                                                      (allow-empty-password?
                                                                             #f)))

                ;; VM & Coantainer.
                (service dnsmasq-service-type
                         (dnsmasq-configuration (shepherd-provision '(dnsmasq-virbr0))
                                                (extra-options (list
                                                                "--except-interface=lo"
                                                                "--interface=virbr0"
                                                                "--bind-dynamic"
                                                                "--dhcp-range=192.168.10.2,192.168.10.254"))))

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

                (service static-networking-service-type
                         (list (static-networking (provision '(network-manager))
                                                  (links (list (network-link (name
                                                                              "virbr0")
                                                                             (type 'bridge)
                                                                             (arguments '()))))
                                                  (addresses (list (network-address
                                                                    (device
                                                                     "virbr0")
                                                                    (value
                                                                     "192.168.10.1/24")))))))

                (service libvirt-service-type
                         (libvirt-configuration (unix-sock-group "libvirt")))
                (service virtlog-service-type)

                ;; Kernel related.
                (simple-service 'extend-kernel-module-loader
                                kernel-module-loader-service-type
                                '("sch_fq_pie" "tcp_bbr"))

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
                                                 'nofile 1048576)))

                ;; Services need to run as root.
                (simple-service 'root-services shepherd-root-service-type
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
                                                        (respawn? #t))

                                      (shepherd-service (documentation
                                                         "REALTIMEKIT Realtime Policy and Watchdog Daemon.")
                                                        (provision '(rtkit-daemon))
                                                        (requirement '(dbus-system))
                                                        (start #~(make-forkexec-constructor
                                                                  (list #$(file-append
                                                                           rtkit
                                                                           "/libexec/rtkit-daemon"))
                                                                  #:log-file
                                                                  "/var/log/rtkit-daemon.log"))
                                                        (stop #~(make-kill-destructor))
                                                        (auto-start? #t)
                                                        (respawn? #t))))

                ;; Fix filesystem permissions.
                (simple-service 'fix-var-tmp-perms activation-service-type
                                #~(begin
                                    (use-modules (guix build utils))
                                    (mkdir-p "/var/tmp")
                                    (chmod "/var/tmp" #o1777)))

                (simple-service 'fix-data-perms activation-service-type
                                #~(begin
                                    (use-modules (guix build utils))
                                    (mkdir-p "/data")
                                    (chmod "/data" #o1777)))

                (simple-service
                 'create-xdg-dirs
                 activation-service-type
                 #~(begin
                     (use-modules (guix build utils))
                     (let ((home (string-append "/home/" #$username)))
                       (for-each
                        (lambda (dir)
                          (mkdir-p (string-append home "/" dir)))
                        '#$%data-dirs))))

                ;; Nix related.
                (service nix-service-type
                         (nix-configuration (extra-config (list (string-append
                                                                 "trusted-users"
                                                                 " = root "
                                                                 username)))))

                (simple-service 'non-nixos-gpu shepherd-root-service-type
                                (list (shepherd-service (documentation
                                                         "Install GPU drivers for running GPU accelerated programs from Nix.")
                                                        (provision '(non-nixos-gpu))
                                                        (requirement '(nix-daemon))
                                                        (start #~(make-forkexec-constructor '
                                                                  ("/run/current-system/profile/bin/ln"
                                                                   "-nsf"
                                                                   "/nix/store/6nklad7qapmqf41pqc2f9vizivn66a5p-non-nixos-gpu"
                                                                   "/run/opengl-driver")))
                                                        (stop #~(make-kill-destructor))
                                                        (one-shot? #t)))))

          (modify-services %rosenthal-desktop-services
            (delete console-font-service-type)

            (greetd-service-type config =>
                                 (greetd-configuration (inherit config)
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
                                                                          "dbus-run-session niri --session"))))))

            (guix-service-type config =>
                               (guix-configuration (inherit config)
                                                   (channels guix-channels)
                                                   (guix (guix-for-channels
                                                          guix-channels))
                                                   (substitute-urls (append (list
                                                                             "https://mirror.sjtu.edu.cn/guix"
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
                                                   (extra-options (list
                                                                   "--cores=20"
                                                                   "--max-jobs=6"))
                                                   (http-proxy
                                                    "http://127.0.0.1:7890")
                                                   (discover? #f)
                                                   (privileged? #f)))

            (udev-service-type config =>
                               (udev-configuration (inherit config)
                                                   (rules (append (udev-configuration-rules
                                                                   config)
                                                                  (list
                                                                   steam-devices-udev-rules
                                                                   (plain-file
                                                                    "99-sayodevice.rules"
                                                                    "KERNEL==\"hidraw*\" , ATTRS{idVendor}==\"8089\" , MODE=\"0666\"")))))))))
