;;; electron-manifest.scm — Guix manifest for running an Electron/Chromium
;;; binary under `guix shell --container --emulate-fhs`.
;;;
;;; Do NOT add glibc: --emulate-fhs injects glibc-for-fhs (reads
;;; /etc/ld.so.cache). Explicit glibc conflicts with it.
;;; Library set mirrors appimage-run's `electron` type (Chromium GUI deps).

(specifications->manifest
  (list
    ;; baseline (appimage-run baseline-packages)
    "coreutils" "bash" "zlib" "mesa" "libglvnd" "alsa-lib" "fontconfig"
    "freetype" "nss-certs" "gcc-toolchain" "font-wqy-zenhei"
    ;; electron / chromium GUI runtime stack
    "ffmpeg" "nss" "at-spi2-core" "cups" "libdrm" "p11-kit"
    "glib" "gtk+" "pango" "cairo" "libx11" "libxext" "libxfixes"
    "libxcb" "libxcomposite" "libxdamage" "libxrandr" "libxtst"
    "dbus" "expat" "eudev" "libxkbcommon" "xcb-util" "xcb-util-wm"
    "xcb-util-keysyms" "xdg-utils"))   ; xdg-utils kills the "xdg-settings: failed to execvp" noise
