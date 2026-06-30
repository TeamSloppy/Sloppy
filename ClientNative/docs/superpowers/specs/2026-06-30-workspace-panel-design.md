# Workspace Panel Design

Date: 2026-06-30
Status: Draft for review

## Goal

When the user is working inside a project directory, the native client should show a right-side workspace panel with:

- hierarchical project file tree
- file preview for readable text files
- drag and drop from the file tree into chat/composer
- basic file operations: create file, create folder, rename, delete

The panel should appear only in project-scoped chat contexts and should reuse the existing Core project-files API instead of introducing a second filesystem access path in the client.

## Existing Context

The repository already has:

- desktop split layout in [Sources/SloppyClient/MainView.swift](/Users/vlad-prusakov/Developer/Sloppy/ClientNative/Sources/SloppyClient/MainView.swift)
- project-aware chat navigation in [Sources/SloppyFeatureChat/ChatScreenViewModel.swift](/Users/vlad-prusakov/Developer/Sloppy/ClientNative/Sources/SloppyFeatureChat/ChatScreenViewModel.swift)
- dashboard implementation of project file browsing in `../Dashboard/src/views/Projects/ProjectFilesTab.jsx`
- backend endpoints:
  - `GET /v1/projects/:projectId/files`
  - `GET /v1/projects/:projectId/files/content`

These backend routes already provide lazy directory listing and text-file reading. The native client should mirror that interaction model.

## Chosen Approach

We will implement an embedded right-side `WorkspacePanel` in the desktop `MainView` layout.

Why this approach:

- matches the requested UX of “panel on the right”
- keeps chat as the main surface while adding project-aware context
- avoids overloading the existing left navigation sidebar
- allows drag and drop directly into the chat composer
- reuses existing project-aware state from `ChatScreenViewModel`

The first implementation will be desktop-first. Compact/mobile layout will not show the right-side panel in this iteration.

## UX Behavior

The workspace panel is shown when all of the following are true:

- the current chat context has a non-empty `projectId`
- the client is in regular/desktop layout
- the project file tree can be resolved through the Core API

The panel is hidden for:

- blank chat
- non-project agent chat
- compact/mobile layout

Panel structure:

1. Header
- project/workspace title
- refresh action
- create file action
- create folder action

2. Tree
- root directory entries loaded from `/v1/projects/:projectId/files`
- directories expand lazily
- directories sort before files
- selected file row is highlighted

3. Preview
- selecting a text file loads `/v1/projects/:projectId/files/content?path=...`
- unreadable, binary, or oversized files show an error/unsupported state

4. Drag and drop
- dragging a file from the tree into the composer inserts an attachment/reference token for the project-relative path
- dragging a folder inserts a folder reference only, not inline content

## Architecture

### Main Layout

`MainView` becomes a three-zone desktop layout:

- left: existing `MainSidebarView`
- center: existing `ChatScreen`
- right: new `WorkspacePanel`

The right panel is conditionally rendered from a derived workspace context owned by `MainViewModel`.

### State Ownership

`ChatScreenViewModel` remains responsible for chat/session/project navigation state.

`WorkspacePanelViewModel` will be introduced for workspace-specific state:

- active `projectId`
- active project name
- root entries
- expanded directory cache
- selected file path
- selected file content state
- create/rename/delete operation state
- drag payload generation

This keeps file-tree concerns separate from chat transcript/session concerns.

### Core Client API

`SloppyClientCore` will expose typed wrappers for project files:

- `fetchProjectFiles(projectId:path:)`
- `fetchProjectFileContent(projectId:path:)`

The model layer will mirror backend contracts already defined in `../Sources/Protocols/APIModels.swift`:

- `ProjectFileEntry`
- `ProjectFileContentResponse`

If file mutations are needed in this iteration, new Core API endpoints will be added through the existing project router/service flow rather than local filesystem access from the app UI.

## File Tree Model

Introduce a native tree node model:

- `id`
- `name`
- `path`
- `kind` (`file` or `directory`)
- `children`
- `isExpanded`
- `isLoadingChildren`
- `size`

Tree loading strategy:

- load root once when project context becomes active
- fetch children only on expand
- cache fetched children in-memory by project-relative path
- invalidate cache on explicit refresh and successful mutations

## Drag and Drop

The drag source is a tree row.

Recommended payload for v1:

- project-relative path string
- item type (`file` or `directory`)
- project id

Drop target is the chat composer.

On drop:

- file: insert a project-file reference token/path attachment
- directory: insert a directory reference token/path attachment

The drop should not eagerly inline file contents into the draft. It should attach a stable reference that existing chat tooling can resolve later.

## File Operations

First-class UI actions in the panel:

- create file
- create folder
- rename
- delete

These should be backed by explicit backend endpoints under the project API, not by direct app-local filesystem mutation.

Operation rules:

- only allow project-relative paths
- reject path traversal
- refresh affected subtree after success
- surface inline error state on failure

If backend mutation endpoints do not yet exist, they become part of the implementation plan for this feature.

## Error Handling

Failure states should be explicit and local:

- tree load failure: panel-level error with retry
- directory load failure: row/subtree error with retry
- file preview failure: preview error state
- mutation failure: inline toast/banner or row-level status

The panel should fail closed: if workspace data cannot load, the rest of the chat UI must keep working normally.

## Testing

### Client tests

Add focused source/behavior tests for:

- `MainView` shows workspace panel only for project-scoped desktop contexts
- workspace panel fetches root entries when activated
- expanding a directory triggers lazy child fetch
- selecting a file triggers content fetch
- picker/chat layout behavior remains unaffected
- drag payload includes project id, path, and type

### Backend tests

If mutation endpoints are added:

- create file/folder
- rename
- delete
- path traversal rejection
- subtree refresh consistency

## Scope Boundaries

Included in this feature:

- right-side desktop workspace panel
- file hierarchy
- text preview
- drag and drop to composer
- create/rename/delete/create-folder actions

Not included in this feature:

- mobile workspace panel
- full code editor
- binary/image preview polish beyond basic unsupported state
- git-aware decorations in the tree
- multi-select drag and drop

## Recommendation

Implement this as a desktop-only `WorkspacePanel` backed by the existing Core project-files API and a new isolated `WorkspacePanelViewModel`.

This gives the requested UX with the least architectural risk, keeps filesystem concerns out of the view layer, and aligns native behavior with the already-shipping dashboard file browser.
