;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(load "../information.scm")

(load "../home/modules.scm")
(load "../home/package.scm")
(load "../home/services.scm")

(define %home-config
  (home-environment
    (packages (append %packages-list))

    (services
      (append %desktop-services))))

%home-config
