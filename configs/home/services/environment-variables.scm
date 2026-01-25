;;; SPDX-FileCopyrightText: 2026 Copyright (C) 2024-2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(define %environment-variable-services
  (list (simple-service 'environment-variables
                        home-environment-variables-service-type
                        `(("EDITOR" . "hx") ("GDK_BACKEND" . "wayland")
                          ("GUIX_PROFILE" . "$HOME/.guix-profile")
                          ("HTTP_PROXY" . "http://127.0.0.1:7890")
                          ("http_proxy" . "$HTTP_PROXY")
                          ("HTTPS_PROXY" . "$HTTP_PROXY")
                          ("https_proxy" . "$HTTP_PROXY")
                          ("MOZ_ENABLE_WAYLAND" . "1")
                          ("PATH" unquote
                           (string-append "$HOME/.local/bin:"
                                          "$HOME/.nix-profile/bin:"
                                          (or (getenv "PATH") "")))
                          ("QT_AUTO_SCREEN_SCALE_FACTOR" . #t)
                          ("QT_PLUGIN_PATH" unquote
                           (string-append
                            "/run/current-system/profile/lib/qt5/plugins:"
                            "/run/current-system/profile/lib/qt6/plugins:"
                            (or (getenv "QT_PLUGIN_PATH") "")))
                          ("QT_QPA_PLATFORMTHEME" . "qt5ct")
                          ("_JAVA_AWT_WM_NONREPARENTING" . #t)))))
