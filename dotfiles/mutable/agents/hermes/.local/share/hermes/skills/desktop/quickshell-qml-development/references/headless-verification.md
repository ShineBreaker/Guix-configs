# Headless verification of a Quickshell shell

Run the whole shell headlessly under sway, drive it over IPC, and screenshot every
step. Without this loop a QML change is guesswork — the log only proves code ran.

## 1. Isolation

Give the run its own XDG tree so nothing touches the user's real config:

```bash
export NOSD_VERIFY_DIR=/tmp/<repo>-verify      # per-repo verify workspace
export XDG_STATE_HOME="$NOSD_VERIFY_DIR/state"
export XDG_DATA_HOME="$NOSD_VERIFY_DIR/data"   # seed .desktop fixtures here
export NOCTALIA_CONFIG_DIR="$NOSD_VERIFY_DIR/config/noctalia/"
export NOCTALIA_CACHE_DIR="$NOSD_VERIFY_DIR/cache/noctalia/"
```

Seeding matters: a headless image has almost no `.desktop` files, so an
applications grid renders empty and looks like a bug. Write a small set of
fixture entries spanning every category, controlled by an env flag
(`SEED_DESKTOP_APPS=1`), never touching real user dirs.

## 2. Session shape

`dbus-run-session -- bash` wrapping:

1. `sway -c $WORK/sway/config` with `WLR_BACKENDS=headless`,
   `WLR_LIBINPUT_NO_DEVICES=1`; wait for the `sway-ipc.*.sock`.
2. `swaymsg "output HEADLESS-1 resolution 1920x1080 position 0 0"` — otherwise
   the output geometry is whatever the default is and all pixel math is off.
