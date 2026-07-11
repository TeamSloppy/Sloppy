# Workspace Terminal Drawer Design

## Summary

Add an embedded workspace terminal drawer to the native client using `migueldeicaza/SwiftTerm`. The terminal opens from the bottom of the active workspace area with `cmd + j`, starts in the current project directory, and keeps a separate terminal session for each workspace tab.

The architecture should be cross-platform from the start, while the first full terminal host is implemented for `macOS`. iPadOS and visionOS should share the same tab-scoped terminal state, commands, and layout contract so they can adopt a platform host without changing the surrounding workspace shell.

## Goals

- Add `SwiftTerm` as a package dependency for the client app.
- Show a bottom terminal drawer inside the active workspace content area.
- Toggle the drawer with `cmd + j`.
- Start the shell in the current project directory.
- Keep an independent terminal session per workspace tab.
- Preserve terminal height and visibility state per tab.
- Design the terminal layer so the surrounding workspace shell is cross-platform.

## Non-Goals

- No floating terminal window.
- No right-side terminal mode inside the existing workspace panel.
- No shared terminal session across tabs.
- No dual terminal drawers in both panes of desktop split mode in the first iteration.
- No full terminal implementation for iPadOS or visionOS in this change if the host capability is not ready there yet.

## Existing Context

The client already has:

- tab-scoped UI state in `Sources/SloppyClient/Navigation/Main/MainTabs.swift`
- desktop workspace composition in `Sources/SloppyClient/Navigation/Main/MainView.swift`
- top-level workspace orchestration in `Sources/SloppyClient/Navigation/Main/MainViewModel.swift`
- an existing right-side `WorkspacePanelView`
- a temporary desktop split presentation over existing tabs

This means the terminal should plug into the existing tab shell instead of creating a second workspace surface model.

## Chosen Approach

Implement the terminal as a tab-scoped bottom drawer owned by `WorkspaceTabState` and orchestrated by `MainViewModel`.

Why this approach:

- matches the requested UX from the screenshot
- aligns with the existing tab/state architecture
- supports one independent session per tab naturally
- keeps terminal lifecycle local to tab lifecycle
- allows a shared cross-platform API even if the rendering host differs by platform

## User Experience

### Open and close

- `cmd + j` toggles the terminal drawer for the active tab.
- If the drawer is closed, toggling opens it and focuses the terminal.
- If the drawer is open, toggling closes it and returns focus to the main tab content.
- The drawer is hidden by default for new tabs.

### Layout

- The terminal appears at the bottom of the active workspace area.
- It is part of the main layout, not an overlay window.
- The main tab content remains above the terminal.
- A resize handle separates the content area and the terminal drawer.
- The initial height should be a comfortable default such as about 30% of the content area.

### Per-tab behavior

- Each tab keeps its own terminal session.
- Each tab keeps its own terminal height.
- Switching tabs restores the previous session, buffer, and height for that tab.
- Closing the drawer does not terminate the running shell.

### Split mode

- In desktop split mode, the terminal belongs to `selectedTabID`.
- Only one terminal drawer is shown at a time in the first version.
- Selecting a different tab retargets the terminal drawer to that selected tab.

## State Model

Add terminal state to `WorkspaceTabState`.

```swift
@MainActor
final class WorkspaceTerminalState {
    var isPresented: Bool
    var height: CGFloat
    var workingDirectory: URL?
    var sessionID: UUID
}
```

Add to `WorkspaceTabState`:

- `var terminalState: WorkspaceTerminalState`

Add to `MainViewModel` behavior:

- `toggleTerminalForSelectedTab()`
- `openTerminalForSelectedTab()`
- `closeTerminalForSelectedTab()`
- `terminalState(for:)`
- `ensureTerminalSessionStarted(for:)`
- `resolveWorkingDirectory(for:)`
- terminal session cleanup when a tab closes

The `terminalState` should be created for every new tab so the shell contract is uniform even before the session starts.

## Terminal Runtime Layer

Introduce a dedicated terminal runtime layer instead of wiring `SwiftTerm` directly into `MainViewModel`.

Recommended types:

```swift
protocol WorkspaceTerminalHosting: AnyObject {
    func attach(to session: WorkspaceTerminalSession)
    func focus()
    func resize(columns: Int, rows: Int)
}

@MainActor
final class WorkspaceTerminalSession {
    let id: UUID
    let workingDirectory: URL
    var isRunning: Bool
}
```

