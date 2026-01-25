;;; SPDX-FileCopyrightText: 2026 Copyright (C) 2024-2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(define %font-services
  (list (simple-service 'extend-fontconfig home-fontconfig-service-type
                        (list "~/.local/share/fonts"
                              "/run/current-system/profile/share/fonts"
                              (let ((sans "Sarasa Gothic SC")
                                    (serif "Sarasa Gothic SC")
                                    (mono "Maple Mono NF CN")
                                    (emoji "Noto Color Emoji"))
                                `((alias (family "sans-serif")
                                         (prefer (family ,sans)
                                                 (family ,emoji)))
                                  (alias (family "serif")
                                         (prefer (family ,serif)
                                                 (family ,emoji)))
                                  (alias (family "monospace")
                                         (prefer (family ,mono)
                                                 (family ,emoji)))
                                  (alias (family "emoji")
                                         (prefer (family ,emoji)))))))))
