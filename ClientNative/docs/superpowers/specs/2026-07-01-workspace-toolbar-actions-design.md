# Workspace Toolbar Actions Design

Date: 2026-07-01
Status: Draft for review

## Goal

Improve the workspace panel toolbar so frequent actions are directly accessible with dedicated buttons, while secondary actions remain in a tools menu.

The first implementation should add:

- dedicated toolbar buttons for primary file actions
- a separate tools/overflow menu for secondary actions
- `Cmd+T` to open or close that tools menu

## Existing Context

The client already has:

- a desktop-only `WorkspacePanel`
- file selection state in `WorkspacePanelViewModel`
- file tree and file preview in the right panel
- a web mode in the same panel

The request is specifically about making the file/workspace action menu faster to access and keyboard-friendly.

## Chosen Approach

We will expose separate always-visible toolbar buttons for the most common actions and keep a dedicated tools menu as overflow.

`Cmd+T` will toggle the tools menu rather than trigger a direct file action.

Why this approach:

- frequent actions become one click instead of two
- menu remains available for less common actions
- keyboard and pointer behavior stay aligned
- disabled/enabled state remains explicit from current selection

## UX Behavior

Toolbar behavior in the workspace panel:

- `Open in Zed` is a dedicated button
- `Reveal in Finder` is a dedicated button
- `Tools` is a separate menu button

If nothing is selected:

- `Open in Zed` is disabled
- `Reveal in Finder` is disabled
- `Tools` remains available

If a file or folder is selected:

- direct buttons become enabled when the action is valid
- menu shows secondary actions

Keyboard behavior:

- `Cmd+T` toggles the tools menu open/closed
- it does not trigger `Open in Zed` directly
- repeated `Cmd+T` closes the menu if it is already open

## Architecture

### 1. WorkspacePanelAction

Introduce a single action enum for toolbar/menu actions:

- `openInZed`
- `revealInFinder`
- `showToolsMenu`
- menu-only secondary actions as needed

This keeps view event wiring explicit and testable.

### 2. WorkspacePanelSelectionContext

Derive a compact selection context from current panel state:

- selected path
- selected node kind
- whether the selected item supports editor open
- whether the selected item supports reveal

This keeps button enablement logic out of view layout code.

### 3. WorkspacePanelToolbarState

Add a small state holder for toolbar behavior:

- `isToolsMenuPresented`
- `toggleToolsMenu()`
- shortcut integration for `Cmd+T`

This state should stay local to the workspace panel feature, not leak into chat/session state.

## Recommended Primary Actions

Primary toolbar buttons:

- `Open in Zed`
- `Reveal in Finder`
- `Tools`

The dedicated buttons are for high-frequency actions only.

Secondary actions should remain inside `Tools` so the toolbar does not become visually noisy.

## Error Handling

Failure states should be lightweight and local:

- invalid/no selection leaves primary buttons disabled
- failed external open/reveal shows inline status or banner
- shortcut should be ignored gracefully if panel is unavailable

## Testing

Add focused tests for:

- toolbar renders dedicated primary action buttons
- `Cmd+T` is registered
- `Cmd+T` toggles tools menu state
- primary buttons are disabled with no selection
- primary buttons are enabled for valid selection
- tools menu still exists independently from primary buttons

## Scope Boundaries

Included in this feature:

- dedicated toolbar buttons for primary actions
- tools menu toggle behavior
- `Cmd+T` shortcut

Not included in this feature:

- remappable shortcuts
- new file-operation backend endpoints
- multi-selection toolbar behavior
- redesign of the entire workspace panel header

## Recommendation

Implement dedicated toolbar buttons for the two highest-frequency actions and keep a separate tools menu for overflow, with `Cmd+T` mapped to toggling that menu.

This preserves discoverability, improves speed for common actions, and gives a clean keyboard story without overloading one shortcut with too much meaning.
