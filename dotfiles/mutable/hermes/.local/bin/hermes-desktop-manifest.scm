;;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;;;
;;; SPDX-License-Identifier: MIT
;;;
;;; hermes-desktop-manifest.scm — Guix manifest for running the Hermes
;;; Electron desktop app under `guix shell --container --emulate-fhs`.
;;;
;;; 与 appimage-run 的 electron 类型库集一致（Chromium 内核 GUI 运行时依赖）。
;;; 不要显式加 glibc——--emulate-fhs 会自动注入 glibc-for-fhs 并读
;;; /etc/ld.so.cache，正式 Electron 二进制期望的行为。

(specifications->manifest
  (list
    ;; 基线（appimage-run baseline-packages）
    "coreutils" "bash" "zlib" "mesa" "libglvnd" "alsa-lib" "fontconfig"
    "freetype" "nss-certs" "gcc-toolchain" "font-wqy-zenhei"
    ;; electron / chromium GUI 运行时栈
    "ffmpeg" "nss" "at-spi2-core" "cups" "libdrm" "p11-kit"
    "glib" "gtk+" "pango" "cairo" "libx11" "libxext" "libxfixes"
    "libxcb" "libxcomposite" "libxdamage" "libxrandr" "libxtst"
    "dbus" "expat" "eudev" "libxkbcommon" "xcb-util" "xcb-util-wm"
    "xcb-util-keysyms" "xdg-utils"
    ;; VA-API 视频硬件解码（GPU 进程 dlopen libva.so.2；缺它仅视频软解，非致命）
    "libva"
    ;; GSettings/dconf：GTK3 通过 GSettings 读 icon-theme / cursor-theme /
    ;; color-scheme（org.gnome.desktop.interface）。缺 schemas 则 GTK3 拿不到
    ;; 这些键，回退 Adwaita 图标 + 默认光标。dconf 后端直接读
    ;; ~/.config/dconf/user 二进制库（--share=$HOME 已挂入），无需 D-Bus。
    "gsettings-desktop-schemas" "dconf"))
