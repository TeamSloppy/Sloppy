# Source Control and Task Sync Spec

## 1. Document Status
- Version: `0.1`
- Date: `2026-06-03`
- Status: `Draft for product and implementation alignment`
- Owners: `sloppy`, `PluginSDK`, `Dashboard`
- Primary code areas: `Sources/sloppy/CoreService+TaskSync.swift`, `Sources/sloppy/CoreService+ProjectChanges.swift`, `Sources/sloppy/GitWorktreeService.swift`, `Sources/sloppy/Gateway/Routers/TaskSyncAPIRouter.swift`, `Sources/sloppy/Gateway/Routers/SourceControlAPIRouter.swift`, `Dashboard/src/views/Projects/*`

## 2. Product Context
Sloppy project work often maps to files in a Git repository and issues in an external tracker. Source control and task sync features let operators inspect working tree changes, restore files, review task diffs, and link project tasks to providers such as GitHub.

## 3. Goals
1. Make repository changes visible from the project workspace and task review UI.
2. Support provider-abstracted source control status through the PluginSDK.
3. Link Sloppy tasks to external issue/task providers without making them mandatory.
4. Provide safe restore/revert actions for generated file changes.
5. Preserve enough sync metadata to avoid duplicate external issues and accidental overwrites.

## 4. Non-goals
1. Full Git hosting replacement.
2. Complex merge conflict resolution inside Dashboard.
3. Supporting every external tracker workflow in the core schema.
4. Automatically pushing code or opening PRs without explicit product decision and approval.

## 5. Core Concepts
| Concept | Description |
| --- | --- |
| Source control provider | Plugin or built-in adapter that reports repository status and diffs. |
| Working tree snapshot | Current changed files, hunks, and metadata for a project repo. |
| Task diff | Diff view scoped to a task's branch/worktree or associated changes. |
| Task sync provider | External tracker adapter, e.g. GitHub issues. |
| Sync link | Mapping between Sloppy project/task IDs and external provider IDs/URLs. |
| Webhook | Provider callback used to update local task state when external state changes. |

## 6. Functional Requirements

### FR-1: Source control providers
- API exposes available source control providers.
- Projects can use a built-in Git provider or plugin provider where configured.
- Provider failures should not break task board rendering.

### FR-2: Working tree visibility
- Clients can fetch project working tree status.
- Dashboard shows changed files, additions/deletions, and file-level state.
- Live project change streams update the UI when file changes occur.

### FR-3: Restore/revert
- Operators can restore selected project files to the repository state where supported.
- Destructive restore actions require explicit confirmation in UI.
- Restore activity should be auditable when associated with a task.

### FR-4: Task diff and review
- Task review view can fetch and render task-scoped diffs.
- Review comments can be attached to lines/hunks when diff metadata is available.
- If a diff is unavailable, the review UI must explain why rather than showing an empty success state.

### FR-5: Task sync discovery and linking
- API can discover supported task sync providers for a project.
- Operators can link/unlink a project to a provider/repository.
- Sync configuration includes provider ID, repository/owner data, webhook URL/status, and token state.

### FR-6: Sync now and webhook ingest
- Operators can trigger manual sync.
- Provider webhooks update local linked task state with idempotency protections.
- Sync should preserve local-only tasks and avoid creating duplicates for already-linked external items.

### FR-7: Secret/token handling
- Provider tokens are stored securely and represented as redacted status in API/UI.
- Clearing a token disables sync operations that require it but preserves non-secret configuration.

## 7. Public API Surface
Representative endpoints:
- `GET /v1/source-control/providers`
- `GET /v1/projects/{projectId}/source-control/working-tree`
- `POST /v1/projects/{projectId}/source-control/restore`
- `GET /v1/projects/{projectId}/changes/stream`
- `GET /v1/projects/{projectId}/tasks/{taskId}/diff`
- `GET /v1/projects/{projectId}/task-sync`
- `POST /v1/projects/{projectId}/task-sync/link`
- `POST /v1/projects/{projectId}/task-sync/unlink`
- `POST /v1/projects/{projectId}/task-sync/sync-now`
- `GET /v1/projects/{projectId}/task-sync/token?providerId=github`
- `POST /v1/projects/{projectId}/task-sync/token?providerId=github`
- `DELETE /v1/projects/{projectId}/task-sync/token?providerId=github`
- `POST /v1/task-sync/github/webhook`

## 8. Dashboard UX
1. Project files/overview surfaces show working tree changes with refresh and live updates.
2. Task review shows diffs beside chat/comments when available.
3. Project settings expose task sync connection status, link/unlink, token management, and manual sync.
4. Restore/revert buttons are guarded by confirmation and show results per file.

## 9. Edge Cases
- Project has no repository path or Git metadata; source control UI should show unsupported state.
- Working tree changes while a diff is open; UI should mark the view stale and allow refresh.
- Webhook arrives for an unknown external issue; policy decides whether to create, ignore, or log.
- Token is missing/expired during sync; state becomes needs-auth without deleting mappings.
- External issue was renamed/closed/deleted; local task should keep history and expose sync status.

## 10. Acceptance Criteria
1. A project with a Git repo shows working tree changes in Dashboard/API.
2. A task with associated changes displays a diff or a clear unavailable reason.
3. Operator can link a project to GitHub task sync, set token, run sync now, and see sync status.
4. Webhook processing is idempotent for repeated delivery.
5. Restore action updates working tree state and is visible after refresh.

## 11. Tests / Verification
- Backend: source control API router, Git worktree service, task sync, GitHub auth/webhook, project change watcher.
- Dashboard: project files tab, review diff panel, live update stream, settings task sync controls.
- Manual: create a project repo, modify a file, verify working-tree API/UI, link task sync, run sync, and test restore on a throwaway change.
