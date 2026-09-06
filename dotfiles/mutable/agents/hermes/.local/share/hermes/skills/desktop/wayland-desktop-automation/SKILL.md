---
name: wayland-desktop-automation
description: Use when driving the Wayland desktop via cua-driver.
---
# Wayland desktop automation (cua-driver)

Two channels exist. They do NOT share backends — pick deliberately.

## 1. The two channels

| Channel | How | Env source | Backend |
| ------- | --- | ---------- | -------- |
| Hermes `computer_use` tool | spawns `cua-driver mcp` per session (stdio) | Hermes gateway process env | X11 unless gateway has the Wayland switch |
| Own daemon + `cua-driver call` | `cua-driver serve --socket ~/.cache/cua-driver/cua-driver.sock`, drive via `cua-driver call <tool> '<json>'` | whatever shell starts it | Wayland iff switch set at serve start |

The mcp channel never talks to your serve daemon. Fixing one does not fix the other.

## 2. The Wayland switch (env-only)

`CUA_DRIVER_RS_ENABLE_WAYLAND=1` (verified cua-driver 0.23.2). There is NO config-file equivalent — `get_config`/`set_config` only carry `capture_mode`/`max_image_dimension`/PiP keys. If Wayland capture is needed, the var must be in the process env at startup.

Failure signature of backend mismatch (NOT "no windows open"): `capture` returns 0x0 / `list_windows` empty / `call get_desktop_state` fails with `X11 error ... GetImage ... BadMatch`, while `doctor` still reports wayland globals advertised. Diagnose via `/proc/<pid>/environ` (gateway pid, mcp pid): check `CUA_DRIVER_RS_ENABLE_WAYLAND`, `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`.

## 3. Recipes

Serve daemon (background, survives tool calls):

```bash
rm -f ~/.cache/cua-driver/cua-driver.sock
CUA_DRIVER_RS_ENABLE_WAYLAND=1 WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000 \
  cua-driver serve --socket ~/.cache/cua-driver/cua-driver.sock
```

Verify: `cua-driver call get_screen_size '{}'` → width/height JSON; `cua-driver call list_windows '{}'` → real toplevels; `get_desktop_state` returns `screenshot_png_b64` (base64-decode → PNG).

Fixing the tool channel requires the var in the gateway env → gateway restart (disruptive, user does it): `CUA_DRIVER_RS_ENABLE_WAYLAND=1 hermes-desktop`. After restart, re-run tool `capture` to confirm before relying on it.

## 4. Limits

- All `click`/`type_text`/`press_key` tools deliver via XSendEvent (X11): they do not reach native Wayland windows. Screenshots + window geometry work; input needs a Wayland-native path (compositor-specific: wtype/wlrctl on wlroots).
- Desktop shell may lack `grep`/`sed`/`pgrep` on minimal Guix profiles — probe with python (`execute_code`) and absolute paths, not shell pipelines.

Session detail (commands + observed outputs): `references/cua-channels.md`.
