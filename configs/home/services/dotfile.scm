;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-modules (gnu home services shells)
             (rosenthal services shellutils))

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
                   ("nano/nanorc" ,%default-nanorc)))))
