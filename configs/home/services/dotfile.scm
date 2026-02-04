;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-modules (gnu home services shells)
             (rosenthal services shellutils))

(use-package-modules shells)

(define %dotfile-services
  (list (service home-dotfiles-service-type
                 (home-dotfiles-configuration (directories '("../dotfiles"))
                                              (excluded '("^.git$"
                                                          "^.gitignore$"
                                                          "^.github$"))))

        (service home-files-service-type
                 `((".guile" ,%default-dotguile)
                   (".Xdefaults" ,%default-xdefaults)))

        (service home-niri-service-type
                 (home-niri-configuration (config (computed-substitution-with-inputs
                                                   "niri.kdl"
                                                   (local-file
                                                    "../configs/files/config.kdl")
                                                   (specs->pkgs
                                                    "brightnessctl"
                                                    "cliphist"
                                                    "dex"
                                                    "foot"
                                                    "fish"
                                                    "niri"
                                                    "noctalia-shell"
                                                    "wl-clipboard"
                                                    "xwayland-satellite")))))

        (service home-xdg-configuration-files-service-type
                 `(("gdb/gdbinit" ,%default-gdbinit)
                   ("nano/nanorc" ,%default-nanorc)))

        (simple-service 'jdk-symlinks home-activation-service-type
                        %jdk-symlink-activation)))