3. `pipewire`/`wireplumber` if the scenes touch audio.
4. `qs -p <repo>` (or the project's shell binary) backgrounded; poll until
   `ipc call state all` answers.
5. `trap` a cleanup that kills shell, pipewire and sway.

## 3. Scene-driven screenshots

Model each screenshot as a scene so it is repeatable and the same command runs
the whole set:

```bash
call() { local s="${!#}"; set -- "${@:1:$#-1}"; qs -p "$REPO" ipc call "$@"; sleep "$s"; }
shot() { grim "$OUT/$1.png" && echo "saved $1.png"; }

run_scene() {
  case "$1" in
    launcher) call launcher toggle 1.5; shot launcher ;;   # keep it OPEN
  esac
}
```

Pitfalls:

- **Take the shot while the subject is open.** A `toggle ... ; shot; toggle`
  helper closes it before `grim` runs and every shot shows the bare desktop.
- **Match the scene's IPC call to a handler that exists.** An unknown handler
  returns `{"success": true}`-shaped output or an error, and the scene silently
  screenshots the wrong state. Grep the IPC service for the target name first.
- **An IPC call returning success only proves the handler was entered**, not
  that the state changed. Verify by looking at the screenshot.
- Drive the *right* screen: prefer the singleton's open screen
  (`LauncherState.fullscreenScreen`) over a current-screen detector, or the call
  lands on a screen with no launcher and writes nothing.

## 4. Acceptance

- A `saved X.png` line proves `grim` ran, nothing more. **Look at the PNG**
  (vision) or sample pixels — a collapsed 0x0 content item looks identical in
  the log.
- Grep the run log for `WARN`/`ERROR` and compare to a known-baseline scene: the
  same warnings in a passing scene are noise, new ones are yours.
- When a scene looks right on one run and wrong on the next, re-run it; async
  provider loads (XDG scans, clipboard) race the shot. Give the settling sleep
  enough room after the last state change.

## 4.1 Seeded-config matrix runs (settings modes, light/dark, dock directions)

When the job is proving a configuration matrix rather than one screenshot:

- **Run the harness from its real path.** Refactors move scripts
  (`Scripts/dev/` -> `Scripts/test/` here) while prose keeps the old path;
  `ls` the script before quoting it to the user or a subagent.
- **Seed keys by reading the defaults file** (`Assets/settings-default.json`
  or the repo's equivalent) plus the class that parses them. A wrong key is a
  silent no-op: the deep-merge writes it, the implementation reads nothing,
  and every screenshot looks fine while you tested the default state.
- **Prove the seed took effect, independently of the log.** A clean log does
  not prove the config was read. Diff `sha1sum` of shots that share a name
  across the seeded and unseeded runs: all-different = the seed is live;
  identical = the seed was ignored, or that scene is insensitive to it.
- **Reconcile the scene list against the PNG count before declaring done.**
  Multi-shot scenes legitimately emit more PNGs than scene names, so one PNG
  short means a scene failed silently. Also scan for collapsed shots
  (`find ... -size -100k`): grim happily captures a full-resolution blank
  frame, and the byte count is the tell.
- **In a matrix, conditions are signal, not noise.** Environment noise
  (no `NetworkManager`, no weather coordinates, no `.face` avatar, absent
  optional binaries) fires in every combination. A warning that appears only
  in the combinations exercising a given path is a real defect in that path —
  classify by conditional presence, not by error keyword.
- **Report the log as measured, never as briefed.** A supplied noise list is
  a hypothesis. When a preset noise entry fires zero times, or a defect type
  outside the list appears, state both divergences explicitly; copying the
  expectation into the report hides the findings.
- **Read the harness's own error summary first.** Mature verify scripts print
  an `=== error summary ===` tail block that is already the high-signal
  slice; widen to full-log greps only for categories it does not cover.
- **Write throwaway helper scripts as POSIX `sh`** (`#!/usr/bin/env sh`,
  `find/grep/sort/uniq` only): a `bash` shebang can fail execve in this
  Guix-Home environment while `sh` always resolves, and a helper that never
  runs costs the whole triage.

## 4.2 Log-triage classification for a report

Grep buckets and how to read them, in this order:

| Bucket | Grep shape | Meaning |
|---|---|---|
| Runtime type errors | `TypeError`\|`ReferenceError` | Real defects. Zero is the target. |
| Engine-named site | `<file>.qml:<row>:<col>` printed by the shell | Real defects — the engine resolved a source site. Not every WARN does. |
| Layout thrash | `Detected recursive rearrange` | Real defect in a layout that self-invalidates; fires per re-layout, so counts scale with how often the scene opens the view. |
| Binding loops | `Binding loop detected for property` | Real defect; fires per delegate instantiation, so hidden in short runs and loud in long ones. |
| Engine-rejected write | `Unable to assign`\|`Invalid write to global property` | Real defect — the engine refused a write, so a value was lost. |
| Environment | `.face`, no coordinates, protocol `not supported`, binary `not found`, plugin file `will create` | Baseline noise of the headless image; restate in the report but exclude from defect counts. |

Pitfalls:

- **A warning without a source site is weaker evidence than one with.**
  `Commons/Settings.qml[110:5]` in the aggregate tail can be benign startup
  sequencing while `Launcher.qml:387:13` names the delegate that broke. Rank
  by engine specificity.
- **Counts across runs are information, not just severity.** A defect that
  appears in 0/3 runs exercised its path rarely; one at 34/4/6 across
  conditioning runs is stable. Report the counts so the fix can be
  regression-checked later.
- **De-duplicate before reporting.** `grep -oE '<shape>' log \| sort \| uniq -c \| sort -rn`
  turns 269 WARN lines into a handful of rows; timestamps and pointer
  addresses are noise, so strip them (`sed 's/0x[0-9a-f]*//g'`).
- **Keep scene-to-file arithmetic visible.** Multi-shot scenes mean PNG count ≠ scene count; state the expected arithmetic in the report so a reader
  can audit "all scenes landed" without re-running.

## 6. Verifying the packaged build (store output, not the repo)

Boot `$OUT/bin/<wrapper>` with the same harness instead of `qs -p <repo>`: the
config and QML then come from the store, which is the only proof the package
is shippable. All of §1–§5 still applies, plus:

- Export the display explicitly before launching: sway sets `WAYLAND_DISPLAY`
  only for its own children, so a GUI started from the harness shell falls
  back to xcb and dies with `failed to create display`. Derive it in the
  inner shell: basename of `$XDG_RUNTIME_DIR/wayland-*` (excluding `.lock`),
  plus `QT_QPA_PLATFORM=wayland` and `XDG_SESSION_TYPE=wayland`.
- Gate the screenshot on compositor state, not on a fixed sleep or a log
  string: poll `swaymsg -t get_tree` until layer surfaces appear. A process
  that stays alive with zero layer surfaces is itself the finding — do not
  screenshot blindly and call the blank PNG a failure of rendering.
- A fresh-HOME first boot is slow (font Cip cache, settings migration) —
  budget minutes, not seconds. A blank shot at ~25 s with a healthy,
  error-free log means "too early", not "broken".
- Treat first-run notices (`plugins.json` missing, will create) as baseline
  noise; only log lines absent from a passing repo-source run count.
- Prove the wrapper PATH covers every runtime exec: helpers that shell out
  (`bluetoothctl`, `rfkill`, `dbus-send`, `pgrep`) need their providers in
  the package inputs AND in `wrap-program` PATH — build-time inputs do not
  cover runtime `exec`. Grep `export PATH` in the wrapper for each helper
  dir, then smoke-run the store binaries with a scratch HOME.
- When the vendored crate list outgrows the package file, split it into its
  own Guix module (e.g. `packaging/rust-crates.scm`) with a header saying how
  to regenerate it (`guix import crate --lockfile=...`), and reference it
  from the main file via load-path — never hand-edit generated stanzas.

## 4.3 Widgets that will not populate under headless sway

A dock/taskbar item that renders its chrome (icons, tray, clock) but never its
running-application entries is a *data* fault, not a layout one. Chase it in
this order:

1. **Log the filter inputs at the model builder, at `Logger.i` level.** The
   usual shape is a per-window predicate reading a field the headless
   compositor never fills:
   ```
   total_windows=N passed=M onlySameOutput=… screenName=… w.output=… w.workspaceId=…
   ```
   `total>0, passed=0` names the failure class without guessing. Log per
   window plus the aggregate — a bare `passed=0` cannot tell "enumeration
   empty" from "every row filtered".
2. **Never assume an object lacks a field because one constructor omits it.**
   A service that aggregates a backend's window objects may add fields the
   backend's own factory never set. "The backend's return shape has no
   `output`, therefore `w.output` is undefined" produced a confident wrong
   root cause here; the aggregate object **had** the field carrying a
   *different compositer's* output name. Measure the value the filter
   actually compares, do not derive it one hop up the chain.
3. **Cross-check the harness's enumeration against what it started.** A
   headless session should enumerate exactly the seeded windows. If the model
   contains app_ids the harness never spawned, or output names of the user's
   real displays, the compositor service is seeing beyond the isolated
   session — every screenshot of "running apps" is then partly someone
   else's desktop and earlier runs' attribution does not hold. Count
   toplevel-creation lines in the shell's qslog and compare to the seed
   count. Report it as a harness finding, not a widget defect.
4. **Screen-name equality is not name equality headlessly.** The shell's
   screen name comes from the compositer's own output naming; predicates like
   `w.output == screen.name` compare a *window-reported* string against it.
   Real sessions make these coincide per-output; headlessly the reported
   string can come from another compositer entirely. Treat any
   `onlySameOutput`-style filter as discharged in headless runs unless
   measured otherwise, and say so in the report.
5. **A widget that hides itself when its model is empty hides the defect.**
   `visible: hideMode !== "hidden" || hasWindow` turns `passed=0` into "the
   whole item area is gone" instead of an empty list, which screenshots read
   as a missing feature. When an entire region vanishes rather than rendering
   empty, treat *empty model + self-hiding* as one joint diagnosis and report
   both halves.
6. **`Quickshell.iconPath(name, fallback)` does not fail on a miss.** It
   returns a deferred `image://icon/<name>?fallback=…` URL that looks exactly
   like success; the theme lookup happens at render. When an icon shows the
   generic fallback while the theme demonstrably ships that file, the gap is
   between the name passed and the name on disk — check **case** for
   reverse-domain app_ids (theme stores `org.gnome.Xxx`; a normalize step can
   lowercase it before the lookup), and check whether a desktop entry was
   found at all (`foundEntry=false` means the fallback path ran and the raw
   app_id became the icon name). Fix by preserving the original case when
   passing an unmatched reverse-domain app_id, and by seeding a matching
   `.desktop` in the harness so the entry path resolves.

## 5. Cleanup discipline

- Overwrite logs per run rather than `rm` them if the environment forbids
  deletion; otherwise `trash-put` — never `rm`.
- Remove instrumentation once green: debug `Logger.i` lines and one-off counters
  go, functional fixes the debugging exposed (callback on load, null guard,
  corrected property name) stay.

