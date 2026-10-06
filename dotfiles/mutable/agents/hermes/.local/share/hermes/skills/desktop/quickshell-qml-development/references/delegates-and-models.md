# Delegates, models, and provider results

## 1. Required properties live in exactly one place

A delegate component declares them:

```qml
// MyCell.qml
Item {
  required property var modelData
  required property int index
  property var gridView: GridView.view   // may be null during early evaluation
}
```

The usage binds the rest, and **never redeclares**:

```qml
delegate: MyCell {
  width: resultsGrid.effectiveCellWidth
  iconSize: 32
}
```

Redeclaring a `required property` inline (because the component also declares it)
produces, for every item:

```
WARN ... Cannot create delegate
WARN ... Required property modelData was not initialized
```

The log names the **view's line of the `delegate:` block**, not the component
file, which sends you to the wrong file — check the component's own declarations
nfirst.

## 2. Grid/ListView handle access

- `GridView.view` inside a grid delegate (not `ListView.view`), and it is `null`
  during early evaluation — null-guard every `root.gridView.x` access.
- `NListView`-style wrappers usually expose `spacing` as an alias; `NGridView`
  historically had none. When adding a missing property (e.g. `spacing`), derive
  `effectiveCellWidth/cellHeight = cell - spacing` so existing consumers that use
  the default `0` are unaffected.

## 3. Model shape and split between list vs grid

A plain JS array works fine with `GridView`/`ListView`. When one model feeds two
different presentations (grid while browsing, list while searching), make the
split explicit with one named predicate instead of duplicating filters:

```qml
readonly property bool browsing: model.searchText.trim() === "" && !model.activeProvider
readonly property var listResults: root.browsing ? [] : model.results
readonly property var appResults: root.browsing ? model.results : []
```

Selection belongs to the model (`selectedIndex`), and the view binds
`currentIndex: model.selectedIndex`; the delegate highlights via
`index === gridView.currentIndex`, guarding for null.

## 4. Provider result objects

- Each result carries `provider` pointing at the producing provider object, plus
  an `onActivate` callback. Views should not special-case providers by name —
  compare object identity (`r.provider === appsProvider`).
- Providers need a handle on their owner to report back:
  `property var launcher: null`, assigned at registration time. **Pass
  registration ids as function arguments** (`registerProvider(p, "apps")`),
  never by writing `p.providerId = "apps"` — QML rejects writes to undeclared
  properties as a warning, silently dropping the value.
- Deferred/reloading data (`loadApplications()`, clipboard scans, XDG scans) is
  invisible to a view that already rendered. End every such load with a callback
  into the owner (`launcher.updateResults()`), or the empty snapshot sticks even
  though the log says the data arrived.

## 5. Binding loops

A `readonly property var { ... }` binding that writes a property it reads
(even a counter for logging) is a binding loop; QML disables the binding and
warns once. Log from functions and handlers, never from a property binding.

