---
name: quickshell-qml-development
author: Hermes Agent
description: "Author, debug, and operate Quickshell QML shells headlessly and over shell IPC (noctalia msg)."
version: 1.1.0
license: MIT
metadata:
  hermes:
    tags:
      - quickshell
      - qml
      - wayland
      - layer-shell
      - panelwindow
      - shell-development
    related_skills: [wayland-desktop-automation, guix-electron-fhs, qt-qss-adwaita-iteration]
---

# Quickshell QML Development

## When to use

- Implementing or fixing a launcher / panel / bar / dock / OSD / lock-screen
  component in a Quickshell repo.
- A component renders nothing, renders only part of itself, or a layout looks
  collapsed (search row visible, body missing).
- Instantiation failures: `Cannot create delegate`, `Required property ... was
  not initialized`, `Cannot assign to non-existent property`.
- A view does not refresh after its data loads asynchronously, or an IPC-driven
  state change never reaches the view.
- Needing to prove a QML change actually rendered — headless sway + grim +
  vision verification.

How to build and debug a Quickshell shell component so it renders on the first
try, and how to prove it rendered.

## 1. The traps that cost the most time

Ordered by how often they bite. Each one fails **silently or with a warning**,
which is why they survive a whole debugging session.

1. **`PanelWindow`'s `anchors` group property is layer-surface anchoring, not
   layout.** `anchors { top: true; left: true; right: true; bottom: true }`
   pins the *surface* to the output edges; it does not size the content item.
   The content item stays 0x0, inner `ColumnLayout`s collapse, and only
   children with explicit sizes render — a 30 px search row shows while every
   `Layout.fillWidth/fillHeight` sibling vanishes. Give the window an
   `implicitWidth` / `implicitHeight` (from `modelData.width/height` or a fixed
   size) and let content anchor to `parent`.
2. **`Variants.delegate` must be the `Loader` itself.** Wrapping the Loader in
   a plain `Item` leaves an unsized orphan in the scene graph: the Loader never
   activates, nothing is created, and no error is printed. Copy the shape of a
   window that already works in the repo (`grep -rn "delegate: Loader"`).
3. **Never re-declare a `required property` the delegate component already
   declares.** `required property var modelData` inside `delegate: MyCell { ... }`
   when `MyCell.qml` declares it too produces `Cannot create delegate` +
   "Required property modelData was not initialized". Required properties live
   in exactly one place: the component file, never the usage.
4. **QML objects reject writes to undeclared properties — as a *warning*, not
   an exception.** `provider.providerId = id` on an object without that
   property prints `WARN ... Cannot assign to non-existent property`; `try/catch`
   never fires and the value is silently lost. Pass identifiers as function
   arguments (`registerProvider(p, id)`) instead of writing them onto objects.
5. **Asynchronous data loads must push into the view.** A provider that fills
   its own list after the view already rendered leaves the view showing the old
   (empty) snapshot — the log says "Loaded 97 applications" while the grid is
   empty. The provider must call back into the owner
   (`launcher.updateResults()`) at the end of the load, not just update state.
6. **A property binding that writes a property it reads is a binding loop**, and
   QML disables the binding — with only a one-line warning. Never put logging or
   counters inside a `readonly property var { ... }` binding; log from a
   function, `Component.onCompleted`, or an `onXChanged` handler.
7. **`Logger.d` is gated behind a settings flag.** In a headless verification
   harness that flag is usually false, so debug lines vanish and you conclude
   the code path never ran. Use an always-on channel (`Logger.i`) while
   debugging, then restore the project's conventional level when you clean up.
8. **Grid delegates get `GridView.view`, not `ListView.view`** — and it is null
   during early evaluation, so `root.gridView.currentIndex` throws
   `TypeError: Cannot read property 'currentIndex' of null`. Null-guard it.
9. **A `Loader`'s `sourceComponent` can only bind signals the component root
   declares.** `onRequestClose` on a Loader whose component root has no
   `signal requestClose` fails with "Cannot assign to non-existent property".
   Declare view-level signals on the view root, then bind them to the model.
10. **A screenshot string like `!launcher.search-placeholder!` means the i18n key
    is missing**, not that translation is broken. `I18n.tr` renders the raw key
    on a miss, so grep the translation JSON for the exact dotted path before
    assuming anything else.

## 2. Authoring order for a new shell component

1. Read the design doc, then read one **working sibling** in the same repo (OSD,
   bar, dock) and match its structure before inventing your own. House patterns
   beat personal taste here; a structure that already maps surfaces correctly
   saves all of §1.
2. **One state owner.** A singleton (open/close/mode/active model/pending
   intent) that the taskbar item, IPC and in-view toggles all route through.
   Views register their model with it; no view holds its own open state.
3. **Window wrapper.** `Variants` → `delegate: Loader` → `sourceComponent:
   PanelWindow`; `visible` bound to the state owner; explicit
   `implicitWidth/implicitHeight`; a namespace that identifies the feature and
   screen (`<app>-<feature>-<screen>`) so it is greppable in compositor trees.
4. **View.** Take all geometry in as properties from the wrapper (paddings,
   columns, cell size, insets) so the same view can be embedded elsewhere.
