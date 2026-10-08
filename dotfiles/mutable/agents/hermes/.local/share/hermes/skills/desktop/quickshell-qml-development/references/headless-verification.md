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

## 4.3 Verifying the packaged build (store output, not the repo)

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

## 4.4 Layouts that look fine in every shot but still thrash — trust probes,
## not frames

A layout defect can be invisible in every terminal-state screenshot and still be
the report's most important finding. Symptom classes:

- **Height thrash across the load boundary.** An injected probe printing
  `implicitHeight` per re-layout reveals what a PNG cannot: a tab/panel whose
  height jumps among its real value, its loader placeholder, and a collapsed
  value *inside a single run*. Indicators: (1) the placeholder constant
  (`settingsTabEstimateHeight` or similar) appearing as one of the levels;
  (2) a collapsed level near *one* content row rather than zero, meaning
  "headers only"; (3) compensating machinery in the source — pending-snap
  state, a resnap timer, a quiet-period re-layout — which exists precisely to
  hide this from the user. Fix by making the container's height not collapse
  while children are unresolved (placeholder participation in the sum, or
  clamping to the previous height), **never by adding another snap**.
- **Row height leaking from content.** A settings row whose height is
  `max(fixedRowHeight, content.implicitHeight + paddings)` inherits the
  description's line count, so one control type renders at two widths in a
  page. Either cap the description at one line or hold the row height fixed.
  Measure the spread by scanning for the row's own background color, not by
  eyeballing the screenshot.
- **Disabled-looking controls need both states.** For any A/B of enabled vs
  disabled, capture both in the same batch (one seed with `enabled: true`, one
  with `enabled: false`) and sample the same pixel row in each. Also watch the
  inverse rule: `enabled: false` alone does not satisfy a spec that says the
  group *does not appear* in a mode — that needs `visible: false`.
- **Read the dim ratio, not the adjective.** Computing `disabled/enabled`
  brightest-pixel ratios per row classifies what "dimmed" means: a cluster
  around 0.6–0.7 is a *single* explicit dim (correct); a cluster around 0.36
  is a dim multiplied by a parent `opacity` (double-stacked — the defect); an
  inverse ratio means `opacity` brightened the control over a lighter row.
  Report the distribution, not "it looks dimmer".

Acceptance for these is the probe, not the frame: a flat height sequence per
key across repeated opens.

- **A *timing* fix is provable with frames when the frames are dense.** For
  "no bounce during open" criteria, inject no probe: burst the subject region
  right after the state change (~0.15 s cadence), cluster text/bright rows per
  frame, and require the content region's cluster sequence to be flat from the
  first frame in which the subject appears at all. Appears-complete is the
  the pass; appears-empty-then-fills is the old two-stage render. Density is the
  whole trick — a 1 s cadence is a terminal-state shot in a burst costume.
  **Measure the harness's real cadence before trusting it**: niri-IPC bursts
  can run at ~0.9 fps (≈1.1 s spacing) regardless of their nominal rate, far
  too sparse for a 160–300 ms motion — when that happens, record with
  wf-recorder instead (§4.8).

## 4.5 Widgets that will not populate under headless sway

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

## 4.6 Reactive i18n: prove the label follows, not that the key exists

A complete translation file proves nothing about runtime behaviour. Judge
adherence from the rendered label, in both languages:

- **Switch the language in the seed, restart the shell, and screenshot the
  label region** — crop around the section under test and read the crop, not
  the whole frame. The two crops are the evidence; the JSON only proves the
  key exists.
- **Baked-at-append models never refresh.** A `ListModel` filled imperatively
  with `I18n.tr(...)` values snapshots the language at append time; the key is
  there, the file is complete, and the widget still shows the old language
  until the process restarts. Run the restart-and-compare path before
  believing any "language switch works" claim.
- **Raw-id fallbacks look like translation bugs but are resolution bugs.** A
  name lookup that misses returns the internal id (`plugin:<id>`, the raw
  widget id). Localisation must route through the registry that resolves ids
  to display names, not through `I18n.tr` alone.
- **Elided is not untranslated.** `Notific...` beside `通知历史` in the other
  language's crop *is* adherence — the chip is narrow, not the key missing.
  Judge translation on un-elided rows and elide separately.

## 4.7 Real-compositor verification via a nested niri

