;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-service-modules linux
                     pam-mount
                     sysctl)

(define %kernel-services
  (list (simple-service 'extend-kernel-module-loader
                        kernel-module-loader-service-type
                        '("ip_tables" "iptable_nat" "kvm_intel"
                          "sch_fq_pie" "tcp_bbr"))

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
