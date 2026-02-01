;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(load "./information.scm")

(load "./home/modules.scm")
(load "./home/package.scm")

(load "./home/services/desktop.scm")
(load "./home/services/dotfile.scm")
(load "./home/services/environment-variables.scm")
(load "./home/services/fish.scm")
(load "./home/services/font.scm")

(define %home-config
  (home-environment
    (packages (append %fish-packages-list
                      %packages-list))

    (services
     (append %desktop-services
             %dotfile-services
             %environment-variable-services
             %fish-services
             %font-services
             %rosenthal-desktop-home-services))))

%home-config
