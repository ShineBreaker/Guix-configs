# gxde-session-ui reference map

Where each DDE 15 constant lives, so a port can pull numbers without re-reading the tree. Values are design facts, not code — take the numbers, never the source.

| DESIGN.md section | Reference file(s) | What defines it |
|---|---|---|
| session menu | `dde-shutdown/view/contentwidget.cpp`, `widgets/rounditembutton.cpp`, `dde-shutdown/skin/shutdown.qss` | row spacing, 140×140 button, 75×75 glyph, 10 px gap, countdown line 40 px under the row, button order and keybinds |
| lock screen | `dde-lock/timewidget.cpp`, `dde-lock/lockframe.cpp`, `dde-lock/skin/*.qss`, `session-widgets/userinputwidget.cpp`, `session-widgets/sessionbasewindow.cpp`, `session-widgets/lockcontent.cpp`, `widgets/useravatar.cpp`, `widgets/controlwidget.cpp`, `widgets/errortooltip.cpp` | 132 px band with 33 px margins, clock offset and weight, 100 px ringless avatar, name size and gap, 280×36 field, alert border + up-arrow tooltip, caps-lock glyph, control row spacing and trailing margin |
| OSD | `dde-osd/container.cpp`, `dde-osd/common.cpp`, `dde-osd/manager.cpp`, `dde-osd/kblayoutprovider.cpp` | 140×140 tile, 180 px bottom offset, glyph and progress offsets, 80×4 track, overdrive ceiling and tick marks |
| notifications / toasts | `dde-osd/notification/bubble.cpp`, `bubblemanager.cpp`, `appbody.cpp`, `actionbutton.cpp` | 300×70 base bubble, 48 px icon at (11,11), text column width, 70 px action strip, 20 px screen-edge inset, X position relative to the control centre |

`dde-osd/common.cpp` also holds constants shared across the session UI (180/140/80/110/25/30/40, volume max 1.5, overdrive) — check it before inventing a number.

## Reading the constants

- Numbers in these files are the spec. If the shell's current value disagrees, the shell is the thing that changes.
- Geometry in the C++ sources is absolute, not scaled: the QML side multiplies by `Style.uiScaleRatio` (or uses `Style` tokens) so a `uiScaleRatio != 1` keeps the same layout.
- Fonts referenced by the C++ (e.g. Maven Pro) are not bundled on this machine. Substitute a bundled equivalent and say so in the report rather than leaving a fallback that silently changes metrics.
