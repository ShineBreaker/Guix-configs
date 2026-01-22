(load "../information.scm")

(use-modules (gnu home services guix)
             (guix channels))

(use-service-modules authentication
                     containers
                     dbus
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
                (service libvirt-service-type)
                (service tlp-service-type)

                (service nftables-service-type
                         (nftables-configuration (ruleset (local-file
                                                           "../files/nftables.conf"))))

                (service nix-service-type
                         (nix-configuration (extra-config (list
                           (string-append "trusted-users" "=" username)))))

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
                                                                   (srting-append "/home/" username "/.config/mihomo/config.yaml"))
                                                                  #:log-file
                                                                  "/var/log/mihomo.log"))
                                                        (stop #~(make-kill-destructor))
                                                        (respawn? #t))))

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
                                                        (one-shot? #t))))

                (service pam-limits-service-type
                               (list (pam-limits-entry "@audio" 'both 'rtprio 90)
                                     (pam-limits-entry "@audio" 'both 'memlock 'unlimited)
                                     (pam-limits-entry "*" 'both 'nofile 1048576))))

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
                                                   (discover? #f)))

            (udev-service-type config =>
                               (udev-configuration (inherit config)
                                                   (rules (append (udev-configuration-rules
                                                                   config)
                                                                  (list
                                                                   steam-devices-udev-rules
                                                                   (plain-file
                                                                    "99-sayodevice.rules"
                                                                    "KERNEL==\"hidraw*\" , ATTRS{idVendor}==\"8089\" , MODE=\"0666\"")))))))))
