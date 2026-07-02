# Safari-Style Workspace Tabs Design

## Summary

Introduce a unified workspace tab container inside the `NavigationSplitView` detail area so macOS and iPhone share the same `WorkspaceTab` model and tab state ownership. The sidebar remains global and unchanged. On macOS, the detail area gets a Safari-inspired top tab strip. On iPhone, the active workspace tab remains full-screen in detail, while `ChatComposerView` becomes the bottom interaction surface for switching tabs horizontally and revealing a mixed tab overview with an upward swipe.

## Goals

- Keep `MainSidebarView` global and independent from workspace tab content.
- Keep all workspace tab state in `MainViewModel`.
- Preserve the existing `WorkspaceTab` model across platforms.
- Make chat, task chat, kanban, and files tabs behave as equal peers.
- Horizontal swipe on the bottom control switches between open tabs.
- Upward swipe on the bottom control reveals an overview of all open tabs.
- `+` creates a new blank chat tab.
- `Cmd+T` creates a new blank chat tab.
- Match Safari interaction patterns on iPhone.
- Make the macOS detail area visually resemble native browser tabs without changing the underlying workspace model.

## Non-Goals

- Changing sidebar content or making the sidebar tab-specific.
- Adding a separate iPhone-only tab model.
- Building a multi-window or system-level AppKit tabbed-window implementation.
- Introducing special grouping or filtering in iPhone tab overview; all tabs appear mixed together.

## Current Context

`MainViewModel` already owns:

- `tabs: [WorkspaceTab]`
- `selectedTabID`
- Per-tab state dictionaries for chat, kanban, and workspace files

`MainView` currently renders:

- `NavigationSplitView`
- A custom desktop tab strip in `desktopContentArea()`
- Detail content based on the currently selected `WorkspaceTab`

`ChatComposerView` already has separate phone and regular render paths, making it the correct place to attach iPhone-specific tab gestures and controls.

## Proposed Architecture

### Detail-Scoped Workspace Container

The workspace tab system remains scoped to `NavigationSplitView` detail. The sidebar stays outside that boundary and is not affected by tab switching.

`desktopContentArea()` becomes the shared workspace tab container entry point for all supported idioms:

- On macOS, it renders a desktop browser-style tab strip above the active tab content.
- On iPhone, it renders the active tab content plus a mobile tab interaction layer driven by `ChatComposerView`.

This keeps a single source of truth for tab content selection while allowing platform-specific chrome.

### Shared Tab Lifecycle

The following behaviors are shared:

- Opening a chat, task, kanban, or files target from elsewhere resolves to `open or select existing tab`.
- Selecting a tab only changes `selectedTabID`.
- Closing a tab disposes only that tab's local state and chooses the next visible tab.
- Creating a new tab inserts a blank chat tab with a fresh `ChatTabState`.

Add a dedicated helper in `MainViewModel` for blank tab creation so `+` and `Cmd+T` route through the same logic.

### Blank Tab Semantics

A new blank tab is always a chat tab whose `ChatScreenViewModel` has no bound session, project, or task context yet. It shows the existing empty chat screen and composer. The user then establishes context manually through normal app actions.

## macOS Design

### Visual Direction

Replace the current pill-style strip with a tighter browser-like top strip:

- A continuous material-backed bar across the top of detail.
- Tabs with compact horizontal density and slightly sloped or softly rounded top corners.
- The active tab visually merges into the content area.
- Inactive tabs appear recessed and lighter in hierarchy.
- A persistent trailing `+` button creates a blank tab.

This should feel native-adjacent to Safari/macOS tabbed windows, while remaining implemented in SwiftUI to preserve custom state handling.

### Behavior

- Click tab to activate.
- Click close affordance to close a tab.
- `Cmd+T` creates a new blank tab.
- Horizontal scrolling remains available when tabs overflow.

No overview mode is needed on macOS.

## iPhone Design

### Core Interaction Model

The detail area shows one active workspace tab at a time. `ChatComposerView` becomes the mobile tab interaction surface:

- Swipe left or right on the composer switches to previous or next tab.
- Swipe upward on the composer opens the overview of all tabs.
- Tapping `+` in the composer creates a blank tab.

