# Global Tabs and Project Kanban Design

Date: 2026-07-01
Status: Draft for review

## Goal

Replace the current single-surface desktop detail area with a global tab shell so the native client can keep multiple work surfaces open at once.

The first implementation should support:

- multiple global tabs in the main content area
- separate chat tabs with independent session state
- separate project kanban tabs
- a project click from the sidebar opening kanban instead of forcing the user into chat

The user specifically wants browser-like tabs that can hold different chats and different project surfaces side by side without being scoped under one project container.

## Existing Context

The client already has:

- a desktop split shell in [Sources/SloppyClient/MainView.swift](/Users/vlad-prusakov/Developer/Sloppy/ClientNative/Sources/SloppyClient/MainView.swift)
- a global `MainViewModel` that currently routes the detail pane through `selectedAppSection`
- one shared [ChatScreenViewModel](/Users/vlad-prusakov/Developer/Sloppy/ClientNative/Sources/SloppyFeatureChat/ChatScreenViewModel.swift) for the active chat surface
- a right-side workspace panel model in [Sources/SloppyClient/WorkspacePanelViewModel.swift](/Users/vlad-prusakov/Developer/Sloppy/ClientNative/Sources/SloppyClient/WorkspacePanelViewModel.swift)
- project detail and task models in [Sources/SloppyClientCore/OverviewModels.swift](/Users/vlad-prusakov/Developer/Sloppy/ClientNative/Sources/SloppyClientCore/OverviewModels.swift)

The dashboard already contains project kanban behavior inside `../Dashboard/src/views/ProjectsView.jsx`, but that implementation is mixed into a much larger React screen. The native client should extract only the task-board slice rather than mirror the whole dashboard view hierarchy.

## Chosen Approach

We will introduce a single global tab model for the desktop detail pane and make each surface an explicit tab kind.

Why this approach:

- matches the requested Safari/Xcode-style workflow
- removes the current limitation of one global chat/workspace surface
- gives kanban a first-class place in the app instead of hiding it behind project detail rows
- scales cleanly to more surface types later without growing `selectedAppSection` into a giant switch

The first implementation is desktop-first. Phone layout can keep the current simpler navigation model for now.

## UX Behavior

### Desktop Shell

The desktop detail area becomes:

1. top tab strip
2. active tab content below it

Each tab shows:

- surface icon
- title
- active state
- close button

When tabs overflow the available width, the strip scrolls horizontally rather than compressing labels into unreadable widths.

If no tabs are open, the detail pane shows an empty state prompting the user to open a project, task, or chat from the sidebar.

### First-Phase Tab Types

We will support these tab kinds first:

- `chat`
- `projectKanban`
- `workspaceFiles`

`workspaceFiles` is included in the model so the shell is future-proof, even if the first visible migration priority is kanban plus chat.

### Sidebar Behavior

Global tabs are not nested under one project. Sidebar actions open or focus tabs directly.

First-phase behavior:

- clicking a project opens or focuses that project's kanban tab
- clicking a task opens or focuses a task-scoped chat tab
- clicking a recent chat opens or focuses a chat tab for that session
- opening the same logical surface again reuses the existing tab instead of creating duplicates

### Deduplication Keys

Tabs should be deduplicated by semantic key, not by title text.

Recommended keys:

- `chat(session:<sessionId>)`
- `chat(task:<projectId>/<taskId>)`
- `kanban(project:<projectId>)`
- `workspace(project:<projectId>)`

This gives predictable reuse while still allowing different surfaces for the same project to exist at the same time.

### Closing Behavior

- closing the active tab selects a neighboring tab, preferring the tab to the right and then to the left
- closing an inactive tab does not affect the selected tab
- the final remaining tab can be closed, which returns the detail pane to the empty state

## Architecture

### 1. WorkspaceTab Model

Introduce a dedicated tab model owned by `MainViewModel`.

Recommended shape:

- `id`
- `kind`
- `dedupeKey`
- `title`
- surface context payload
- surface-local state holder

`kind` is an enum such as:

- `chat`
- `projectKanban`
- `workspaceFiles`

The tab model should be explicit enough that view rendering does not depend on fragile text matching or unrelated route state.

### 2. MainViewModel as Tab Owner

`MainViewModel` becomes the owner of:

- `tabs`
- `selectedTabID`
- `openTab(...)`
- `selectTab(...)`
- `closeTab(...)`
- "find existing tab by dedupe key" behavior

