# Information

## 包含了一些系统的基本信息

```scheme
(load "../files/information.scm")
```

# modules

```scheme
(use-modules (gnu)
             (gnu home)
             (gnu home services)

             (gnu packages)
             (gnu services)
             (gnu system shadow)

             (guix build-system trivial)
             (guix gexp)
             ((guix licenses) #:prefix license:)
             (guix packages)
             (guix utils)

             (rosenthal utils file)
             (rosenthal utils packages)

             (gnu home services shells)

             (gnu home services desktop)
             (gnu home services dotfiles)
             (gnu home services fontutils)
             (gnu home services gnupg)
             (gnu home services shepherd)
             (gnu home services niri)
             (gnu home services sound)
             (gnu home services syncthing)
             (gnu home services guix)

             (rosenthal services desktop)

             (rosenthal services shellutils))

(use-package-modules bash
                     fcitx5
                     freedesktop
                     gnupg
                     kde-internet
                     java
                     linux
                     polkit
                     shells
                     wm)
```

# emacs

```scheme
(define %emacs-packages-list
  (cons* (specs->pkgs+out
          ;; --- Emacs 核心与 Lisp ---
          "emacs-pgtk"
          "sbcl"
          "emacs-use-package"
          "emacs-general"

          ;; --- 补全与迷你缓冲区 ---
          "emacs-vertico"
          "emacs-marginalia"
          "emacs-orderless"
          "emacs-consult"
          "emacs-embark"
          "emacs-corfu"

          ;; --- Evil 模式（Vim 模拟）---
          "emacs-evil"
          "emacs-evil-collection"

          ;; --- 界面与外观 ---
          "emacs-dashboard"
          "emacs-doom-modeline"
          "emacs-ef-themes"
          "emacs-kind-icon"
          "emacs-nerd-icons"
          "emacs-which-key"
          "emacs-minimap"
          "emacs-rainbow-delimiters"
          "emacs-treemacs"
          "emacs-treemacs-nerd-icons"
          "emacs-diff-hl"
          "emacs-stickyfunc-enhance"
          "emacs-ws-butler"

          ;; --- 开发工具 ---
          "emacs-vterm"
          "emacs-yasnippet"
          "emacs-yasnippet-snippets"
          "emacs-rg"

          ;; --- 编程语言支持 ---
          "emacs-kotlin-mode"
          "emacs-rust-mode"
          "emacs-zig-mode"
          "emacs-typescript-mode"
          "emacs-web-mode"
          "emacs-json-mode"
          "emacs-markdown-mode"
          "emacs-sly"
          "emacs-geiser"
          "emacs-geiser-guile"

          ;; --- Git 集成 ---
          "emacs-magit"
          "emacs-magit-todos"
          "emacs-git-messenger"

          ;; --- 项目管理 ---
          "emacs-projectile"

          ;; --- Org Mode 生态 ---
          "emacs-org-modern"
          "emacs-org-roam"
          "emacs-org-appear"

          ;; --- 帮助与文档 ---
          "emacs-helpful"

          ;; --- 邮件与日历 ---
          "emacs-notmuch"
          "emacs-calfw"

          ;; --- 环境与工具 ---
          "emacs-no-littering"
          "emacs-spinner"
          "emacs-yaml"

          ;; --- Tree-sitter（语法解析）---
          "tree-sitter"
          "tree-sitter-bash"
          "tree-sitter-c"
          "tree-sitter-cpp"
          "tree-sitter-css"
          "tree-sitter-dockerfile"
          "tree-sitter-go"
          "tree-sitter-html"
          "tree-sitter-javascript"
          "tree-sitter-json"
          "tree-sitter-python"
          "tree-sitter-rust"
          "tree-sitter-typescript")))
```

# fish

```scheme
(define %fish-packages-list
  (cons* (specs->pkgs+out "atuin"
                          "bat"
                          "direnv"
                          "fd"
                          "ripgrep"
                          "fzf"
                          "lolcat"
                          "zoxide")))

(define %fish-services
  (list (simple-service 'fish-configs
                        home-xdg-configuration-files-service-type
                        (list `("fish/conf.d/10-source.fish" ,(computed-substitution-with-inputs
                                                               "config.fish"
                                                               (plain-file
                                                                "10-source.fish"
                                                                "status is-interactive
                    and begin

                      $$bin/atuin$$ init fish | source
                      $$bin/direnv$$ hook fish | source
                      $$bin/fzf$$ --fish | source
                      $$bin/zoxide$$ init fish | source

                    end")
                                                               (specs->pkgs
                                                                "atuin"
                                                                "direnv" "fzf"
                                                                "zoxide")))))

        (simple-service 'fish-functions
                        home-xdg-configuration-files-service-type
                        (list `("fish/functions/fenv.main.fish" ,(file-append
                                                                  fish-foreign-env
                                                                  "/share/fish/functions/fenv.main.fish"))
                              `("fish/functions/fenv.fish" ,(file-append
                                                             fish-foreign-env
                                                             "/share/fish/functions/fenv.fish"))))))

