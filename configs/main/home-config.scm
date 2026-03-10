;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(load "../information.scm")

(load "../home/modules.scm")
(load "../home/package.scm")

(load "../home/services/desktop.scm")
(load "../home/services/dotfile.scm")
(load "../home/services/environment-variables.scm")

(load "../home/services/programs/emacs.scm")
(load "../home/services/programs/fish.scm")

(load "../home/services/font.scm")
(load "../home/services/trash.scm")

(define %home-config
  (home-environment
    (packages (append %emacs-packages-list
                      %fish-packages-list
                      %packages-list))

    (services
     (append %desktop-services
             %dotfile-services
             %environment-variable-services
             ; %emacs-services
             %fish-services
             %font-services
             %trash-services
             %rosenthal-desktop-home-services))))

%home-config