5. **Providers/models.** Register with explicit string ids kept in a map;
   reload paths call back into the owner (trap 5).
6. **Integration.** IPC handlers, settings keys with defaults, translation keys
   — all three, checked against the actual key paths used in code.
7. **Verify headlessly** (§3), looking at the real PNGs.

## 3. Debug loop when nothing (or half) renders

Work top-down; each step is cheap and eliminates a whole class:

1. Grep the run log for `WARN`/`ERROR` — "Cannot create delegate", "Required
   property ... not initialized", "Cannot assign to non-existent property"
   name the exact line.
2. Add one `Logger.i` at the top of the suspect component's
   `Component.onCompleted`. No line = the component was never created (wrapper
   problem, traps 1–2). Line present but no content = sizing problem (trap 1).
3. Never infer from `echo`/IPC exit codes alone: an IPC call returning
   `{"success": true}` only proves the handler was entered.
4. Remove the logs and restore project-conventional logging once green. Keep
   the functional fixes the debugging exposed (callbacks, guards); only the
   instrumentation goes.

## 4. Verification recipe

Full headless pattern (isolated XDG dirs, seeded fixtures, scene-driven
screenshots, log grep, vision check) is in
`references/headless-verification.md`. The short version: run the shell under
`dbus-run-session` + headless sway, drive it over IPC, `grim` after each step,
seed fixture inputs so the view is non-empty, and **actually look at the PNG** -
a "saved" line only proves grim ran. Settings-matrix runs (`--settings` seeds,
light/dark, dock modes) and report-grade log triage live in §4.1 of that file.
Widgets that render chrome but never their running-application entries, and
icon fallbacks that look like successes, are §4.3.
Booting the packaged store output instead of the repo has its own traps
(display export, surface-gated shots, wrapper PATH) — see §6 of that file.

## 7. Operating the running shell from an agent terminal (noctalia msg)

Noctilia ships its own CLI channel: `noctilia msg <command>` — run `noctilia msg --help`
for the full surface (`notification-dnd-set <on|off>`, `notification-dnd-status`,
`volume-mute`, `mic-mute`, `volume-set`, `brightness-*`, `bar-*`, `wallpaper-*`,
`theme-mode-set`, `panel-toggle ...`). The GUI launcher and the agent terminal are
different spawn contexts; the latter does not inherit the session env for free.

### 7.1 Env first — read the daemon's environ, never reconstruct the bus path

The CLI reaches the daemon over the session bus, so it needs what the daemon itself
holds: `DBUS_SESSION_BUS_ADDRESS` and `WAYLAND_DISPLAY`. The agent shell session has
neither. Take both from the live process:

```bash
PID=$(pgrep -x noctilia | head -1)
export DBUS_SESSION_BUS_ADDRESS=$(tr '\0' '\n' < /proc/$PID/environ | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p')
export WAYLAND_DISPLAY=$(tr '\0' '\n' < /proc/$PID/environ | sed -n 's/^WAYLAND_DISPLAY=//p')
noctilia msg notification-dnd-status
```

- Do not assume `$XDG_RUNTIME_DIR/bus` exists: on this host the greeter/session chain
  starts the bus under `/tmp/dbus-*`. `/proc/<pid>/environ` is the only source of
  truth — the same process-truth rule as §2.5.
- `pgrep -x <name>` matches the daemon comm exactly; `pgrep -f <pattern>` also matches
  the agent's own `bash -c` command line and always reports "alive".
- Reachability probe: `guix shell dbus -- busctl --user tree dev.noctalia.Debug` —
  if it lists the daemon's bus clients (it also registers
  `org.freedesktop.Notifications`), the bus talks and env was the only problem.
- `noctilia msg communication-error` (the status command printed it once when both
  vars were exported but the daemon was mid-restart) means a transient, not a
  config error; retry the same command once.
- No `gdbus` on this Guix Home profile; introspection is cheaper over
  `dbus-send ... org.freedesktop.DBus.Introspectable.Introspect` (guix shell dbus) or
  by reading the daemon's own `--help` surface first.

### 7.2 Read state back — `ok` proves the handler ran, nothing more

- Action verbs (`volume-mute`, `mic-mute`, `notification-dnd-set`) answer `ok`; state
  queries (`notification-dnd-status`, `pactl get-sink-mute @AUDIO_DEFAULT_SINK` or
  `wpctl get-volume @DEFAULT_SINK`) are the only evidence. With toggle verbs, sample
  state *before* as well as after.
- Debug toggles land on the opposite of the intended final state; close every such
  session with an explicit `-set`/read-back pass that canonicalizes the end state.
- `noctilia is not running` from the CLI means the channel was unreachable, **not**
  that the daemon died. Confirm with `pgrep -x noctilia` + `/proc/<pid>/environ`
  before restarting the shepherd service — a restart disrupts the live desktop.

## References

- `references/panel-window-and-layers.md` — PanelWindow sizing, layer shell
  layer/keyboard-focus/exclusion choices, multi-screen Variants geometry.
- `references/delegates-and-models.md` — delegate instantiation rules, model
  array shape, selection/currentIndex, provider result objects.
- `references/headless-verification.md` — isolated XDG verification harness,
  fixture seeding, scene script patterns, screenshot acceptance.