Responsibilities:

- `WorkspaceTerminalSession`: shell lifecycle, PTY/process attachment, cwd, running state
- terminal host adapter: platform-specific terminal rendering and input bridge
- `MainViewModel`: high-level tab orchestration only

This separation keeps the workspace shell cross-platform even if `SwiftTerm` is only fully wired for `macOS` first.

## Package and Platform Integration

Add `SwiftTerm` to `Package.swift` as a SwiftPM dependency and link it only where needed by the app target.

Platform plan:

- `macOS`: implement the first real host using `SwiftTerm`
- `iPadOS` and `visionOS`: keep the same terminal state, commands, and layout contract, but use a platform adapter boundary so the app architecture does not need another redesign later

If `SwiftTerm` support is incomplete on a target, that target should still compile through conditional host wiring instead of leaking platform checks throughout the workspace shell.

## Working Directory Resolution

The terminal must open in the project directory for the active tab.

Resolution order:

1. workspace files tab project directory
2. project chat or task chat project directory
3. project kanban project directory if available
4. if no project-scoped directory can be resolved, do not start the shell and show an inline "Project directory unavailable" state in the drawer

The working directory should be resolved once when the session is first started, then kept for the lifetime of that tab session unless explicit retargeting is added later.

For the first implementation, shell startup is intentionally restricted to tabs that can resolve a concrete project directory. This keeps the behavior deterministic and aligned with the requested "open in project directory" requirement.

## Lifecycle

### Tab creation

- Create a `terminalState` with default height and hidden presentation.
- Do not start the shell yet.

### First open

- Resolve the tab working directory.
- Start the session lazily.
- Attach the platform host.
- Focus the terminal.

### Hide drawer

- Keep the shell alive.
- Hide only the UI.

### Switch tabs

- Detach or hide the previous host presentation as needed.
- Restore the selected tab terminal state if it is presented.

### Close tab

- Terminate the associated terminal session cleanly.
- Release host resources.

## Rendering

### Main view

`MainView` should render the terminal drawer under the active tab content.

- single-tab mode: selected tab content above, terminal drawer below when presented
- split mode: selected split tab drives the drawer state, drawer remains below the active workspace content region

The drawer should use the existing visual language of the client with a subtle divider and drag handle.

### Host view

Add a dedicated terminal host view rather than embedding `SwiftTerm` inline everywhere.

Suggested direction:

- `WorkspaceTerminalDrawerView`
- `WorkspaceTerminalMacHostView`
- optional placeholder or adapter-backed host views for other platforms

## Keyboard Shortcuts and Focus

Add a workspace-level shortcut for `cmd + j`.

Behavior:

- open closed drawer and focus terminal
- close open drawer even if focus is currently inside the terminal
- return focus to the surrounding workspace content after closing

The shortcut should be handled at the workspace shell layer so it remains reliable even when the embedded terminal has keyboard focus.

## Edge Cases

- Toggling the terminal with no selected tab does nothing.
- If a tab has no resolvable project directory, keep the drawer in a non-running error/empty state and do not spawn a shell.
- If the session fails to start, show an inline terminal error state inside the drawer.
- If a selected tab changes while the terminal is visible, the drawer should retarget to the newly selected tab state.
- If desktop split references a tab that closes, its terminal session should also be cleaned up.

## Files Expected To Change

- `Package.swift`
- `Sources/SloppyClient/Navigation/Main/MainTabs.swift`
- `Sources/SloppyClient/Navigation/Main/MainViewModel.swift`
- `Sources/SloppyClient/Navigation/Main/MainView.swift`
- new terminal runtime/host files under `Sources/SloppyClient/Workspace/Terminal/`
- focused tests under `Tests/SloppyClientCoreTests/`

## Testing

Add focused tests for:

- terminal state is created per tab
- toggling terminal affects only the selected tab
- working directory resolution prefers project-scoped context
- closing a tab cleans up the associated terminal session
- terminal height persists per tab
- split mode uses the selected tab terminal state
- source-level coverage for bottom drawer rendering and shortcut wiring

## Recommendation

Implement the terminal as a bottom drawer owned by each workspace tab, with a dedicated runtime layer and a `macOS` `SwiftTerm` host as the first concrete renderer. This keeps the UX aligned with the request while preserving a clean cross-platform workspace architecture.