When acceptance depends on real compositor behaviour — open animations and
their timing, layer-shell stacking, input paths no X11 bridge delivers — run
the shell inside a **nested niri that renders as a window on the user's live
session**, under a fully isolated HOME/XDG/dbus/runtime root. The live session
is only attached to; the target shell never runs in it and nothing is written
to it. Use `scripts/nested-niri-verify.sh` (boot / grab / burst /
restart-shell / stop); the rules below are what it encodes.

1. **Pass the live compositor socket as an absolute path.** With
   `XDG_RUNTIME_DIR` redirected, a relative `WAYLAND_DISPLAY=wayland-1`
   resolves inside the *new* runtime dir and the nested niri dies with
   `EventLoopCreation ... NoCompositor`.
2. **Write the nested `config.kdl` explicitly.** Three lines carry their
   weight: `output { transform "normal" }` (winit outputs default to flipped,
   which mirrors every screenshot), `hotkey-overlay { skip-at-startup }` (a
   fresh instance otherwise opens the "Important Hotkeys" window, and under
   winit `niri msg windows` returns `[]` — it cannot be closed over IPC), and
   `screenshot-path` pointed into the isolated root.
3. **Confirm the shell's layer surfaces before driving anything.**
   `NIRI_SOCKET=<nested> niri msg --json layers` must list the shell's
   namespaces. A live shell with zero layers is itself the finding — the same
   rule as the Limits section of `wayland-desktop-automation`.
4. **Screenshot over the nested socket only** (`NIRI_SOCKET` plus the nested
   `WAYLAND_DISPLAY`/`XDG_RUNTIME_DIR`, never the live ones).
   `screenshot-path` resolves to second resolution only — `%f` is not a
   supported specifier and lands in the filename literally — so **move each
   frame out of the landing directory as soon as it appears**, or a burst
   collapses onto one filename.
5. **Cold-state scenes restart the shell process, not just the panel.**
   "First open" timing only exists before the shell has instantiated the
   view; closing and reopening does not reproduce it.
6. **Shell-IPC calls issued in the first seconds after ready are swallowed.**
   Poll `ipc call state all`, let it settle, then issue `openTab`-style calls —
   otherwise the scene screenshots the default tab and reads as an IPC bug.
7. **Run the whole session from one script.** A foreground terminal call that
   needs `&` is rejected, and a session that loses its boot half-way leaves
   orphaned compositors behind. Source the harness's isolated env file before
   every scene/IPV call so the calls target the isolated shell. Seed the
   shell's config before boot (§4.1: `settingsVersion` in lockstep, or the
   first load runs migrations that rewrite the seed) and change settings by
   editing that file and restarting the shell — there is no in-shell writer
   for every key.
8. **Prefer the target repo's harness when it ships one.** A repo that keeps
   `Scripts/test/niri/` (or an equivalent) maintains its compositor config,
   settings seed, burst helper and stop script alongside the shell itself: it
   regenerates the nested `config.kdl` from the flags this shell needs and
   resolves the shell binary through PATH / `guix shell` instead of a store
   hash. Reach for `scripts/nested-niri-verify.sh` only when the repo has no
   harness of its own; when it does, name in the report which harness
   produced each claim.

- **Bring the shell down with the compositor.** `kill <niri.pid>` and
  `kill <shell.pid>`, then confirm with `pgrep -ax niri`: a compositor
  started under `dbus-run-session` can survive `niri msg action quit`, and a
  leaked instance keeps its window on the user's screen after your run.
- **Delete-denied hosts:** move throwaway artifacts with `mv` into a `trashed/`
  subdir of the isolated root rather than `rm` (`rm` is frozen in some
  sessions); a `rm -f` in the middle of a script then aborts the whole run.
- **Never hardcode a store path for the shell binary.** A literal like
  `/gnu/store/<hash>-quickshell-<ver>/bin/quickshell` points at a binary the
  next `guix upgrade` orphans, and the harness then runs a stale build with
  no error. Resolve through `PATH`, or fall back to
  `guix shell quickshell -- quickshell`, so the harness survives upgrades.
  Re-check the resolution before every run of a long session.
