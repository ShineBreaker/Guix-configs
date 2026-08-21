---
name: distrobox-xdg-forwarding
description: Diagnose and fix browser/URL links and display forwarding from inside distrobox containers. Covers the host-spawn -env whitelist root cause (DISPLAY/WAYLAND_DISPLAY dropped by default) and the correct fix pattern. Use for recurring "links don't open from the container" / "no DISPLAY" issues, especially in Guix-configs tools/linux-setup (justfile patch-xdg-open, register-scheme-handlers).
version: 1.1.0
metadata:
  hermes:
    tags: [distrobox, xdg-open, host-spawn, display-forwarding, guix, container, linux-setup]
---

# Distrobox xdg-open / Display Forwarding

## When to use
- Browser/URL links clicked inside a distrobox container don't open (nothing happens, or `xdg-open` prints errors).
- `xdg-open <url>` run inside the container prints `Error: no DISPLAY environment variable specified` then `xdg-open: no method available for opening '<url>'`.
- Recurring container XDG issues in this repo: `tools/linux-setup/justfile` tasks `patch-xdg-open` / `register-scheme-handlers`.
- Symptom is source-specific: links work from the host (or some sources) but fail from inside the container.

## Root cause (the non-obvious part)
distrobox generates `/usr/local/bin/xdg-open` inside the container. It forwards `xdg-open <url>` to the host via `host-spawn`, and remaps `XDG_RUNTIME_DIR` + `DBUS_SESSION_BUS_ADDRESS` to `/run/host/...`. It **omits `DISPLAY` and `WAYLAND_DISPLAY`**.

There are TWO independent blockers, both must be understood to avoid the half-fix:

1. **`-env` whitelist default `TERM` only.** `host-spawn --help` shows `-env` is "comma separated list of environment variables to pass to the host process. (default `TERM`)". So env vars you `export` in the container are NOT forwarded unless you add them to `-env`. First instinct "just `export DISPLAY=:0` in the script" does nothing — verified: container had `DISPLAY=:0`, host-spawn still delivered `DISPLAY=[]`.

2. **host-spawn hardcodes a `/run/host` path rewrite on `WAYLAND_DISPLAY`.** Whatever value you give `WAYLAND_DISPLAY` (relative `wayland-1`, or absolute `/run/user/1000/wayland-1`), host-spawn prepends `/run/host` → e.g. `/run/host/run/user/1000/wayland-1`, which does NOT exist on the host → Gecko "Failed to connect to Wayland display". This rewrite is for "run a GUI app *inside* the container" (container runtime maps `/run/host` → host `/`), NOT for "forward a command to the host".

   Compounding: the distrobox wrapper also rewrites `XDG_RUNTIME_DIR="/run/host/${XDG_RUNTIME_DIR}"` earlier in the script. Gecko builds the wayland socket path as `$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY` → `/run/host/run/user/1000/wayland-1`. So even getting DISPLAY through doesn't help if WAYLAND_DISPLAY is wrong.

This is why it recurs: a container rebuild / image update rewrites `/usr/local/bin/xdg-open`, wiping any manual patch. Re-apply via the justfile task after any recreate.

## Diagnosis (verify before editing)
1. Reproduce from inside the container:
   `distrobox-enter -nw <name> -- bash -c "xdg-open https://example.com"`
   If it prints `no DISPLAY`, you're on this path.
2. **Host-side probe (decisive).** Drop `scripts/probe-host-env.sh` on the HOST at `/tmp/probe-host-env.sh`, `chmod +x`, then from the container run `host-spawn /tmp/probe-host-env.sh`. Inspect `/tmp/probe-host-env.out` on the host. `DISPLAY=[]` proves host-spawn is dropping DISPLAY (the `-env` whitelist root cause).
3. **Rule out the PATH-leak misdiagnosis.** The container has an independent home; the host's Guix `xdg-open` (`~/.guix-home/profile/bin/xdg-open`) is NOT visible inside the container. `command -v xdg-open` inside the container resolves to `/usr/local/bin/xdg-open` (the host-spawn wrapper) regardless of login/non-login shell. Don't chase a "wrong xdg-open resolves / PATH leak" theory here — it's a red herring. (Confirmed: with a container PATH containing only guix/nix + `.local/bin` and no `/usr/local/bin`, `xdg-open` still resolved to the wrapper.)

## The fix (VERIFIED working form)
Do NOT rely on host-spawn's `-env` for DISPLAY/WAYLAND_DISPLAY — both blockers above make that path fail. Instead, bypass host-spawn's env handling entirely: have the forwarded *command* set the display vars on the HOST side, by wrapping the call in `sh -c`. host-spawn does not rewrite vars that appear inside the command string, so the host-side `xdg-open` receives the correct values directly.

