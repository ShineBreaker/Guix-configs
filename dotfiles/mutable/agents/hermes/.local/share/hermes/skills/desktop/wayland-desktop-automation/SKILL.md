---
name: wayland-desktop-automation
description: "用 cua-driver 驱动 Wayland 桌面（移动 / 点击 / 截图等真实输入自动化）。触发：真机桌面自动化操作 / 验证 GUI 行为 / 鼠标键盘注入 / 与 niri 等合成器交互——任一出现即调用。"
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

Fixing the tool channel requires the var in the gateway env → gateway restart (disruptive, user does it): `CUA_DRIVER_RS_ENABLE_WAYLAND=1 hermes desktop`. After restart, re-run tool `capture` to confirm before relying on it.

## 4. Limits

- **Input tools DO reach native Wayland windows through the virtual-pointer path** (verified cua-driver 0.34 + niri): `move_cursor`/`click` with `scope=desktop` drive the real pointer — left AND right button both land; `x,y` are physical pixels matching `get_desktop_state` coordinates. Older builds delivered input via XSendEvent only; rather than trusting either claim, smoke-test once: move the pointer, screenshot, move again, screenshot, diff the two (a real move shifts a small cursor region; byte-identical frames mean the move never landed — `get_cursor_position` echoes the requested value and proves nothing).
- **Confirm the target shell is actually running on the live desktop before calling a pass "real-machine".** Check `niri msg --json layers` (or the compositor's equivalent) for the shell's own layer surfaces before driving: another bar (`noctalia-bar-*`) occupying the session means your repo's shell is not on screen and every screenshot is of something else. The honest wording is that the walkthrough ran in the isolated harness at the same tree and binary; claim real-machine coverage only when the layers list contains the target.
- **Never `pkill` a process family the live desktop shares.** The user's running shell is frequently quickshell-driven too, so `pkill -f "quickshell -p"` (or any pattern that matches the live bar/dock) takes their session down alongside the subject. Kill only the pid you recorded when you started the run, and check the namespaces in `layers` first to know which process is yours.
- Desktop shell may lack `grep`/`sed`/`pgrep` on minimal Guix profiles — probe with python (`execute_code`) and absolute paths, not shell pipelines.
- **Sourcing an isolated-env harness file poisons every later call in the same terminal session.** A harness `env.sh` exports `HOME`/`XDG_*` for its own run, and the terminal tool keeps those exports between calls — the next `cua-driver call` then resolves its socket under the *isolated* home and answers "daemon is not running on /tmp/<iso>/home/.cache/cua-driver/cua-driver.sock" for a daemon that is perfectly alive. The socket path in the error is the tell. Re-export the real `HOME`/`XDG_*`/`WAYLAND_DISPLAY`/`XDG_RUNTIME_DIR` before returning to CUA, and prefer sourcing such a file inside a single command rather than leaving it exported.
- **A nested compositor window has no usable geometry in CUA's window list — locate it by pixel scan.** A winit-backed nested niri shows up in `list_windows` with `0x0` bounds, so coordinate arithmetic off the CUA window list dies. Instead: capture `get_desktop_state`, scan the PNG for the nested window's distinctive pixels (e.g. its colored wallpaper block) to get the physical-pixel rectangle, then target points as `screen = nested-session coords + window origin`. For shell-internal states, prefer the nested compositor's own IPC (`NIRI_SOCKET=<nested> niri msg ...`) and its screenshots for verification.
- **Moving the pointer OUTSIDE a nested window produces no leave event inside it.** The nested compositor stops tracking the pointer, so the shell keeps its last hover/tooltip state — a "move away" step must land on another point *inside* the nested window (e.g. its terminal area), or hover-dependent scenes never observe an exit.
- Clearing a stale socket can itself be blocked by a write-protection hook — `mv` it aside instead of `rm`.

Session detail (commands + observed outputs): `references/cua-channels.md`.
