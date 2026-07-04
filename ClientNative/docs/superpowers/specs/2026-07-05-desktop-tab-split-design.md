# Desktop Tab Split Design

## Summary

Add a temporary desktop-only split mode for workspace tabs. A user can drag one tab onto another tab in the desktop tab strip to open both tabs side by side in a temporary split pair. The top-level tab strip remains linear and unchanged. The split exists only as a presentation mode over two existing tabs.

## Goals

- Let the user drag one desktop tab onto another desktop tab to create a side-by-side split.
- Keep the existing linear `tabs` model and current tab-state stores intact.
- Show a central drag indicator between the two panes so the user can resize the split.
- Keep the behavior temporary and easy to collapse.

## Non-Goals

- No full multi-pane tab management.
- No separate tab strip per pane.
- No mobile or tablet split behavior in this change.
- No tab reordering as part of the split gesture.

## User Experience

### Create split

1. The user starts dragging a tab in the desktop tab strip.
2. The user drops the dragged tab onto another tab.
3. The app enters temporary split mode.
4. The drop target becomes the primary pane.
5. The dragged tab becomes the secondary pane.

### Split layout

- The existing desktop tab strip stays visible and keeps its current structure.
- The content area renders two existing tab contents side by side.
- A vertical drag indicator appears in the middle.
- Dragging the indicator changes pane widths.

### Exit split

- Closing either split tab collapses the split.
- Selecting a third tab from the tab strip collapses the split and shows the selected tab normally.
- A direct unsplit affordance is attached to the center handle.

## State Model

Add a temporary desktop split model, separate from the base tab list.

```swift
struct DesktopTabSplitState {
    var primaryTabID: WorkspaceTab.ID
    var secondaryTabID: WorkspaceTab.ID
    var fraction: CGFloat
}
```

Add to `MainViewModel`:

- `var desktopSplitState: DesktopTabSplitState?`

Add to `MainViewModel` behavior:

- `beginDesktopSplit(source:target:)`
- `updateDesktopSplitFraction(_:)`
- `clearDesktopSplit()`
- automatic cleanup if either tab no longer exists

## Rendering

### Main view

`MainView` keeps the current desktop tab strip. In the desktop content area:

- if `desktopSplitState == nil`, render the current single-tab content path
- if `desktopSplitState != nil`, render a two-pane horizontal split

Each pane reuses the existing `desktopTabContent(for:)` renderer for its tab.

### Tab strip

`DesktopWorkspaceTabStrip` becomes:

- a drag source for each tab
- a drop target for each tab

Dropping one tab onto another triggers `beginDesktopSplit(source:target:)`.

## Drag Indicator

The center divider must provide:

- a visible vertical handle
- a larger hit target than the visible line
- drag-based resizing
- a clear unsplit affordance

Resize bounds should clamp to a safe range such as `0.28 ... 0.72`.

## Edge Cases

- Dropping a tab onto itself does nothing.
- If the split references a missing tab, clear the split.
- If the secondary tab closes, keep the primary tab visible and clear the split.
- If the primary tab closes, promote the secondary tab to normal single-tab mode and clear the split.
- If a third tab is selected from the top strip, clear the split before rendering that tab.
- If existing chat retargeting changes one of the split tabs in a way that invalidates the pair, clear the split.

## Files Expected To Change

- `Sources/SloppyClient/MainTabs.swift`
- `Sources/SloppyClient/MainView.swift`
- `Sources/SloppyClient/DesktopWorkspaceTabStrip.swift`
- related focused tests under `Tests/SloppyClientCoreTests/`

## Testing

Add focused tests for:

- split state creation and cleanup
- split cleanup when tabs close
- split cleanup when another tab is selected
- drag/drop hooks in the desktop tab strip
- presence of the center drag indicator in split mode

## Recommendation

Implement this as a temporary overlay split pair over the existing tab architecture. This keeps the change small, avoids introducing pane-specific tab stacks, and leaves room for a future full multi-pane system if needed.
