# 用户配置文件

我会尽量地把更多的配置放在这里，而 `system-config.md` 只会放置一些保障系统正常使用所必须的配置，这样的好处在于:

1. 在首次安装系统的时候，可以少安装很多很多的软件包，这样安装系统的时长不会说长的太过分，也可以尽量减少因为网络问题而造成的报错
2. 系统和用户分开配置，这样在修改某一块的配置时不用将一整个系统都reconfighration一遍，方便多次迭代

---

## 模块

- [Main](#Main) -- **全配置文件的基本骨架**，建议优先查看这里的结构

- [Information](#information)
- [Modules](#modules)
- [Packages](#packages)
- [Services](#services)
- [Font](#font)

---

## Information

### 包含了一些系统的基本信息

```scheme
(load "../source/information.scm")
```

## Modules

```scheme
(use-modules (gnu)
             (gnu home)
             (gnu home services)

             (gnu packages)
             (gnu services)
             (gnu system shadow)

             (guix gexp)
             (guix packages)
             (guix utils)

             (rosenthal utils file)
             (rosenthal utils packages))
```

## Packages

### Emacs 相关软件包

```scheme
(define %emacs-packages-list
  (cons* (specs->pkgs+out
          ;; Emacs 核心与 Lisp
          "emacs-pgtk"
          "sbcl"
          "emacs-use-package"
          "emacs-general"

          ;; 补全与迷你缓冲区
          "emacs-vertico"
          "emacs-marginalia"
          "emacs-orderless"
          "emacs-consult"
          "emacs-embark"
          "emacs-corfu"

          ;; Evil 模式（Vim 模拟）
          "emacs-evil"
          "emacs-evil-collection"

          ;; 界面与外观
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

          ;; 开发工具
          "emacs-vterm"
          "emacs-yasnippet"
          "emacs-yasnippet-snippets"
          "emacs-rg"

          ;; 编程语言支持
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

          ;; Git 集成
          "emacs-magit"
          "emacs-magit-todos"
          "emacs-git-messenger"

          ;; 项目管理
          "emacs-projectile"

          ;; Org Mode 生态
          "emacs-org-modern"
          "emacs-org-roam"
          "emacs-org-appear"

          ;; 帮助与文档
          "emacs-helpful"

          ;; 邮件与日历
          "emacs-notmuch"
          "emacs-calfw"

          ;; 环境与工具
          "emacs-no-littering"
          "emacs-spinner"
          "emacs-yaml"

          ;; Tree-sitter（语法解析）
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

### Fish 相关软件包

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
```

### 用户安装的软件包

```scheme
(define %packages-list-extended
  (cons* (specs->pkgs+out
          ;; AI工具
          "claude-code"
          "codex"
          "opencode"

          ;; 影音
          "easyeffects"
          "helvum"
          "mpv"
          "nomacs"
          "obs-with-cef"
          "obs-pipewire-audio-capture"
          "obs-vkcapture"

          ;; 桌面环境相关
          "baobab"
          "cliphist"
          "dex"
          "fcitx5"
          "fuzzel"
          "libnotify"
          "nautilus"
          "swaylock-effects"
          "swayidle"
          "swww"
          "waypaper"
          "wl-clipboard"
          "xdg-dbus-proxy"
          "xdg-desktop-portal-gnome"
          "xdg-desktop-portal-gtk"
          "xdg-user-dirs"
          "xdg-utils"
          "xsel"

          ;; 社交
          "notmuch"
          "telegram-desktop"

          ;; 生产力工具
          "gimp"
          "keepassxc"
          "git-credential-keepassxc"
          "kdeconnect"
          "seahorse"
          "virt-manager"
          "zen-browser-bin"

          ;; 娱乐
          "heroic"
          "mangohud"
          "osu-lazer-bin"
          "prismlauncher-dolly"
          "steam"

          ;; 实用工具
          "age"
          "amule"
          "broot"
          "btop"
          "freerdp@3"
          "just"
          "kanata"
          "maak"
          "postgresql"
          "setxkbmap"
          "tmux"
          "tmuxifier"
          "tmux-xpanes"
          "winapps"
          "xprop"

          ;; 主题
          "orchis-kde-themes"
          "orchis-theme"
          "adwaita-icon-theme"
          "bibata-cursor-theme"
          "papirus-icon-theme"

          ;; 开发环境
          "ccls"
          "clang"
          "gitui"
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

          ;; QT框架相关
          "kvantum"
          "qt5ct"
          "qt6ct")))
```

## Services

```scheme
(use-modules (gnu home services desktop)
             (gnu home services dotfiles)
             (gnu home services fontutils)
             (gnu home services gnupg)
             (gnu home services shepherd)
             (gnu home services niri)
             (gnu home services sound)
             (gnu home services desktop)
             (gnu home services fontutils)
             (gnu home services syncthing)
             (gnu home services guix)

             (rosenthal services desktop))

(use-package-modules fcitx5
                     freedesktop
                     gnupg
                     kde-internet
                     linux
                     polkit
                     wm)
```

### modprobe 相关服务

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

### Fish 相关服务

```scheme
(use-modules (gnu home services shells))

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
```

### 桌面常用软件的相关服务

```scheme
(define %user-desktop-services
  (list (service home-syncthing-service-type)

        (service home-fcitx5-service-type
                 (home-fcitx5-configuration (themes (list
                                                     fcitx5-material-color-theme))
                                            (input-method-editors (list
                                                                   fcitx5-rime))
                                            (gtk-im-module? #t)
                                            (qt-im-module? #t)))))
```

### 利用 `home-shepherd-service-type` 来手动指定一些软件的自启动

这里利用 **scheme** 的 `lambda` 函数来包装了一个列表，这样的操作在我的配置文件里面多次出现，这样可以不用重复写很大一段内容

这也正是 Guix 的优势所在: 可以利用 Scheme 强大的生态来进行各种操作

```scheme
(use-modules (gnu packages rust-apps))

(define auto-startup
  (lambda (pkg path requirement)
    (shepherd-service (provision (list (string->symbol (package-name pkg))))
                      (requirement requirement)
                      (start #~(make-forkexec-constructor
                          (list #$(file-append pkg path))
                                #:log-file (string-append (getenv "HOME") "/.var/log/"
                                            #$(package-name pkg) ".log")))
                      (respawn? #t))))

(define %home-shepherd-services
  (list (simple-service 'essential-desktop-services home-shepherd-service-type
                        (list (auto-startup kanata "/bin/kanata" '(dbus))
                              (auto-startup kdeconnect "/bin/kdeconnectd" '(dbus))
                              (auto-startup polkit-gnome
                               "/libexec/polkit-gnome-authentication-agent-1" '(dbus))
                              (auto-startup poweralertd "/bin/poweralertd" '(dbus))
                              (auto-startup swayidle "/bin/swayidle" '(dbus))
                              (auto-startup waybar "/bin/waybar" '(dbus))
                              (auto-startup xdg-desktop-portal "/libexec/xdg-desktop-portal" '(dbus))
                              (auto-startup xdg-desktop-portal-gtk
                               "/libexec/xdg-desktop-portal-gtk" '(xdg-desktop-portal))))))

```

### 计时器服务

```scheme
(define %home-shepherd-timer-services
  (list (simple-service 'auto-update home-shepherd-service-type
                        (list
                          ;; 用于自动更新flatpak中的软件包
                          (shepherd-timer '(flatpak-update)
                                              #~(calendar-event #:hours '(18)
                                                                #:minutes '(0))
                                              #~("/run/current-system/profile/bin/flatpak"
                                                 "upgrade" "-y")
                                              #:requirement '(dbus))))))
```

### dotfiles 管理相关服务

#### 主要的一些内容

```scheme
(use-modules (gnu home services shells)
             (rosenthal services shellutils))

(use-package-modules java shells)

(define %dotfile-services
  (list (service home-dotfiles-service-type
                 (home-dotfiles-configuration (directories '("../dotfiles"))
                                              (excluded '("^.git$"
                                                          "^.gitignore$"
                                                          "^.github$"))))

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

#### 区别对待某些配置文件

有一些软件会需要在其配置文件内写入某个二进制的具体位置，此时就可以使用由 **rosenthal** 提供的 `computed-substitution-with-inputs` 函数

用法为：

1. 在需要的配置文件内以 `&&bin/foo&&` 的形式来写你所需要写入的二进制路径
2. 在 `specs->pkgs` 参数中写入能够提供这些二进制的软件包

```scheme
(define %home-files-services
  (list (service home-files-service-type
                 `((".guile" ,%default-dotguile)
                   (".Xdefaults" ,%default-xdefaults)
                   (".config/git-credential-keepassxc" ,(computed-substitution-with-inputs
                                                         "git-credential-keepassxc"
                                                         (local-file
                                                          "../source/files/git-credential-keepassxc")
                                                         (specs->pkgs "git"
                                                                      "fish")))
                   (".config/zed/settings.json" ,(computed-substitution-with-inputs
                                                  "zed.json"
                                                  (local-file
                                                   "../source/files/zed.json")
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
                                                    "../source/files/niri.kdl")
                                                   (specs->pkgs
                                                    "brightnessctl"
                                                    "cliphist"
                                                    "dex"
                                                    "foot"
                                                    "fish"
                                                    "fuzzel"
                                                    "niri"
                                                    "swaylock-effects"
                                                    "waypaper"
                                                    "wl-clipboard"
                                                    "xwayland-satellite")))))))
```

### 环境变量

#### 软件相关的环境变量

```scheme
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
```

#### 为了让软件尽量遵守XDG规范而提供的变量

```scheme
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
```

#### 引用以上的所有变量，并在这里放一些多行的环境变量

```scheme
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

## Font

### 字体相关配置

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
```

## Main

用于导入所有配置

配置文件利用 `define` 来分成了很多个模块，这样方便维护

但是要记住：**一定要导入对应变量**

```scheme
(define %packages-list
  (append %packages-list-extended %emacs-packages-list %fish-packages-list))

(define %desktop-services-extended
  (append %user-desktop-services
          %home-shepherd-services
          %home-shepherd-timer-services
          %fish-services %modprobe-services))

(define %desktop-services
  (append %desktop-services-extended

          %dotfile-services
          %home-files-services

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
