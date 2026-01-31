;;; SPDX-FileCopyrightText: 2026 Copyright (C) 2024-2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(define %fish-packages-list
  (cons* (specs->pkgs+out "atuin"
                          "bat"
                          "direnv"
                          "fd"
                          "ripgrep"
                          "fzf"
                          "lolcat"
                          "starship"
                          "zoxide")))

(define %fish-services
  (list (service home-fish-plugin-atuin-service-type)
        (service home-fish-plugin-direnv-service-type)
        (service home-fish-service-type
                 (home-fish-configuration (aliases '(("cat" . "bat")
                                                     ("cd" . "z")
                                                     ("cp" . "cp -i")
                                                     ("find" . "fd")
                                                     ("grep" . "rg")
                                                     ("htop" . "btop")
                                                     ("ll" . "ls -la")
                                                     ("rm" . "rm -i")
                                                     ("sudo" . "/run/privileged/bin/sudo")))

                                          (abbreviations '(("commit" . "'git commit --all -S'")
                                                           ("enter" . "distrobox enter")
                                                           ("push" . "git push")
                                                           ("reboot" . "loginctl reboot")
                                                           ("rebuild" . "'sudo guix system reconfigure ./config.scm --allow-downgrades && guix home reconfigure ./home-config.scm --allow-downgrades'")
                                                           ("shutdown" . "loginctl poweroff")
                                                           ("update" . "'sudo flatpak upgrade -y && flatpak upgrade -y && distrobox upgrade'")
                                                           ("upgrade" . "'guix pull -C ./channel.scm && guix describe --format=channels > channel.lock'")))

                                          (config (list (local-file
                                                         "../../files/config.fish")))))))
