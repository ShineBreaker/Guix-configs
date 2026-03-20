;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: GPL-3.0

(define %extend-environment-variables
  '(("ANDROID_HOME" . "$HOME/Programs/Android/SDK")
    ("EDITOR" . "hx")
    ("FREERDP_ASKPASS" . "1")
    ("GUIX_PROFILE" . "$HOME/.guix-profile")
    ("GUIX_SANDBOX_HOME" . "$XDG_DATA_HOME/Sandbox")
    ("HTTP_PROXY" . "http://127.0.0.1:7890")
    ("http_proxy" . "$HTTP_PROXY")
    ("HTTPS_PROXY" . "$HTTP_PROXY")
    ("https_proxy" . "$HTTP_PROXY")
    ("LIBVIRT_DEFAULT_URI" . "qemu:///system")
    ("no_proxy" . "127.0.0.1,localhost")
    ("NO_PROXY" . "127.0.0.1,localhost")
    ("QS_ICON_THEME" . "Papirus-Dark")
    ("QT_QPA_PLATFORMTHEME" . "qt5ct")

    ;; Wayland support.
    ("GDK_BACKEND" . "wayland")
    ("_JAVA_AWT_WM_NONREPARENTING" . "1")
    ("MOZ_ENABLE_WAYLAND" . "1")
    ("QT_AUTO_SCREEN_SCALE_FACTOR" . "1")))

(define %xdg-base-directory-env-vars
  '( ;bash
     ("HISTFILE" . "$XDG_STATE_HOME/bash/history")
    ;; docker
    ("DOCKER_CONFIG" . "$XDG_CONFIG_HOME/docker")
    ;; gdb
    ("GDBHISTFILE" . "$XDG_STATE_HOME/gdb/history")
    ;; gnupg
    ("GNUPGHOME" . "$XDG_DATA_HOME/gnupg")
    ;; go
    ("GOMODCACHE" . "$XDG_CACHE_HOME/go/mod")
    ("GOPATH" . "$XDG_DATA_HOME/go")
    ;; gradle
    ("GRADLE_USER_HOME" . "$XDG_DATA_HOME/gradle")
    ;; guile
    ("GUILE_HISTORY" . "$XDG_STATE_HOME/guile/history")
    ;; luanti
    ("MINETEST_USER_PATH" . "$XDG_DATA_HOME/luanti")
    ;; node
    ("NPM_CONFIG_USERCONFIG" . "$XDG_CONFIG_HOME/npm/npmrc")
    ;; nvidia-driver
    ("CUDA_CACHE_PATH" . "$XDG_CACHE_HOME/nv")
    ;; password-store
    ("PASSWORD_STORE_DIR" . "$XDG_DATA_HOME/pass")
    ;; python
    ("PYTHON_HISTORY" . "$XDG_STATE_HOME/python/history")
    ;; rust
    ("CARGO_HOME" . "$XDG_DATA_HOME/cargo")
    ;; sqlite
    ("SQLITE_HISTORY" . "$XDG_STATE_HOME/sqlite_history")
    ;; tmuxifier
    ("TMUXIFIER_LAYOUT_PATH" . "$XDG_CONFIG_HOME/tmuxifier/layouts")))

(define %environment-variable-services
  (list (simple-service 'environment-variables
                        home-environment-variables-service-type
                        `(,@%extend-environment-variables
                          ,@%xdg-base-directory-env-vars
                          ("QT_PLUGIN_PATH" unquote
                           (string-append
                            "/run/current-system/profile/lib/qt5/plugins:"
                            "/run/current-system/profile/lib/qt6/plugins:"
                            "$HOME/.guix-home/profile/lib/qt5/plugins:"
                            "$HOME/.guix-home/profile/lib/qt6/plugins"))

                          ("CHROMIUM_FLAGS" unquote
                           (string-append
                            "--enable-features=UseOzonePlatform,WaylandWindowDecorations "
                            "--ozone-platform-hint=wayland "
                            "--enable-wayland-ime "
                            "--wayland-text-input-version=3"))
                          ("_JAVA_OPTIONS" unquote
                           (string-append
                            "-Djava.util.prefs.userRoot=$XDG_CONFIG_HOME/java "
                            "-Dawt.toolkit.name=WLToolkit"))))))