This replaces the current desktop assumption that one `selectedAppSection` implies one active detail surface.

Sidebar section selection can still exist for left-navigation organization, but it should no longer be the primary owner of desktop content routing.

### 3. Surface-Local State

Each tab keeps its own screen state so switching tabs does not reset the user's work.

Examples:

- a chat tab owns its own `ChatScreenViewModel`
- a kanban tab owns its own `ProjectKanbanViewModel`
- a workspace tab owns its own `WorkspacePanelViewModel`

This is the key change that makes multiple concurrent chats and project surfaces possible.

### 4. Detail Rendering

`MainView` should render:

- the shared left sidebar
- a new desktop tab strip view
- one active tab content view selected from the current tab kind

The current `.projects -> chatScreen` and `.workspace -> workspaceScreen` desktop switch should be replaced by tab-based rendering for desktop.

## Project Kanban Surface

### Kanban Scope

The first kanban implementation is read-only.

Included:

- project task loading through existing project API
- task grouping by status
- column headers with counts
- task cards with title, id, priority, and assignee metadata when available

Not included:

- drag and drop between columns
- inline create/edit/delete
- task detail modals
- optimistic live socket sync

This keeps the migration focused on shipping the board as a viewable project surface first.

### Data Source

The native client should reuse `fetchProject(id:)` from [Sources/SloppyClientCore/SloppyAPIClient.swift](/Users/vlad-prusakov/Developer/Sloppy/ClientNative/Sources/SloppyClientCore/SloppyAPIClient.swift).

No new backend API is required for the first read-only board if the current project record already includes task arrays with status and priority.

### View Model

Introduce `ProjectKanbanViewModel` with responsibility for:

- loading a project by id
- exposing grouped columns
- mapping raw task status values into stable board columns
- exposing loading, empty, and error states

This keeps Dashboard-specific grouping logic out of `MainViewModel` and keeps the board testable in isolation.

### Status Grouping

Board columns should be driven by stable typed status grouping rather than by ad hoc display text.

Initial columns should cover the statuses already present in existing project/task data, such as:

- `todo`
- `in_progress`
- `needs_review`
- `done`

Unknown statuses should still render, either in a fallback column or through a typed normalization layer, but never through text heuristics.

## Chat Surface Migration

The current single global `chatViewModel` is incompatible with true multi-tab behavior.

For desktop tabs:

- each chat tab gets its own `ChatScreenViewModel`
- opening a task from the sidebar creates or reuses a task-scoped chat tab
- opening a recent session creates or reuses a session-scoped chat tab

The existing chat feature views can remain mostly unchanged if they receive a tab-owned view model rather than the current app-global one.

## Workspace Surface Migration

`workspaceFiles` should fit the same tab architecture even if its UI is migrated later than kanban.

This keeps the shell coherent:

- chat is a tab
- kanban is a tab
- workspace is a tab

The current standalone desktop `.workspace` section should be treated as transitional and not as the long-term model.

## Error Handling

Each tab surface should fail locally.

Examples:

- a kanban load failure shows an error inside that tab only
- a chat tab failing to refresh should not disrupt neighboring tabs
- closing a broken tab should be safe and immediate

The tab strip itself should remain usable even when one surface is in an error state.

## Testing

Add focused tests for:

- opening a project from the sidebar creates or focuses a kanban tab
- opening the same project twice reuses one kanban tab
- opening a task creates or focuses a task chat tab
- opening a recent session creates or focuses a session chat tab
- closing active and inactive tabs updates selection correctly
- empty-state rendering when no tabs remain

Add feature tests for kanban:

- project tasks are grouped into expected columns
- unknown or missing statuses are handled deterministically
- loading, empty, and error states render correctly

Add source/rendering tests for:

- tab strip presence in desktop layout
- tab kind icon/title rendering
- active tab content switching without reinitializing neighboring tabs

## Scope Boundaries

Included in this feature:

- desktop global tab shell
- multi-chat desktop support through tab-local state
- read-only project kanban tab
- sidebar project click opening kanban by default

Not included in this feature:

- phone tab-shell parity
- drag-and-drop kanban editing
- live collaborative tab sync
- restoring tabs across full app relaunch
- full replacement of every existing desktop surface in one pass

## Recommendation

Implement the desktop detail area as a global tab shell with tab-local state, and ship project kanban as the first new native project surface within that shell.

This solves the immediate request for browser-like multitasking, gives projects a real board view in the client, and creates a stable architectural foundation for later workspace and review surfaces.
