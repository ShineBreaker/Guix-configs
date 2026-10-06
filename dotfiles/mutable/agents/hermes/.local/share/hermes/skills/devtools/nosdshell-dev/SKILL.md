---
name: nosdshell-dev
description: Use when porting nosDshell modules to DDE 15.
version: 1.0.0
metadata:
  hermes:
    tags: [nosdshell, quickshell, dde15, qml, qt]
    related_skills: [qt-qss-adwaita-iteration, emacs-config-debugging]
---

# nosDshell dev (Quickshell shell → DDE 15)

## When to Use

Any task in the nosDshell repo (`~/Projects/Desktop/nosDshell` or a `p<N>` phase worktree): porting a module to the DDE 15 session UI, fixing QML that renders blank, black, or overlapping, syncing settings and migrations, or running the verify harness.

Work in this fork of Noctalia rewritten to the DDE 15 session UI. Constants come from `references/gxde-session-ui/` (map in `references/dde-reference-map.md`). The rules below are the ones that cost time when skipped.

## Always-on

- Read `AGENTS.md` and `DESIGN.md` before editing anything. `DESIGN.md` §3.x is binding per module, not advisory.
- Reference sources are read-only: take numbers and structure, never copy code, assets, or fonts.
- Work only in the phase worktree you were given (`nosDshell-p<N>`). The main checkout and sibling phase worktrees belong to other agents.
- Do not commit unless the brief says so. Before reporting "no commits", run `git log` — a concurrent agent may have committed your uncommitted tree mid-edit, which is a fact to report, not to hide.
- Verify only inside an isolated work dir: `NOSD_VERIFY_DIR=/tmp/nosd-verify-<phase> Scripts/dev/verify.sh ...` and the same for `Scripts/dev/lint.sh`. Never run `qs` against the user's live session.
- Kill leaked processes by exact PID. A pattern-based `pkill` that matches the shared harness name takes down other phases' runs.

## Procedure

1. Read `AGENTS.md`, `DESIGN.md`, and the phase brief. Pull the module's constants from the reference tree using `references/dde-reference-map.md`.
2. Run the scenes you are about to touch as a baseline and keep the log — later runs are compared against it.
3. Edit one module at a time; run `Scripts/dev/lint.sh --changed` after each logical step.
4. Iterate per scene: read the log for load and runtime errors *before* looking at the screenshot.
5. Finish with a full scene run, lint, `git diff --stat`, then write the report to the path the brief names.

## Debugging blank or overlapping QML

Go top-down. Do not start by measuring pixels.

1. **A blank screenshot means the config failed to load.** Grep the run log for `Failed to load configuration` and read the `file:line` it names. One syntax error blanks the whole component; no amount of styling shows through.
2. **Overlapping rows are a layout bug, not a paint bug.** Check the parent container for a hardcoded `height` and the child layout for `anchors.fill: parent`. A fixed height clips overflowing content, and `anchors.fill: parent` against a parent that is sized by its content collapses the rows onto each other. Let the container be content-sized and anchor the layout `left/right/top` instead.
3. Only after 1 and 2 are clean, measure geometry in the screenshot. Centring a row of widgets means two `Item { Layout.fillWidth: true }` spacers plus `Layout.alignment: Qt.AlignHCenter` on the target, not a fixed-width spacer.

Derived-component rules (load-time and runtime failures, not style nits):

- Declare every property you set on a derived component (`required property`). Passing an undeclared one fails at load with `Cannot assign to non-existent property "..."`.
- Never define `open()`, `close()`, or `toggle()` in a derived `SmartPanel` — you shadow the base implementation and recurse forever. Put custom lifecycle logic in a differently named function and hook it with `Connections { function onIsPanelVisibleChanged() }`.
- Ids declared inside `panelContent` are not reachable from the derived file's root scope; pass state across through a root-level property.
- Anything meant to render underneath a `SmartPanel`'s `contentLoader` must be declared inside `panelContent`; siblings at the derived root paint above it.
- Widgets that always render (`NBusyIndicator` only stops animating on `running: false`) need their own `visible:` bound to the same condition, or a dead spinner shows in an idle field.

Probes: `Logger.d` is off unless the shell runs in debug mode, so use `Logger.i` for always-visible probes — and delete them before finishing.

## Verify harness

- Invocation: `Scripts/dev/verify.sh <run-name> --scenes <comma-list>`; screenshots under `$WORK/shots/<run>/`, logs under `$WORK/logs/<run>.log`.
- `notify-send -A` blocks waiting for the notification server to answer. Background it, capture `$!`, take the shot, then `kill` and `wait` by that PID. A leaked one holds the D-Bus connection and every later run stalls after a few scenes.
- Scene selection word-splits on whitespace. When two scene names share a prefix (`lockscreen` / `lockscreen-error`), strip the longer one first, otherwise the shorter substitution leaves a stray fragment as the scene name.
- Compare runs by counting error-class lines (`ReferenceError|TypeError|is not defined|Cannot assign`) in the logs against the baseline, not by re-reading whole logs.
- Lint through the repo script: `Scripts/dev/lint.sh --changed` resolves the Qt import mirror that a bare `qmllint file.qml` cannot find, and would otherwise report false import errors.

## Settings, migrations, i18n

- A new setting needs four-place sync: default in `Commons/Settings.qml`, `Assets/settings-default.json`, a new numbered `Commons/Migrations/Migration<N>.qml`, the registry entry — plus the verify seed's `settingsVersion` bumped to match.
- Translation keys go in `en.json` only; `I18n.qml` falls back to English for the other locales. A missing key renders as `!!key!!`, so check the key exists in `en.json` before relying on it.
- When a layout stops reading a setting, mark it inert (comment in `Commons/Settings.qml` plus a disabled control in the Settings panel) and delete the reads, rather than leaving branches no path reaches. Configs keep loading because the key still exists.

## Reporting

- If a verify scene cannot reach a state headlessly — an auth-failure path that needs real keystrokes, for instance — the scene may exist while its screenshot stays unproduced. Name which part is verified and which is not; never substitute a plausible screenshot.
