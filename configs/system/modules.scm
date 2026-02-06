;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(use-modules (gnu)
             (gnu system accounts)
             (gnu system nss)
             (gnu system pam)

             (guix channels)
             (guix gexp)
             (guix modules)

             (ice-9 session)

             (rosenthal utils packages))
