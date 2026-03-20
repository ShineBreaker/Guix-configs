;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-modules (rosenthal packages networking)
             (rosenthal services networking))

(use-service-modules networking
                     shepherd)

(define %networking-services
  (list (service nftables-service-type
                 (nftables-configuration (ruleset (local-file
                                                   "../configs/files/nftables.conf"))))
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
