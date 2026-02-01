;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
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
                                                     ("rm" . "rm -i")))

                                          (abbreviations '(("commit" . "'git commit --all -S'")
                                                           ("enter" . "distrobox enter")
                                                           ("push" . "git push")
                                                           ("reboot" . "loginctl reboot")
                                                           ("shutdown" . "loginctl poweroff")
                                                           ("update" . "'sudo flatpak upgrade -y && flatpak upgrade -y && distrobox upgrade'")))

                                          (config (list (computed-substitution-with-inputs
                                                         "config.fish"
                                                         (local-file
                                                          "../../files/config.fish")
                                                         (specs->pkgs
                                                          "fastfetch" "fzf"
                                                          "lolcat" "starship"
                                                          "zoxide"))))))))
