---
name: quickshell-qml-development
author: Hermes Agent
description: "开发、调试与操作 Quickshell QML shell：无头运行、shell IPC（noctalia msg）、设置与面板界面的视觉验收。触发：写改 Quickshell QML / 无头跑 shell 排查 / 面板与设置页验收 / IPC 交互——任一出现即调用。"
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
11. **`opacity` is not a disabled state on a surface of a different luminance.**
    `opacity: enabled ? 1.0 : 0.6` on a dark field composited over a lighter
    row *brightens* the control — `82×0.6 + 56×0.4 ≈ 70` reads as lit, not
    greyed, so a genuinely-unusable control looks like the highlighted one.
    Disable by changing colors explicitly (content text to the theme's
    disabled text color, field background to the theme's idle/overlay tone)
    and keep the control opaque. Prove the direction with pixel arithmetic on
    both states before shipping; the composite is almost never what intuition
    predicts across a luminance boundary.
12. **A disabled state must be ONE factor, not two.** Anything that dims a
    subtree and also dims its own text multiplies: a control that reads
    explicitly `×0.6` inside a parent already at `×0.6` lands at `×0.36` and
    looks dead next to its 0.6 siblings. Decide where the dim lives — the
    leaf reads its own `enabled`, or the parent dims and leaves the leaf
    opaque — never both. Level the disabled look by measuring,
    not by eyeing: per-row brightest-pixel ratios cluster at one value when
    the dim is single, and split into two clusters when stacked (§4.4).
13. **A slot sized by `fillWidth` + `preferredWidth: 1` cannot hold a CJK
    placeholder.** Two half-width slots sharing a row give each ~40 px of text
    while a 7-character zh-CN label needs ~70 px at `fontSizeS`, so any
    `elide: Text.ElideRight` on that `NText` truncates it to `添...` and the
    sibling empty slot shows only its icon. Compute the CJK width
    (pointSize × full-width chars) against the slot's share of the row before
    shipping a placeholder, or shorten the placeholder to what the slot fits.
14. **A `Behavior` animation can silently not run while the final state stays
    pixel-correct** — which is why it survives review, logs and static shots.
    Check these two shapes before touching animation parameters:
    (a) **two assignments to the same property in one JS tick**
    (`offset = from; offset = to;`): the second write reads the not-yet-advanced
    current value, so the Behavior animates current→same and the motion never
    happens. Split the writes across an event-loop turn (`Qt.callLater`, or a
    small Timer — the pattern a working sibling uses) or drive an explicit
    `PropertyAnimation`. Same-tick double writes produce NO motion at all;
    writes separated by an event-loop turn animate from the advanced value
    (partial travel, not the full offset).
    (b) **an `enabled:` guard on the Behavior** (`enabled: !Color.isTransitioning`)
    can be false at trigger time and kill the motion while a sibling Behavior
    without a guard (usually `opacity`) animates fine. When one of two parallel
    Behaviors moves and the other does not, diff their guards before anything
    else — a disabled Behavior is indistinguishable from "no animation intended"
    in the source until you compare it against its ungated sibling.
    Verify with recorded frames, not static shots — see
    `references/headless-verification.md` §4.8.

15. **An element anchored to a sibling must be declared as that sibling's
    sibling, not inside its closure.** `anchors.top: cardSurface.bottom`
    written inside the `cardSurface { ... }` block anchors a child to its own
    parent's bottom edge — it resolves to a position you did not intend (or
    nothing at all), with no warning. The same mistake hides hover buttons and
    stacked edges that "are in the code and logged as visible" yet never
    paint. Rule: anything positioned *outside* a rectangle's bounds lives at
    the rectangle's own level, next to it.
16. **A `Repeater`'s height never feeds the `Column`/`Row` it lives in.**
    `Column { Repeater { model: 2; delegate: Rectangle { height: 4 } } }`
    instantiates both children (`children.length` proves it) while the Column's
    `height` stays at one child's worth — the positioner does not wait for
    Repeater incubation, so a repeated stack silently collapses to its first
    item. For a fixed, known count, write the items out literally; for a
    dynamic count, give the positioner an explicit `height`.
17. **`qmllint`'s "Syntax error" line is downstream of the missing brace.**
    The parser only fails when it reaches a construct that cannot start where
    it is, so the reported line is typically the *next top-level object* after
    the unclosed block, dozens of lines below the defect. When the error line
    looks fine, count brace depth per line and find where the running depth
    returns to 0 early — that is the real gap. Do not edit at the reported
    line.

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
   **When the question is "did this element actually render, and where", log
   its geometry from the running shell** (`Logger.i("Mod", "h", x.height,
   "w", x.width, "vis", x.visible)`) instead of guessing pixel rows in a
   screenshot — a guessed y-range that misses the element produces a confident
   "it is not there" that costs several rounds to disprove. Log first, then
   scan exactly that range.
3. Never infer from `echo`/IPC exit codes alone: an IPC call returning
   `{"success": true}` only proves the handler was entered.
4. A `Failed to load configuration` chain ending in a `.qml:line` names the
   file that broke — the whole component is blank from that point down, so
   fix it before reading any screenshot (trap 17 explains why the named line
   is not where the brace is missing).
5. Remove the logs and restore project-conventional logging once green. Keep
   the functional fixes the debugging exposed (callbacks, guards); only the
   instrumentation goes.

## 4. Verification recipe