- **The nested session's private bus can die mid-run and the shell silently
  joins the wrong one.** If `dbus-run-session`'s daemon exits (socket file
  remains, connects get `Connection refused`), a shell started later inherits
  the *caller's* `DBUS_SESSION_BUS_ADDRESS` and registers its notification
  service on that foreign bus. Before testing notification paths,
  `dbus-send ... ListNames` the intended bus and confirm
  `org.freedesktop.Notifications` sits on it; if the daemon is gone, start a
  fresh private one (`setsid dbus-daemon --session --fork --print-address`)
  and restart the shell with that address exported.
- **Stale pidfiles from a killed run make a fresh `start-niri` report "niri
  died".** The wait loop can read the old pidfile before the new instance
  rewrites it. When restarting a nested env, clear the previous pidfiles and
  leftover sockets first (`mv` them aside).
- **Run harness scripts with output redirected to a file, never piped.** A
  backgrounded compositor inherits the script's stdout; `| tail` then waits on
  a pipe that never closes, the tool call times out, and the whole process
  group (nested niri + shell) is killed with it. `bash harness.sh > run.log
  2>&1` returns as soon as the script exits.

## 4.8 Frame-accurate animation verification (sub-300ms motions)

Static shots and logs cannot see "the motion never happened" — the end state is
pixel-correct either way (a missing `Behavior` animation is invisible in the
final frame and silent in the log). Record frames from the LIVE session's view
of the nested window and measure per frame:

- **Record with wf-recorder, not compositor screenshots.**
  `wf-recorder -c libx264 -g '<logical x>,<logical y> <logical W>x<logical H>' -f out.mp4`
  records the region at 60–140 fps *while content changes* and emits nothing
  while idle (only-on-update), which is exactly the density an animation needs.
  Region coordinates are the live compositor's logical pixels — derive the
  nested window's rectangle by scanning a `get_desktop_state` capture for its
  distinctive pixels (its wallpaper block). Stop with `kill -INT` (Ctrl+C
  equivalent) to finalize the file; pass `-c libx264` explicitly, since
  hardware-encoder probing may fail on headless hosts. Compositor-IPC bursts
  are the fallback, not the tool: measured ~0.9 fps here.
- **Extract and timestamp:** `ffmpeg -vsync 0 -i out.mp4 f-%03d.png` plus
  `ffprobe -show_entries frame=pts_time`; the non-monotonic-dts warnings from
  ffmpeg are harmless. Frame density per 0.5 s bucket localizes each animation
  segment without watching video.
- **Measure per frame, three complementary signals:**
  (1) 2D normalized cross-correlation of a template block from the settled
  state — robust to opacity, gives (dx, dy) travel; (2) region-mean brightness
  as an alpha/opacity proxy; (3) adjacent-frame diff bboxes — the bbox's
  advancing edge tracks slide direction (left edge sweeping right = horizontal
  exit; bottom edge growing = entry from below).
- **Read the sequences, not single frames.** A "single-frame jump" (no
  intermediate values between two states) is the evidence for instant
  transitions (menus, tooltips); a graded sequence is a real tween and its
  duration can be fitted against the intended easing curve (e.g. alpha 0.65 at
  109 ms into a fade fits InCubic at ~150 ms total, not 300 ms).
- **Cross-check geometry independently of opacity:** an entry from −12 px shows
  as a diff bbox 12 px taller than the resting state, and a block whose
  correlation collapses within one frame while its sibling fades gradually is
  the signature of an instant/disabled motion, not a fast one.

## 5. Cleanup discipline

- Overwrite logs per run rather than `rm` them if the environment forbids
  deletion; otherwise `trash-put` — never `rm`.
- Remove instrumentation once green: debug `Logger.i` lines and one-off counters
  go, functional fixes the debugging exposed (callback on load, null guard,
  corrected property name) stay.

## 6. Reporting

Report isolation and state honestly, in the user's terms:

- **Say which harness produced each claim.** "Walked through in the isolated
  harness on the same tree and binary" and "verified on the real desktop" are
  different claims; a nested-niri run is real-compositor but still not the
  user's own session.
- **Never let the brief's premise substitute for evidence.** A brief can state
  an earlier pass already covered something; check the timestamps/scopes and
  say when it did not.
- **Name what was not covered, with what it would take.** Missing frames,
  unprobed scenes, and the specific harness change that would close each gap
  belong in the report so the next session inherits the gap, not a false
  "all green".
