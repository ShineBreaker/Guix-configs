;;; SPDX-FileCopyrightText: 2026 Copyright (C) 2024-2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(define %fish-services
  (list (service home-fish-plugin-atuin-service-type)
        (service home-fish-plugin-direnv-service-type)
        (service home-fish-plugin-zoxide-service-type)
        (service home-fish-service-type
                 (home-fish-configuration (aliases '(("ll" . "ls -la")
                                                     ("rm" . "rm -i")
                                                     ("cp" . "cp -i")))

                                          (abbreviations '(("cat" . "git")
                                                           ("cd" . "bat")
                                                           ("commit" . "'git commit --all -S'")
                                                           ("push" . "git push")
                                                           ("reboot" . "loginctl reboot")
                                                           ("rebuild" . "'sudo guix system reconfigure ./config.scm && guix home reconfigure ./home-config.scm'")
                                                           ("shutdown" . "loginctl poweroff")
                                                           ("update" . "'sudo flatpak upgrade -y && flatpak upgrade -y && distrobox upgrade'")
                                                           ("upgrade" . "guix pull")))

                                          (config (list (local-file
                                                         "../../files/config.fish")))))))