```sh
# --no-pty branch (non-tty / gio / flatpak misbehave with a pty)
\tcd "${HOME}" > /dev/null 2>&1; host-spawn --no-pty -env TERM,DBUS_SESSION_BUS_ADDRESS,XDG_RUNTIME_DIR sh -c 'WAYLAND_DISPLAY=/run/user/1000/wayland-1 DISPLAY=:0 xdg-open "$@"' sh "$@"
# plain branch (tty interactive)
cd "${HOME}" > /dev/null 2>&1; host-spawn -env TERM,DBUS_SESSION_BUS_ADDRESS,XDG_RUNTIME_DIR sh -c 'WAYLAND_DISPLAY=/run/user/1000/wayland-1 DISPLAY=:0 xdg-open "$@"' sh "$@"
```

Key points:
- `WAYLAND_DISPLAY` is an **absolute host path** (`/run/user/1000/wayland-1`), NOT `wayland-1`. Gecko uses the absolute value directly and does NOT re-prepend the (broken) `XDG_RUNTIME_DIR=/run/host/...`. Verified: this is the only form that gets past "Failed to connect to Wayland display".
- `DISPLAY=:0` is the XWayland fallback (harmless; Wayland is preferred when WAYLAND_DISPLAY is valid).
- `-env` whitelist keeps only `TERM,DBUS_SESSION_BUS_ADDRESS,XDG_RUNTIME_DIR` — the D-Bus remap still works, and we deliberately do NOT put DISPLAY/WAYLAND_DISPLAY there (they'd get the `/run/host` rewrite or dropped).
- `sh -c '...' sh "$@"` is the correct multi-arg form: host-spawn runs `sh -c '...' sh <url>` on the host, so `"$@"` inside the inner script receives the URL.

Host display values are for a niri (Wayland) host with XWayland: Wayland socket at `/run/user/1000/wayland-1`, XWayland at `:0`. Adjust the absolute path if the host's `XDG_RUNTIME_DIR` or wayland socket name differs (check `ls /run/user/1000/wayland-*`).

## Wrong approaches (do NOT use — all verified to FAIL)
- **`export DISPLAY=:0; export WAYLAND_DISPLAY=wayland-1` + `-env TERM,DISPLAY,WAYLAND_DISPLAY,...`**: the `-env` form. Fails because (a) host-spawn drops DISPLAY unless in whitelist — but even when added, (b) host-spawn rewrites `WAYLAND_DISPLAY` to `/run/host/run/user/1000/wayland-1` (broken path). Verified: still "Failed to connect to Wayland display".
- **Embedding `env DISPLAY=:0 ...` into the command string**: `host-spawn "env DISPLAY=:0 xdg-open" "$@"` → host-spawn execs the whole string as a single binary path (no shell splitting) → exit 127 "command not found".
- **`WAYLAND_DISPLAY=wayland-1` (relative) inside `sh -c`**: host-spawn still rewrites it to `/run/host/...` (the rewrite fires on the env name regardless of where the value appears? No — inside `sh -c` it is NOT rewritten; BUT if you ALSO pass it via `-env` it gets rewritten). Keep WAYLAND_DISPLAY OUT of `-env` and use the absolute path inside `sh -c`.
- **`WAYLAND_DISPLAY=/run/user/1000/wayland-1` passed via `-env`**: host-spawn prepends `/run/host` → broken. Only safe inside the `sh -c` command string.
- **Chasing a PATH leak / wrong-xdg-open-resolution theory**: container home is independent; the host Guix `xdg-open` isn't visible there.

## Integrating with this repo (Guix-configs)
The home for this fix is `tools/linux-setup/`, now a dedicated script `scripts/patch-xdg-open.sh` (invoked by justfile task `patch-xdg-open`). The script uses Python to rewrite the two `host-spawn` lines to the VERIFIED form above (idempotent — safe to re-run). After any `distrobox create` / image update, run `just patch-xdg-open <name>` to re-apply.

When applying the patch inside the container, prefer a Python rewrite of the two `host-spawn` lines over `sed` (the tabs/`${host_command}`/`"$@"` quoting is fragile through nested shell+sudo+sed; and `sed` with `\t`/quoting fails silently). The repo script `scripts/patch-xdg-open.sh` is the canonical implementation — copy/adapt it rather than hand-editing.

## References
- `references/host-spawn.md` — host-spawn `-env` flag notes and the distrobox `/usr/local/bin/xdg-open` wrapper structure. **NOTE: the "before/after" in that file reflects an EARLIER broken `-env` attempt; the VERIFIED fix is the `sh -c` form in this SKILL.md's "The fix" section, now canonically implemented in `Guix-configs/tools/linux-setup/scripts/patch-xdg-open.sh`.**
- `Guix-configs/tools/linux-setup/scripts/patch-xdg-open.sh` — the canonical, idempotent implementation (Python rewrites the two host-spawn lines to the verified form). `just patch-xdg-open <name>` invokes it.

## Verification (how to confirm a fix worked)
From inside the container with an empty DISPLAY env (simulates an IDE-embedded terminal like qoderwork):
```
distrobox-enter -nw <name> -- bash -c "env -u DISPLAY -u WAYLAND_DISPLAY xdg-open https://example.com"
```
Expected: EXIT=0, no "no DISPLAY" / "no method available" / "Failed to connect to Wayland display" errors, and the host browser opens the URL (note: a single-instance browser may open a new tab rather than a new process, so don't rely on process count alone).