(define termide
  (package
    (name "termide")
    (version "0.1.0")
    (source
     (local-file "../configs/files/termide"))
    (build-system trivial-build-system)
    (arguments
     (list
      #:modules '((guix build utils))
      #:builder
      #~(begin
          (use-modules (guix build utils))
          (let* ((out (assoc-ref %outputs "out"))
                 (bin (string-append out "/bin"))
                 (target (string-append bin "/termide")))
            (mkdir-p bin)
            (copy-file #$source target)
            (patch-shebang target
                           (list (string-append #$bash-minimal "/bin")))
            (chmod target #o555)))))
    (inputs (list bash-minimal))
    (synopsis "VSCode-like tmux workspace helper")
    (description
     "termide launches and controls the tmuxifier-based terminal IDE session.")
    (home-page "https://github.com/BrokenShine/Guix-configs")
    (license license:gpl3)))

(define %packages-list-extended
  (cons* termide
         (specs->pkgs+out
          ;; AI related.
          "claude-code"
          "codex"
          "opencode"

          ;; Audio & Video
          "easyeffects"
          "helvum"
          "mpv"
          "nomacs"
          "obs-with-cef"
          "obs-pipewire-audio-capture"
          "obs-vkcapture"

          ;; Desktop Environment
          "baobab"
          "cliphist"
          "dex"
          "fcitx5"
          "fuzzel"
          "nautilus"
          "wl-clipboard"
          "xsel"

          ;; Communication
          "kdeconnect"
          "notmuch"
          "telegram-desktop"

          ;; Productivity
          "gimp"
          "keepassxc"
          "git-credential-keepassxc"
          "seahorse"
          "virt-manager"
          "zen-browser-bin"

          ;; Entertainment
          "heroic"
          "mangohud"
          "osu-lazer-bin"
          "prismlauncher-dolly"
          "steam"

          ;; System & Utilities
          "age"
          "amule"
          "broot"
          "btop"
          "freerdp@3"
          "just"
          "maak"
          "postgresql"
          "tmux"
          "tmuxifier"
          "tmux-xpanes"
          "winapps"

          ;; Themes & Appearance
          "adw-gtk3-theme"
          "adwaita-icon-theme"
          "bibata-cursor-theme"
          "papirus-icon-theme"

          ;; Development
          "ccls"
          "clang"
          "gradle"
          "helix"
          "maven"
          "node"
          "openjdk@25"
          "pandoc"
          "pnpm@10"
          "python-black"
          "python-jsbeautifier"
          "python-lsp-black"
          "python-lsp-server"
          "python-pylsp-mypy"
          "reuse"
          "rust-analyzer"
          "sdkmanager"
          "uv"
          "zed"

          ;; Qt Framework
          "pinentry-qt"
          "qt5ct"
          "qt6ct")))

(define %packages-list
  (append %packages-list-extended %emacs-packages-list %fish-packages-list))
```

# modprobe

```scheme
(define %modprobe-services
  (list ;modprobed-db 配置文件
        (simple-service 'modprobed-db-config home-files-service-type
                        `((".config/modprobed-db/modprobed-db.conf" ,(plain-file
                                                                      "modprobed-db.conf"
                                                                      "IGNORE=(hid-uclogic wacom)"))))

        ;; modprobed-db 激活时运行（一次性初始化）
        (simple-service 'modprobed-db-activation home-activation-service-type
                        #~(begin
                            (use-modules (guix build utils))
                            ;; 确保配置目录存在
                            (mkdir-p (string-append (getenv "HOME")
                                                    "/.config/modprobed-db"))
                            ;; 运行 modprobed-db store 记录当前模块
                            (system* #$(file-append modprobed-db
                                                    "/bin/modprobed-db")
                                     "storesilent")))))
```

# desktop

```scheme
(define %user-desktop-services
  (list (service home-syncthing-service-type)
        (service home-noctalia-shell-service-type)

        (service home-fcitx5-service-type
                 (home-fcitx5-configuration (themes (list
                                                     fcitx5-material-color-theme))
                                            (input-method-editors (list
                                                                   fcitx5-rime))
                                            (gtk-im-module? #t)
                                            (qt-im-module? #t)))

        (simple-service 'essential-desktop-services home-shepherd-service-type
                        (list (shepherd-service (provision '(kdeconnectd))
                                                (requirement '(dbus))
                                                (start #~(make-forkexec-constructor
                                                          (list #$(file-append
                                                                   kdeconnect
                                                                   "/bin/kdeconnectd"))
                                                          #:log-file (string-append
                                                                      (getenv
                                                                       "HOME")
                                                                      "/.var/log/kdeconnectd.log")))
                                                (respawn? #t))

                              (shepherd-service (provision '(polkit-gnome))
                                                (requirement '(dbus))
                                                (start #~(make-forkexec-constructor
                                                          (list #$(file-append
                                                                   polkit-gnome
                                                                   "/libexec/polkit-gnome-authentication-agent-1"))
                                                          #:log-file (string-append
                                                                      (getenv
                                                                       "HOME")
                                                                      "/.var/log/polkit-gnome.log")))
                                                (respawn? #t))

                              (shepherd-service (provision '(poweralertd))
                                                (requirement '(dbus))
                                                (start #~(make-forkexec-constructor
                                                          (list #$(file-append
                                                                   poweralertd
                                                                   "/bin/poweralertd"))
                                                          #:log-file (string-append
                                                                      (getenv
                                                                       "HOME")
                                                                      "/.var/log/poweralertd.log")))
                                                (respawn? #t))

                              (shepherd-service (provision '(swayidle))
                                                (requirement '(dbus))
                                                (start #~(make-forkexec-constructor
                                                          (list #$(file-append
                                                                   swayidle
                                                                   "/bin/swayidle"))
                                                          #:log-file (string-append
                                                                      (getenv
                                                                       "HOME")
                                                                      "/.var/log/swayidle.log")))
                                                (respawn? #t))

                              (shepherd-service (provision '(xdg-desktop-portal))
                                                (requirement '(dbus))
                                                (start #~(make-forkexec-constructor
                                                          (list #$(file-append
                                                                   xdg-desktop-portal
                                                                   "/libexec/xdg-desktop-portal"))
                                                          #:log-file (string-append
                                                                      (getenv
                                                                       "HOME")
                                                                      "/.var/log/xdg-desktop-portal.log")))
                                                (respawn? #t))

                              (shepherd-service (provision '(xdg-desktop-portal-gtk))
                                                (requirement '(xdg-desktop-portal))
                                                (start #~(make-forkexec-constructor
                                                          (list #$(file-append
                                                                   xdg-desktop-portal-gtk
                                                                   "/libexec/xdg-desktop-portal-gtk"))
                                                          #:log-file (string-append
                                                                      (getenv
                                                                       "HOME")
                                                                      "/.var/log/xdg-desktop-portal-gtk.log")))
                                                (respawn? #t))))

        (simple-service 'auto-update home-shepherd-service-type
                        (list (shepherd-timer '(flatpak-update)
                                              #~(calendar-event #:hours '(18)
                                                                #:minutes '(0))
                                              #~("/run/current-system/profile/bin/flatpak"
                                                 "upgrade" "-y")
                                              #:requirement '(dbus))))))

(define %desktop-services-extended
  (append %user-desktop-services

          %fish-services %modprobe-services))
```

# dotfile

```scheme
(define %dotfile-services
  (list (service home-dotfiles-service-type
                 (home-dotfiles-configuration (directories '("../dotfiles"))
                                              (excluded '("^.git$"
                                                          "^.gitignore$"
                                                          "^.github$"))))

        (service home-files-service-type
                 `((".guile" ,%default-dotguile)
                   (".Xdefaults" ,%default-xdefaults)
                   (".config/git-credential-keepassxc" ,(computed-substitution-with-inputs
                                                         "git-credential-keepassxc"
                                                         (local-file
                                                          "../configs/files/git-credential-keepassxc")
                                                         (specs->pkgs "git"
                                                                      "fish")))
                   (".config/qt5ct/qss/rounded.qss" ,(local-file
                                                      "../configs/files/rounded.qss"))
                   (".config/qt6ct/qss/rounded.qss" ,(local-file
                                                      "../configs/files/rounded.qss"))
                   (".config/zed/settings.json" ,(computed-substitution-with-inputs
                                                  "zed.json"
                                                  (local-file
                                                   "../configs/files/zed.json")
                                                  (specs->pkgs "ccls"
                                                   "clang"
                                                   "maven"
                                                   "node"
                                                   "package-version-server"
                                                   "python-black"
                                                   "python-jsbeautifier"
                                                   "python-lsp-black"
                                                   "python-lsp-server"
                                                   "python-pylsp-mypy"
                                                   "rust-analyzer")))))

        (service home-niri-service-type
                 (home-niri-configuration (config (computed-substitution-with-inputs
                                                   "config.kdl"
                                                   (local-file
                                                    "../configs/files/niri.kdl")
                                                   (specs->pkgs
                                                    "brightnessctl"
                                                    "cliphist"
                                                    "dex"
                                                    "foot"
                                                    "fish"
                                                    "niri"
                                                    "wl-clipboard"
                                                    "xwayland-satellite")))))

        (service home-xdg-configuration-files-service-type
                 `(("gdb/gdbinit" ,%default-gdbinit)
                   ("nano/nanorc" ,%default-nanorc)))

        (simple-service 'prism-jdks home-files-service-type
                        (map (lambda (jdk)
                               (list (in-vicinity
                                      ".local/share/PrismLauncher/java/"
                                      (package-version jdk)) jdk))
                             (list openjdk25 openjdk21 openjdk17)))))
```

# environment-variables

```scheme
(define %extend-environment-variables
  '(("ANDROID_HOME" . "$HOME/Programs/Android/SDK") ("EDITOR" . "hx")
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
                        `(,@%extend-environment-variables ,@%xdg-base-directory-env-vars
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
```

# font

```scheme
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

(define %desktop-services
  (append %desktop-services-extended
          %dotfile-services
          %environment-variable-services
          %font-services

          %rosenthal-desktop-home-services))

(define %home-config
  (home-environment
    (packages (append %packages-list))

    (services
     (append %desktop-services))))

%home-config
```
