;;; SPDX-FileCopyrightText: 2026 Copyright (C) 2024-2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-package-modules shells)

(define %dotfile-services
  (list (service home-dotfiles-service-type
                 (home-dotfiles-configuration (directories '("../../../dotfiles"))
                                              (excluded '("^.git$"
                                                          "^.gitignore$"
                                                          "^.github$"))))

        (service home-files-service-type
                 `((".guile" ,%default-dotguile)
                   (".Xdefaults" ,%default-xdefaults)))

        (service home-xdg-configuration-files-service-type
                 `(("gdb/gdbinit" ,%default-gdbinit)
                   ("nano/nanorc" ,%default-nanorc)
                   ("pipewire/pipewire.conf.d/99-custom-latency.conf" , (local-file "../../files/99-custom-latency.conf"))))

        (simple-service 'fish-foreign-env
                        home-xdg-configuration-files-service-type
                        `(("fish/conf.d/01-fish-foreign-env-main.fish" ,(file-append
                                                                         fish-foreign-env
                                                                         "/share/fish/functions/fenv.main.fish"))
                          ("fish/conf.d/02-fish-foreign-env.fish" ,(file-append
                                                                    fish-foreign-env
                                                                    "/share/fish/functions/fenv.fish"))))))
