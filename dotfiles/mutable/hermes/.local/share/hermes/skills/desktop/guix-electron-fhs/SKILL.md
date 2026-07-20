---
name: guix-electron-fhs
description: Run prebuilt Electron / Chromium binaries (or Electron apps built from a checked-out source tree, e.g. via `npm run pack`) on Guix, where the binary hard-links FHS system libs (libglib-2.0, gtk, nss) that Guix does not provide on the default linker path. Uses `guix shell --container --emulate-fhs` + an electron library manifest, NOT nix-ld. Covers the three non-obvious Electron-specific pitfalls (WAYLAND_DISPLAY mismatch, GPU-process SIGILL under read-only /dev/dri, dbus machine-id). Complements appimage-run (which handles AppImages); use this for loose Electron binaries or source-built Electron apps.
---

# Run Electron / Chromium binaries on Guix via FHS container

## When to use
- You have an Electron app that you want on Guix, but it's NOT a packaged AppImage
  (so `appimage-run` doesn't apply). Two common cases:
  1. A loose prebuilt Electron binary (e.g. `release/linux-unpacked/AppName`).
  2. An Electron app built from a checked-out source tree (`npm install` + `vite build`
     + `electron-builder --dir`), producing `release/linux-unpacked/AppName`.
- The binary fails with `error while loading shared libraries: libglib-2.0.so.0:
  cannot open shared object file` (or similar gtk/nss errors) because Guix has no
  `/usr/lib` FHS path and the binary is hard-linked against it.

## Key insight
`--emulate-fhs` injects a hidden `glibc-for-fhs` that reads `/etc/ld.so.cache` — exactly
what the Electron binary expects. **Do NOT add `glibc` to the manifest** (it conflicts with
the injected version). All other GUI runtime libs must be listed explicitly.

This is the same mechanism `appimage-run` uses, but for loose/source-built Electron rather
than AppImage. Reuse `appimage-run`'s electron library set (see `references/manifest.scm`).

## Procedure
1. Build the electron app if needed (source case): `npm ci` + `npm run pack` (or
   `hermes desktop --build-only` for hermes). The unpacked binary lands at
   `release/linux-unpacked/<Name>`.
2. Drop `references/manifest.scm` (electron lib set) next to your launcher.
3. Use `references/run-electron.sh` as the launcher template: it builds the
   `guix shell --container --emulate-fhs` command and execs the binary.
4. In a real desktop session, run the launcher. If the window does not appear, the
   cause is almost certainly one of the three pitfalls below — NOT a missing lib.

## Three non-obvious Electron-specific pitfalls (each cost a full debug cycle)
These are THE reason a naive `--emulate-fhs` launch shows "process starts but no window":

1. **WAYLAND_DISPLAY mismatch.** If you hardcode `wayland-0` but the host session uses
   `wayland-1` (check `echo $WAYLAND_DISPLAY`), the container exposes a non-existent
   socket and Electron's ozone-wayland cannot reach the compositor → window hangs/fails.
   **Fix:** use the real `$WAYLAND_DISPLAY` (default to `wayland-0` only as fallback).

2. **GPU-process SIGILL (exitCode 4) under read-only /dev/dri.** Exposing `/dev/dri`
   with `--expose` (READ-ONLY bind) makes Chromium's GPU process SIGILL
   (`GPU.GPUProcessTerminationStatus2 mean=4.0`): the GPU process must issue write
   ioctls on `/dev/dri/renderD128`, which fail on a read-only device node.
   **Fix:** use `--share=/dev/dri` (READ-WRITE bind) — with a writable render node
   the hardware path works (verified: `glxinfo` in-container reports the real GPU,
   e.g. `Mesa Intel(R) Arc(tm) Graphics (MTL)`, and Electron's GPU process runs
   stable; its only observed termination was `exit_code=15` from an external
   SIGTERM, never SIGILL). Two more binds are required for hardware GL:
   - `--expose=/sys` (read-only): mesa's `drmGetDevice()` reads
     `/sys/dev/char/<maj>:<min>` to resolve the DRM device's PCI identity; without
     sysfs you get `MESA-LOADER: failed to retrieve device information` and a
     silent llvmpipe (software) fallback — the app runs but with NO GPU
     compositing/animations.
   - `--expose=/gnu/store` (read-only): Guix mesa hardcodes its DRI driver search
     path to absolute store paths (`/gnu/store/<hash>-mesa-*/lib/dri`); invisible
     store → `failed to load driver: i915` → llvmpipe fallback.
   Then pass `--ignore-gpu-blocklist` to Electron (in-container GPU probing can
   blocklist the card) and do NOT set `LIBGL_ALWAYS_SOFTWARE=1` or
   `--enable-unsafe-swiftshader` (both force software rendering, killing all
   in-app animations). Keep `LIBGL_ALWAYS_SOFTWARE` in the `--preserve` regex so
   users can set it externally as an emergency software-render fallback.
   Only if hardware GL proves impossible on some machine, fall back to
   `--disable-gpu` + `LIBGL_ALWAYS_SOFTWARE=1` (stable but animation-free).

3. **dbus machine-id missing.** FHS container has read-only `/var` and `/etc`, so
   `dbus-uuidgen --ensure` cannot write. DBus then prints
   `Failed to open "/var/lib/dbus/machine-id"`. **Fix:** `--expose=/etc/machine-id`
   (host has it; container reads it). This is cosmetic (Electron degrades gracefully
   without session dbus) but removes the noise.

**Recommended stable backend:** X11/xwayland, not pure Wayland. Set
`QT_QPA_PLATFORM=xcb`, `ELECTRON_OZONE_PLATFORM_HINT=x11`, expose `/tmp/.X11-unix`,
and pass `--ignore-gpu-blocklist` (hardware GL via the rw `/dev/dri` bind above).
Wayland-in-container needs the real compositor socket AND is more fragile; with
xwayland already running (`DISPLAY=:0` on the host), X11 is the most reliable.

## Verification without a desktop (headless)
You cannot prove a window appears from a headless terminal. But you CAN prove the
startup path is alive using **Xvfb**:
- `xvfb-run -a -s "-screen 0 1280x720x24" timeout 35 your-launcher`
- Success criteria: process reaches `createWindow`/app-ready WITHOUT
  `libglib-2.0.so.0` missing, WITHOUT `GPUProcessTerminationStatus2 mean=4` (SIGILL),
  and does not early-crash.
- See `scripts/verify-electron-xvfb.sh` for the exact probe.
- Caveat: Xvfb only falsifies "starts and crashes"; the real desktop still needs a
  human eye on the actual window. State this blocker honestly — never claim the GUI
  works from headless evidence alone.

## Pitfalls / gotchas
- **`write_file` does not set +x.** Scripts deployed via stow land as `-rw-------` and
  the stow symlink is also non-executable. `chmod +x` the SOURCE before/after writing.
- **stow `.stow-folding` is dangerous for packages owning `.local/bin`.** Folding folds
  the ENTIRE `.local/bin` dir into a symlink to the source, clobbering other packages'
  single-file symlinks (agenote/pi/appimage-run). Use `--no-folding` (or drop
  `.stow-folding`) for any package that adds `.local/bin/*`.
- **Background (non-login) shell lacks `~/.local/bin` in PATH.** When spawning a wrapper
  that lives in `~/.local/bin` via `terminal(background=true)`, call it by ABSOLUTE path,
  not by name — `hermes-update: command not found` otherwise.
- **`guix shell --container` rebuilds profile when the manifest changes** (adds a package
  like `xdg-utils`); first launch after a manifest edit is slower.
- **Editable source install (pip install -e) puts bundled assets in the checkout, not
  site-packages.** For a Python tool wrapped around Electron (e.g. hermes: `hermes-cli`
  pip-installed editable, Electron app built separately), `web_dist` lives in
  `checkout/hermes_cli/web_dist` (or is absent until built), NOT in the venv's
  site-packages. Don't grep site-packages for it.

## References
- `references/manifest.scm` — electron library manifest (copy + adjust)
- `references/run-electron.sh` — launcher template (container + X11 + hardware GPU)
- `scripts/verify-electron-xvfb.sh` — headless startup-path verifier

## Related
- `appimage-run` skill: same FHS-container technique but for AppImage files.
- `electron-wayland-ime`: fcitx5 IME under Wayland — different concern (input), use
  after this skill gets the window on screen.
