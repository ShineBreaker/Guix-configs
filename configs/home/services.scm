;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(load "../home/services/desktop.scm")
(load "../home/services/dotfile.scm")
(load "../home/services/environment-variables.scm")
(load "../home/services/font.scm")

(define %desktop-services
  (append %desktop-services-extended
          %dotfile-services
          %environment-variable-services
          %font-services

          %rosenthal-desktop-home-services))