Full headless pattern (isolated XDG dirs, seeded fixtures, scene-driven
screenshots, log grep, vision check) is in
`references/headless-verification.md`. The short version: run the shell under
`dbus-run-session` + headless sway, drive it over IPC, `grim` after each step,
seed fixture inputs so the view is non-empty, and **actually look at the PNG** -
a "saved" line only proves grim ran. Settings-matrix runs (`--settings` seeds,
light/dark, dock modes) and report-grade log triage live in §4.1–§4.2 of that file.
Widgets that render chrome but never their running-application entries, and
icon fallbacks that look like successes, are §4.5. Layouts that look clean in
every terminal-state shot but thrash across the load boundary are §4.4 — those
are probe findings, not pixel findings.
Booting the packaged store output instead of the repo has its own traps
(display export, surface-gated shots, wrapper PATH) — see §4.3 of that file.
When acceptance depends on real compositor behaviour (open timing, layer
stacking, input paths no X11 bridge delivers) rather than on headless-renderable
state, §4.6–§4.7 cover reactive-i18n verification and the nested-niri harness
(`scripts/nested-niri-verify.sh`) that runs the shell on a real niri with the
live session untouched.

Judging a *restyled* settings/notification surface against a design doc — is the
row style uniform, is the 15 px group rhythm exact, is text elided — is §8.

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

## 8. Visual acceptance of a restyled settings/panel surface

A restyle pass ("convert these pages to DDE rows", "unify the list styling") is
judged on pixels, not on the diff. The procedure below is the cheap order that
finds every class of restyle defect:

1. **Drive it, then measure it. Take one screenshot per tab and sub-tab, then
   check the PNGs are distinct** (`md5sum`) before looking at any of them — a
   scene whose shot is byte-identical to its neighbour means the panel never
   opened, and every later judgement is of the wrong frame. Confirm with one
   `vision_analyze` per shot that the subject is actually in-frame.
2. **A screenshot loaded into context is evidence you already have — look at
   it.** Do not re-invoke `vision_analyze` on the same file to answer a
   follow-up, and do not run exhaustive pixel scans to settle a question the
   image answers at a glance. Reserve pixel arithmetic for the two things it
   is genuinely for: confirming an exact geometry value ("is this band 4 px or
   6 px") and proving a composited color equals a token. Deciding whether an
   element is *visible* is a looking task; a scan that returns "no pixels
   above threshold" at a guessed coordinate is not a finding, it is a wrong
   coordinate.
3. **Locate the panel in pixels before sampling anything.** A 1920×1080 frame
   with a desktop wallpaper puts a warm-toned backdrop beside a dark panel, and
   a naive coordinate lands on the wallpaper and reports a plausible color.
   Scan a row/column for the luminance jump, then crop the panel to its own
   file and sample only inside it.
3. **Judge "opaque black cards" by block geometry, not by a brightness
   threshold.** Real translucent rows over a bright wallpaper read as *warm*
   dark values (~`91,72,60`), so a cutoff like `r<25` that only catches
   `0,0,0` both misses the defect and flags legitimate controls. Group the
   sub-threshold pixels into contiguous bands first: a card is a wide
   low-height band, a slider is a narrow band that repeats at fixed intervals
   with its label, and a *preview* surface that legitimately shows solid color
   is one whose sampled pixels differ per item. Report the band, never a
   percentage.
4. **Verify spacing by measuring transitions, not by trusting the design
   number.** Walk a vertical pixel column and record the run-length of every
   constant-value segment; the inter-group gap is a clean run of the panel
   background between two bands of the row color. Compare the measured run to
   the token's value (`Style.settingsGroupSpacing` and the ui-scale version of
   it) — a hair off is a finding, an exact match is a pass.
5. **Read list-item selected states as a *marker*, not a color.** A selection
   implemented as accent text plus a checkmark at the row's trailing edge is
   the spec; one implemented as a filled background is not. Verify on an item
   that is actually selected (connected Wi-Fi, clicked template) rather than
   inferring from the component.
6. **Confirm placeholder text is legible, not merely present.** Zoom 8× into
   the control and read the glyphs; elide (`…`/`...`) is the report's finding
   and belongs to whoever owns the label's width (see trap 13). An empty slot
   showing only its icon is the same defect with the text clipped to nothing.
7. **Read the i18n key before calling a label a rendering bug.** A truncated
   label is a width problem whose fix lives in the string or the slot, and the
   string's real length is only known from `Assets/Translations/<locale>.json`.
8. **Report the walkthrough with its scope.** A nested-niri run touches the
   live session's compositor but not its config or services, and each claim
   should name which harness produced it; a brief's premise (a tab that
   "exists") is not evidence that the tab's groups are the ones specified.

## References

- `references/panel-window-and-layers.md` — PanelWindow sizing, layer shell
  layer/keyboard-focus/exclusion choices, multi-screen Variants geometry.
- `references/delegates-and-models.md` — delegate instantiation rules, model
  array shape, selection/currentIndex, provider result objects.
- `references/headless-verification.md` — isolated XDG verification harness,
  fixture seeding, scene script patterns, screenshot acceptance.
- `scripts/nested-niri-verify.sh` — boot a nested niri under an isolated
  HOME/XDG/dbus and grab/burst screenshots from it, for runs that need a real
  compositor (see §4.7 of the reference).
- `scripts/anim-capture.sh` — record a live-session region with wf-recorder
  while a trigger runs, then extract timestamped frames (see §4.8 of the
  reference).
