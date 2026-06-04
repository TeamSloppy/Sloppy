# Project Task Board and Autonomous Work Spec

## 1. Document Status
- Version: `0.1`
- Date: `2026-06-03`
- Status: `Draft for product and implementation alignment`
- Owners: `sloppy`, `Dashboard`, `AgentRuntime`
- Primary code areas: `Sources/sloppy/CoreService+Projects.swift`, `Sources/sloppy/CoreService+TaskLifecycle.swift`, `Sources/sloppy/Gateway/Routers/ProjectsAPIRouter.swift`, `Dashboard/src/views/Projects/ProjectTasksTab.jsx`

## 2. Product Context
Sloppy projects are the operator-facing unit for grouping repository context, channels, actors, and autonomous work. The task board turns requests into auditable work items that can be planned, approved, executed by agents, reviewed, archived, and synchronized with external trackers.

## 3. Goals
1. Give operators a single board for all project work.
2. Preserve enough task state to resume and audit autonomous execution.
3. Support human and agent loops without hiding route decisions.
4. Make approvals, clarifications, comments, activities, logs, and diffs discoverable from the task detail surface.
5. Keep task references stable and human-readable, e.g. `SLOPPY-123`.

## 4. Non-goals
1. Replacing external issue trackers.
2. Full dependency scheduling across distributed workers.
3. Hard real-time execution guarantees.
4. Fine-grained enterprise RBAC for every task field.

## 5. Core Concepts
| Concept | Description |
| --- | --- |
| Project | Workspace/repository scoped container for tasks, channels, actors, memories, and settings. |
| Task | Durable unit of work with title, description, status, priority, assignee/actor/team, dependencies, and audit history. |
| Reference | Human-readable task key derived from project identity. |
| Loop mode | Execution control hint: human, agent, or route-derived autonomous mode. |
| Approval | Explicit gate for pending work before execution or merge-like actions. |
| Clarification | Structured question attached to a task when an agent needs operator input. |
| Activity | Append-only history of task lifecycle and collaboration events. |

## 6. Functional Requirements

### FR-1: Project-scoped task CRUD
- Operators and tools can create, read, update, cancel, archive/delete, and list project tasks.
- API must support both opaque `taskId` and human-readable `reference` where applicable.
- Updates must be partial and preserve unspecified fields.

### FR-2: Kanban statuses
- The board must expose active tasks by status columns.
- `done` is only valid when the caller provides completion confidence and evidence.
- Cancellation must preserve the task record with a reason instead of silently deleting work.

### FR-3: Assignment and routing metadata
- Tasks may carry `actorId`, `teamId`, `selectedModel`, `kind`, `priority`, `tags`, dependencies, and optional parent task.
- Autonomous routing history must be recorded so operators can see why a task moved or stalled.

### FR-4: Approvals and constrained routes
- A task can enter `pending_approval` before execution.
- Approval/rejection must be explicit and auditable.
- Rejected tasks retain reason and should not continue autonomous execution.

### FR-5: Clarifications
- Agents can attach structured clarification requests with options and optional free-form notes.
- Answers become task activity and unblock agent execution when applicable.

### FR-6: Review surface
- The task detail view should aggregate description, route/status, comments, activity, logs, clarifications, and diffs.
- Review comments can be line-scoped when a diff is available.

### FR-7: Live updates
- Dashboard should receive project/task changes without requiring manual refresh where a stream is available.
- The board must remain usable if the live stream disconnects; polling or manual refresh is acceptable fallback.

## 7. Public API Surface
Representative endpoints:
- `GET /v1/projects`
- `POST /v1/projects`
- `PATCH /v1/projects/{projectId}`
- `GET /v1/projects/{projectId}`
- `GET /v1/projects/{projectId}/tasks/{taskId}`
- `POST /v1/projects/{projectId}/tasks`
- `PATCH /v1/projects/{projectId}/tasks/{taskId}`
- `DELETE /v1/projects/{projectId}/tasks/{taskId}`
- `POST /v1/projects/{projectId}/tasks/{taskId}/approve`
- `POST /v1/projects/{projectId}/tasks/{taskId}/reject`
- `GET /v1/projects/{projectId}/tasks/{taskId}/diff`
- `GET /v1/projects/{projectId}/changes/stream`

## 8. Data and Persistence
A persisted task should include at least:
- `id`, `reference`, `projectId`
- `title`, `description`
- `status`, `kind`, `priority`, `tags`
- `actorId?`, `teamId?`, `selectedModel?`, `loopModeOverride?`
- `dependsOnTaskIds`, `parentTaskId?`
- timestamps and audit metadata
- route history, approval state, clarification state, comments, activities, and optional diff/log references

## 9. Dashboard UX
1. Project task tab shows a kanban-style board and task list filters.
2. Task detail/review view shows the work brief, status controls, approvals, comments, activity, logs, and diff panels.
3. Creating planning or pending-approval tasks should encourage structured descriptions with goal, context, definition of done, and verification.
4. Operators must be able to tell whether the next action belongs to a human, an agent, or an external dependency.

## 10. Edge Cases
- Duplicate task creation should be discouraged for planning tasks by comparing intent, goal, scope, and expected outcome.
- Missing project context should require explicit project resolution before writing.
- Dependency cycles must be rejected or treated as blocked.
- A task marked `done` without evidence must be rejected by tool/API validators.
- Live updates may arrive out of order; clients should reconcile by task timestamp/version.

## 11. Acceptance Criteria
1. An operator can create a task, see it on the project board, update its status, and open the task detail view.
2. An agent can request clarification on a task; the answer is visible in activity and can unblock execution.
3. A pending task can be approved or rejected with an auditable result.
4. A completed task requires confidence and completion notes.
5. Dashboard remains usable when the live changes stream disconnects.

## 12. Tests / Verification
- Backend: task CRUD, approval, clarification, comments, activities, project current resolution, and completion validation tests.
- Dashboard: task selection, notification navigation, review panels, kanban live update behavior.
- Manual: create a project, create a planning task, approve it, attach a clarification, answer it, and complete it with evidence.
