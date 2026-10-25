# cua-driver channels — session record (2026-09-04, niri + cua-driver 0.23.2)

## Symptom

Hermes `computer_use` tool: `capture` → 0x0 SOM, `list_windows` → `[]`,
`capture(app=screen)` → `X11Error BadMatch ... GetImage`. Same host, `doctor`
reported wayland_backend all true (screencopy/virtual-pointer advertised).

## Root cause

mcp channel runs the X11 backend: neither the gateway (pid 133) nor its
`cua-driver mcp` child had `CUA_DRIVER_RS_ENABLE_WAYLAND` in env
(checked via `tr '\\0' '\\n' < /proc/<pid>/environ`). Gateway DID have
`WAYLAND_DISPLAY=wayland-1` — necessary but not sufficient.

## Verified facts

- `get_config` → only `capture_mode`/`max_image_dimension`/PiP keys. No
  backend switch exists; the env var is the only control.
- `cua-driver call` requires a live `serve` daemon on
  `~/.cache/cua-driver/cua-driver.sock` ("daemon is not running" otherwise).
  The stale `.sock` + dead pid file from 08-31 had to be removed first.
- Serve started WITH the switch: `get_screen_size` → 3072x1920 s1.0;
  `list_windows` → real entry (`dev.zed.Zed`, layout bounds 0 — normal for
  that tool); `get_desktop_state` → 3.1MB PNG, visually confirmed.
- mcp channel does not reuse the serve daemon: tool `capture` still failed
  with the X11 error after the daemon was up.
- `cua-driver mcp` processes are short-lived (per tool-call session); each
  respawn inherits the gateway env, so only a gateway restart with the var
  fixes the tool channel.
- Tool inventory note: capture = `get_desktop_state`/`get_window_state`/`zoom`;
  every input tool (`click`, `type_text`, `press_key`, `scroll`, drag family)
  is XSendEvent-based (X11-only delivery).
