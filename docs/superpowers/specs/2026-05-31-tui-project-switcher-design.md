# TUI Project Switcher Design

## Goal

Allow one TUI instance to move between projects on the currently selected Sloppy backend so a user can work across multiple workspaces without restarting the TUI.

## Scope

Version 1 is scoped to the active backend only. On a local backend, `/projects` lists local projects. On a remote backend selected through `/remote`, `/projects` lists projects from that remote instance. Cross-instance aggregation is intentionally deferred.

## User Experience

`/projects` and `/project` open a searchable picker that matches the existing remote project picker style. Project rows show name, id, and updated time, sorted by most recently updated first. The current project is marked as current.

Selecting a project switches the visible TUI workspace. If the selected project already has a tracked session, the TUI resumes that project-scoped selection. Otherwise it opens a draft session for the resolved agent. Working sessions remain alive in the backend and remain tracked under their project key, so the user can return through `/projects` and `/sessions`.

## Architecture

The feature reuses `SloppyTUIBackend.listProjects()` and `getProject(id:)`, avoiding new Core API surface. The picker uses a new `SloppyTUIPickerKind.project` and shares the same search/filter machinery as other TUI pickers.

Project switching is factored into a helper that keeps the current backend but replaces the current `project`, resolves the project-scoped launch selection, resets project-specific transient state, and restarts streams/indexing/status tasks. Existing state keys already include `project.id`, so drafts, tracked sessions, persisted directory grants, and selections remain separated per workspace.

## Error Handling

If project listing fails, the TUI shows a local card and leaves the current workspace unchanged. If a selected project disappears or cannot be loaded, the current workspace remains active and the error is shown. Selecting the already-current project closes the picker without doing destructive work.

## Tests

Tests cover command registration, picker item sorting/current marking, and state key behavior for project-scoped tracked sessions. Existing remote backend tests continue covering the backend list/get behavior used by this feature.
