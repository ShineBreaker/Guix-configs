(define %environment-variable-services
  (list (simple-service 'environment-variables
                        home-environment-variables-service-type
                        `(("EDITOR" . "hx") ("GDK_BACKEND" . "wayland")
                          ("GUIX_PROFILE" . "$HOME/.guix-profile/etc/profile")
                          ("HTTP_PROXY" . "http://127.0.0.1:7890")
                          ("HTTPS_PROXY" . "$HTTP_PROXY")
                          ("PATH" unquote
                           (string-append "$HOME/.local/bin:"
                                          (or (getenv "PATH") "")))
                          ("QT_AUTO_SCREEN_SCALE_FACTOR" . #t)
                          ("QT_QPA_PLATFORMTHEME" . "qt5ct")
                          ("QT_PLUGIN_PATH" unquote
                           (string-append
                            "/run/current-system/profile/lib/qt5/plugins:"
                            "/run/current-system/profile/lib/qt6/plugins:"
                            (or (getenv "QT_PLUGIN_PATH") "")))
                          ("_JAVA_AWT_WM_NONREPARENTING" . #t)))))
