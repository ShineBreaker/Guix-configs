# PanelWindow sizing, layers, multi-screen geometry

## 1. Sizing the content item

`anchors` on `PanelWindow` is a **group property for layer-surface anchoring**
(`top`/`left`/`right`/`bottom` pin the surface to output edges). It has **nothing**
to do with sizing the content item. A fullscreen-style surface still needs:

```qml
implicitWidth: modelData?.width ?? 0
implicitHeight: modelData?.height ?? 0
```

and inner content anchored to `parent` (`anchors.fill: parent`).

**Symptom without it:** the window maps and covers the whole output, but only
children with explicit `width`/`height` or `Layout.preferred*` sizes render —
every `Layout.fillWidth/fillHeight` sibling collapses to 0. A dialog shell window
needs a fixed size (or one derived from its content) instead.

Do **not** set `width`/`height` when the surface is anchored to fill the output —
read from `implicitWidth/implicitHeight` like the house windows do, so compositor
driven resize still propagates.

## 2. Choosing the layer

| Layer | Use for | Keyboard focus |
|---|---|---|
| `WlrLayer.Background` | Wallpaper | None |
| `WlrLayer.Bottom` | Desktop icons / panels that stay below windows | None |
| `WlrLayer.Top` | Panels, launchers, any interactive shell UI | `Exclusive` while open, `None` while closed |
| `WlrLayer.Overlay` | Lock screen, launcher overlays, OSD | `Exclusive` while open |

Always:

```qml
WlrLayershell.namespace: "<app>-<feature>-" + (screen?.name || "unknown")
WlrLayershell.keyboardFocus: isActive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
```

- `keyboardFocus` on a hidden window steals focus. Bind it to the same
  `visible` source so closed windows never take focus.
- `exclusionMode: ExclusionMode.Ignore` when the surface must not reserve
  output space (overlays, launchers); leave the default for bars/docks that
  need to reserve a strut.
- Namespaces are how you find your surfaces in `swaymsg -t get_tree`, so make
  them unique and greppable — two windows sharing a namespace is a debugging
  trap.

## 3. Multi-screen Variants geometry

```qml
Variants {
  id: root
  model: Quickshell.screens

  delegate: Loader {
    id: screenItem
    required property ShellScreen modelData
    active: true          // surface exists all session; visibility is separate
    asynchronous: false

    readonly property bool isActive: LauncherState.fullscreenScreen === modelData

    sourceComponent: PanelWindow { /* geometry from screenItem.modelData */ }
  }
}
```

Derive all geometry from `modelData`:

- `width` / `height` — the output size (fullscreen surfaces)
- Bar thickness and safe insets: query the repo's bar service per screen name
  (`BarService.hasTaskbarOnScreen(modelData.name)`, `Settings.getBarPositionForScreen(name)`)
  rather than assuming a single value.
- Grid geometry: compute columns from available width, then let cell size be
  `floor(width / columns)` with a budgeted minimum; keep the numbers as readonly
  properties on the delegate so the view stays declarative.

Never name the delegate's boolean `active` — that collides with `Loader.active`.
Use `isActive`.

## 4. Window that opens and closes

Keep the surface alive for the session and gate visibility; destroying and
recreating layer surfaces on every open/close costs a remap and can drop keyboard
focus. When you do need lazy creation, mirror the working house pattern:
`active` starts false and flips on the first open, `visible` stays bound to the
state owner.

