;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-modules (guix channels)

             (rosenthal services base)
             (rosenthal packages wm)
             (rosenthal services desktop))

(use-package-modules glib
                     package-management
                     wm)

(define %desktop-services
  (modify-services %rosenthal-desktop-services/tuigreet
    (delete console-font-service-type)

    (greetd-service-type config =>
                         (greetd-configuration (inherit config)
                                               (greeter-supplementary-groups '
                                                ("video" "audio"))
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
                                                                             #$
                                                                             (file-append
                                                                              dbus
                                                                              "/bin/dbus-daemon"))
                                                                            #$
                                                                            (file-append
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
                                           (privileged? #f)
                                           (tmpdir "/var/tmp")))))