The composer still sends messages normally, so tab gestures must coexist with text entry and send controls.

### Gesture Rules

Horizontal switching:

- Only begins when the drag is primarily horizontal.
- Uses thresholded paging behavior so small drags do not accidentally change tabs.
- Switches by one tab per completed gesture.

Upward overview reveal:

- Only begins when the drag is primarily vertical and upward.
- Uses a threshold large enough to avoid conflict with normal composer taps or text interactions.

Gesture priority should favor text field editing and button taps over overview activation when the user's intent is clearly input-focused.

### Tab Overview

The overview is a Safari-style mixed grid of all open tabs:

- Chat, task chat, kanban, and files tabs appear together in one collection.
- Each card shows title and lightweight type-specific preview chrome.
- Tapping a card activates that tab and dismisses the overview.
- Each card includes a close affordance.
- A `+` affordance creates a blank tab.

No grouping, filtering, or sidebar coupling is introduced.

### Mobile Chrome Ownership

The mobile overview and swipe navigation remain inside detail. They do not live in `MainSidebarView`, and they do not depend on a phone-specific root `TabView`.

## Component Changes

### `MainViewModel`

Add or adjust responsibilities:

- Blank tab creation helper.
- Neighbor tab lookup for swipe navigation.
- Overview presentation state for iPhone detail chrome.
- Optional lightweight tab preview metadata helpers.

Keep `tabs`, `selectedTabID`, and per-tab state dictionaries as the only source of truth.

### `MainView`

Refactor `desktopContentArea()` into a platform-adaptive detail workspace container:

- Shared active-tab rendering.
- Desktop top strip chrome.
- Mobile overview layer and bottom-driven gesture flow.

The old phone root `TabView` does not return.

### `ChatComposerView`

Extend only the phone path:

- Add optional callbacks for previous tab, next tab, show overview, and create tab.
- Add gesture handling around the phone composer shell rather than inside the text field itself.
- Preserve current message send behavior and layout expectations.

The regular/macOS composer remains focused on message composition.

## Data Flow

1. User opens or creates a tab.
2. `MainViewModel` updates `tabs`, tab state dictionaries, and `selectedTabID`.
3. Detail container re-renders the active `WorkspaceTab`.
4. On iPhone, composer gestures invoke `MainViewModel` tab selection helpers.
5. On iPhone overview selection, the chosen tab becomes active and overview dismisses.

## Error Handling

- If a selected tab loses its backing state unexpectedly, keep the existing placeholder behavior instead of crashing.
- If swipe navigation has no neighbor tab in the requested direction, ignore the gesture.
- If a close action removes the last tab, immediately create or select a blank tab so the detail area never becomes stranded on iPhone.

On macOS, an empty-state view may still be acceptable if desired, but the preferred behavior is also to keep at least one blank tab available for consistency.

## Testing Strategy

Add focused source and behavior tests for:

- Blank tab creation helper.
- `Cmd+T` wiring for new tabs.
- Neighbor-tab selection logic.
- Closing behavior for first, middle, last, and only tabs.
- Mobile overview state transitions.
- `ChatComposerView` source coverage for mobile tab gesture hooks.
- `MainView` source coverage ensuring detail-scoped workspace container remains the integration point.

Prefer narrow tests in:

- `Tests/SloppyClientCoreTests`
- `Tests/SloppyFeatureChatTests`

## Risks and Mitigations

- Gesture conflicts in `ChatComposerView`.
  Mitigation: thresholded directional gesture detection and explicit tap preservation.

- Divergence between macOS and iPhone tab behavior.
  Mitigation: preserve one shared tab model and keep only chrome platform-specific.

- Overview complexity on iPhone.
  Mitigation: ship a mixed static grid first, using lightweight previews rather than live miniature rendering.

## Implementation Notes

- Prefer SwiftUI-first implementation for both platforms.
- Reuse existing `WorkspaceTab`, `ChatTabState`, `ProjectKanbanTabState`, and `WorkspaceFilesTabState`.
- Keep tab chrome separate from tab content rendering so platform styling can evolve independently.
- Avoid adding text-based heuristics or mode inference; use explicit callbacks and state.
