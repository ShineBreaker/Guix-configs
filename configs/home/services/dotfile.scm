;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-modules (gnu home services shells)
             (rosenthal services shellutils))

(use-package-modules java shells)

(define %dotfile-services
  (list (service home-dotfiles-service-type
                 (home-dotfiles-configuration (directories '("../dotfiles"))
                                              (excluded '("^.git$"
                                                          "^.gitignore$"
                                                          "^.github$"))))

        (service home-files-service-type
                 `((".guile" ,%default-dotguile)
                   (".Xdefaults" ,%default-xdefaults)
                   (".config/git-credential-keepassxc" ,(computed-substitution-with-inputs
                                                         "git-credential-keepassxc"
                                                         (local-file
                                                          "../configs/files/git-credential-keepassxc")
                                                         (specs->pkgs "git"
                                                                      "fish")))
                   (".config/qt5ct/qss/rounded.qss", (local-file "../configs/files/rounded.qss"))
                   (".config/qt6ct/qss/rounded.qss", (local-file "../configs/files/rounded.qss"))))

        (service home-niri-service-type
                 (home-niri-configuration (config (computed-substitution-with-inputs
                                                   "config.kdl"
                                                   (local-file
                                                    "../configs/files/niri.kdl")
                                                   (specs->pkgs
                                                    "brightnessctl"
                                                    "cliphist"
                                                    "dex"
                                                    "foot"
                                                    "fish"
                                                    "niri"
                                                    "wl-clipboard"
                                                    "xwayland-satellite")))))

        (service home-xdg-configuration-files-service-type
                 `(("gdb/gdbinit" ,%default-gdbinit)
                   ("nano/nanorc" ,%default-nanorc)))

        (simple-service 'symlink-openjdk home-files-service-type
                        (map (lambda (jdk)
                               (list (in-vicinity
                                      ".local/share/PrismLauncher/java/"
                                      (package-version jdk)) jdk))
                             (list openjdk25 openjdk21 openjdk17)))))
