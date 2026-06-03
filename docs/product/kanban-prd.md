# PRD: Project Kanban for Agent Work

Status: Internal draft for maintainers and coding agents  
Date: 2026-06-03  
Audience: Sloppy maintainers, Dashboard engineers, runtime engineers, and repository-aware agents  
Public docs: Excluded from VitePress via `srcExclude`

## 1. Executive Summary

- **Problem Statement**: Sloppy projects need a reliable kanban surface where humans, agents, and external task sources can coordinate work without losing task state, review context, or routing intent. Without a typed board contract, task movement risks becoming a Dashboard-only UI behavior disconnected from agent execution, actor/team routing, review, sync, and recovery.
- **Proposed Solution**: Treat project kanban as the operational task control plane for Sloppy projects: a typed project task model, explicit lifecycle statuses, realtime board events, actor/team assignment, review handoff, comments/activity/logs, attachments, archived work, and optional external task sync.
- **Success Criteria**:
  - Creating, updating, deleting, and moving a task updates persisted project state and emits a matching `KanbanEvent` within the active project stream.
  - Moving a task to `ready` triggers agent routing through explicit `actorId`, `teamId`, `claimedActorId`, `claimedAgentId`, and actor-board task links, not by parsing task text.
  - Task dependencies are represented by structured fields and can promote downstream work only when prerequisite tasks are complete.
  - Every agent execution attempt leaves structured handoff evidence that a human, reviewer, retry worker, or downstream task can inspect without scraping model prose.
  - Dashboard board state converges after websocket reconnect by refetching project data and applying `task_created`, `task_updated`, `task_deleted`, and `project_updated` events idempotently.
  - Review workflows can move work through `needs_review`, approve to `done`, or reject back to a developer/team with an auditable activity trail.
  - Archived terminal tasks stay retrievable through `/v1/projects/:projectId/tasks/archived` and do not crowd the active board.

## 2. User Experience & Functionality

- **User Personas**:
  - Operator: creates and triages project work, assigns actors/teams, watches progress, and resolves blocked or review states.
  - Agent manager: configures project actors/teams and needs the board to trigger predictable worker execution.
  - Agent worker: receives ready tasks with enough title, description, attachments, model, routing, and project context to execute work.
  - Reviewer: inspects task diff, review comments, activity, logs, and completion notes before approving or rejecting work.
  - Integrations engineer: links Sloppy project tasks to external providers such as GitHub Projects without breaking local board semantics.

- **User Stories**:
  - As an operator, I want to create a task with title, description, priority, status, kind, assignee/team, model override, attachments, and tags so that work enters the project with enough execution context.
  - As an operator, I want to drag or bulk move tasks between kanban columns so that board state reflects current lifecycle state immediately.
  - As an agent manager, I want `ready` tasks to route through the actor board and project team settings so that work is delegated to the right agent or team.
  - As an orchestrator, I want to decompose a rough request into linked child tasks so that specialists can work in parallel and downstream tasks start only after their prerequisites complete.
  - As a retry worker, I want to see prior attempt summaries, verification, failures, and residual risks so that I do not repeat failed work.
  - As a reviewer, I want tasks in `needs_review` to expose diff, comments, activity, logs, and approve/reject controls so that review decisions are auditable.
  - As an operator, I want blocked and waiting-input tasks to remain visible and actionable so that human intervention is not hidden inside chat transcripts.
  - As an integrations engineer, I want external task sync to preserve Sloppy task identity and lifecycle fields so that local agents can work from imported tasks.

- **Acceptance Criteria**:
  - The active board groups non-archived tasks by the canonical statuses: `pending_approval`, `backlog`, `ready`, `in_progress`, `waiting_input`, `needs_review`, `blocked`, `done`, and `cancelled`.
  - Task create uses `POST /v1/projects/:projectId/tasks` and returns the updated `ProjectRecord`.
  - Task update/move uses `PATCH /v1/projects/:projectId/tasks/:taskId` with `changedBy` set by the caller and returns the updated `ProjectRecord`.
  - Task delete uses `DELETE /v1/projects/:projectId/tasks/:taskId` and emits `task_deleted`.
  - Task approval uses `POST /v1/projects/:projectId/tasks/:taskId/approve`; task rejection uses `POST /v1/projects/:projectId/tasks/:taskId/reject`.
  - Task comments, review comments, activities, logs, clarifications, and source-control diff are available through task-scoped project routes.
  - `KanbanEvent` payloads include `type`, `projectId`, and either `task` or `taskId` as appropriate.
  - The websocket endpoint `/v1/projects/:projectId/kanban/ws` streams project-scoped kanban events and the Dashboard reconnects after transient disconnects.
  - Moving a task to `backlog` or `cancelled` clears claimed actor/agent fields.
  - Moving a task to `ready`, or changing assignment while already `ready`, resets route history when appropriate and invokes `handleTaskBecameReady`.
  - A task with `dependsOnTaskIds` cannot be auto-routed to execution until all referenced project-local dependencies are `done`; unresolved, cross-project, or cyclic dependencies are rejected or surfaced as blocked before worker spawn.
  - Runtime-driven task completion records a structured completion note and target handoff metadata: changed files, verification commands/results, dependency notes, retry notes, blocked reason, and residual risk.
  - A running task that loses its worker, channel, or claim past a configured timeout is reclaimed or blocked through typed lifecycle state, with a visible activity/log entry.
  - Terminal `done` and `cancelled` tasks older than the archive threshold are marked `isArchived` and excluded from the active board while still available in archived task views.

- **Non-Goals**:
  - Do not infer task status, completion, review result, or routing from natural-language task titles, descriptions, comments, or model prose.
  - Do not make Dashboard drag/drop the source of truth; server-side project state and typed events remain authoritative.
  - Do not replace Actors Board routing or Swarm decomposition in this PRD scope.
  - Do not require external task sync for local kanban to function.
  - Do not add custom per-project status definitions until a separate migration and compatibility design exists.
  - Do not allow links, dependencies, realtime events, comments, or worker visibility to cross project boundaries unless a future explicit cross-project reference design is accepted.

### Kanban vs. Other Agent Primitives

Kanban is not a replacement for direct chat, branch work, or Swarm. It is the durable work queue used when work must remain visible, survive restarts, cross actor boundaries, involve humans, or leave an audit trail.

| Primitive | Use When | Persistence | Human-In-Loop | Output Contract |
| --- | --- | --- | --- | --- |
| Direct chat | A user needs an answer or short action in the current conversation. | Channel/session state | Inline only | Assistant response and tool observations |
| Branch work | A focused agent needs isolated reasoning or an artifact before returning to the parent flow. | Runtime branch/event state | Parent-mediated | Branch conclusion |
| Swarm | A manager actor decomposes a ready task through hierarchical actor links. | Project tasks plus runtime events | Through project/task state | Child tasks, handoffs, review |
| Kanban | Work needs durable lifecycle state, assignment, retries, review, comments, and external visibility. | Project task store | First-class comments, waiting-input, blocked, review | Structured task/run state |

Kanban workers may still use direct chat, tools, branches, or Swarm internally. The board remains the source of truth for the task lifecycle.

## 3. AI System Requirements

- **Tool Requirements**:
  - Agent-visible task tools must call typed project APIs and supply structured fields such as `status`, `actorId`, `teamId`, `dependsOnTaskIds`, `completionConfidence`, and `completionNote`.
  - Runtime execution must consume `ProjectTask` fields directly and preserve `routeHistory` as structured routing evidence.
  - A worker assigned to a kanban task must start from the task record and project bootstrap, not from an inferred chat summary.
  - Long-running workers must emit typed progress/heartbeat observations or task logs often enough for stale-claim detection.
  - Worker completion must use a typed task update/review API that carries completion evidence; plain assistant prose is not sufficient to close an execution task.
  - Worker blocking must use `waiting_input` or `blocked` with a structured reason and, when applicable, clarification records.
  - Orchestrator agents may create/link child tasks, but execution workers should not mutate unrelated project tasks unless their role/tool scope explicitly allows orchestration.
  - Review automation must use `ProjectReviewSettings`, actor/team roles, task status, and approve/reject APIs rather than textual review heuristics.
  - Memory checkpoint triggers may observe task lifecycle changes, but must not persist transient board status as durable project memory.

- **Evaluation Strategy**:
  - Router/service tests cover create, update, delete, archive, approve, reject, comments, activities, logs, clarifications, and websocket event emission.
  - Runtime tests verify `ready` task routing through explicit actor/team assignment and actor-board task links.
  - Dependency tests verify `dependsOnTaskIds` promotion, cycle rejection, missing dependency handling, and no cross-project dependency execution.
  - Worker protocol tests verify task read, heartbeat/progress, completion evidence, blocked/waiting-input transitions, stale claim reclaim, and protocol-violation blocking.
  - Attempt-history tests verify each worker run has an outcome, start/end timestamps, actor/agent identity, optional summary/metadata, and grouped task events.
  - Dashboard tests verify column grouping, drag/bulk status updates, realtime event application, reconnect behavior, and active/archived separation.
  - Review tests verify diff visibility, comment lifecycle, approve/reject state transitions, and rejection reassignment to a developer actor where configured.
  - Sync tests verify imported/external tasks do not overwrite local routing, review, archive, or task identity fields incorrectly.

## 4. Technical Specifications

- **Architecture Overview**:
  - `ProjectRecord.tasks` stores the board's task collection and `ProjectTask` stores each task's lifecycle, assignment, source-control, swarm, attachment, tag, route, and archive fields.
  - `CoreService+Projects` owns project task CRUD, status normalization, archive rules, outbound sync hooks, and `KanbanEvent` publication.
  - `CoreService+TaskLifecycle` owns execution lifecycle transitions, review approval/rejection, team handoff, retry, and runtime-driven task updates.
  - `ProjectsAPIRouter` exposes project task routes, review routes, diff routes, comments, activities, logs, clarifications, and archive endpoints.
  - `KanbanEventService` provides project-scoped realtime updates consumed by Dashboard through `/v1/projects/:projectId/kanban/ws`.
  - `ProjectsView` and `ProjectTasksTab` render the active board, task detail surfaces, selection/bulk actions, review entry points, and archived task access.

- **Dependency Model**:
  - `dependsOnTaskIds` is the project-local dependency list for a task.
  - A task with dependencies may sit in `backlog` or `ready`, but runtime dispatch treats it as executable only after all dependencies are `done`.
  - When the final dependency reaches `done`, the service may promote the dependent task to `ready` or emit an actionable blocked/waiting-input state if routing cannot be resolved.
  - Dependency validation must reject self-dependencies, cycles, missing task IDs, and cross-project task IDs.
  - Swarm child task fields (`swarmId`, `swarmTaskId`, `swarmParentTaskId`, `swarmDependencyIds`) remain separate from human-authored dependency fields, but both must converge into the same executable-readiness decision.

- **Dispatcher and Worker Protocol**:
  - The dispatcher is the server/runtime path that turns executable `ready` tasks into claimed worker execution.
  - Claiming a task sets `claimedActorId`, `claimedAgentId`, route history, and `in_progress` state through typed updates before worker work begins.
  - Current implementation includes a periodic kanban maintenance scheduler that invokes stale-claim reclaim and dispatches existing `ready` tasks through the same typed worker path used by manual ready transitions, using configurable timeout, interval, jitter, and spawn-failure limit settings.
  - A worker reads the task record, project bootstrap, attachments, comments, dependencies, and prior attempt summaries before making changes.
  - A worker emits progress through task logs, activities, comments, runtime events, or heartbeat records during long-running work.
  - A worker finishes by moving the task to `needs_review`, `done`, `waiting_input`, or `blocked` through a typed task update with structured evidence.
  - Stale or missing heartbeat is absence detection: the dispatcher reclaims the task to `ready`, closes the attempt as `reclaimed`, and does not count it as a worker failure.
  - Worker success/exit while the task remains `in_progress` without a typed task completion, waiting-input, or blocked update is a protocol violation: the dispatcher closes the run as failed/blocked evidence and moves the task to `blocked` immediately.
  - If a worker disconnects or times out while the task remains `in_progress`, the dispatcher closes the attempt as reclaimed, failed, or blocked according to that distinction rather than leaving an orphaned claim.
  - Repeated spawn or execution failures trip a circuit breaker that moves the task to `blocked` with the last structured error.

- **Attempt History and Handoff Evidence**:
  - Target model: introduce a first-class `ProjectTaskRun`/attempt record separate from `ProjectTask` so retries, review attempts, and manual completions do not overwrite history.
  - Each attempt records `runId`, `projectId`, `taskId`, `actorId`, `agentId`, `workerId` or session ID, `status/outcome`, `startedAt`, `endedAt`, `summary`, `metadata`, and failure/block reason when present.
  - Task events should optionally reference `runId` so Dashboard can group logs, comments, completion, rejection, and retry activity by attempt.
  - Structured handoff metadata should prefer this shape for engineering tasks: `changedFiles`, `verification`, `dependencies`, `blockedReason`, `retryNotes`, and `residualRisk`.
  - Downstream tasks, reviewers, and retry workers should read the latest completed dependency attempts and prior failed attempts without parsing free-form comments.
  - Manual completion of a never-claimed task may synthesize a zero-duration attempt so handoff evidence still has a durable home.

- **Integration Points**:
  - Protocol models: `Sources/Protocols/APIModels.swift`
  - Project task CRUD and archive logic: `Sources/sloppy/CoreService+Projects.swift`
  - Task execution/review lifecycle: `Sources/sloppy/CoreService+TaskLifecycle.swift`
  - Activity/comment/log recording: `Sources/sloppy/CoreService+TaskActivity.swift`
  - Project API routes: `Sources/sloppy/Gateway/Routers/ProjectsAPIRouter.swift`
  - Kanban websocket route: `Sources/sloppy/Gateway/CoreRouter.swift`
  - Dashboard API client: `Dashboard/src/shared/api/coreApi.ts`
  - Dashboard board surfaces: `Dashboard/src/views/ProjectsView.jsx` and `Dashboard/src/views/Projects/ProjectTasksTab.jsx`
  - Realtime hook: `Dashboard/src/views/Projects/useKanbanSocket.ts`
  - External task sync: `Sources/sloppy/CoreService+TaskSync.swift`

- **Security & Privacy**:
  - Task payloads may contain file paths, attachments, source-control metadata, and user comments; API and logs should avoid exposing secrets beyond the authenticated Dashboard/Core surface.
  - External task sync tokens must stay in task-sync token storage/status APIs and never be copied into task descriptions, comments, activities, or events.
  - Realtime kanban events should carry task records only for the subscribed project and must not broadcast cross-project tasks.
  - Workers spawned for a project task must see only the project, task, dependency, attachment, and memory scope they are authorized to read.
  - Dependency links and route history should store IDs and bounded summaries, not raw transcripts or secret-bearing tool output.
  - Review comments and task logs should prefer structured metadata and bounded snippets over large raw command/model output.
  - Agent tools must respect project boundaries and reject invalid project/task IDs before mutating board state.

## 5. Risks & Roadmap

- **Phased Rollout**:
  - MVP/as-is hardening: preserve current project task statuses, CRUD routes, kanban websocket events, active/archived split, actor/team assignment, review approve/reject, comments, activities, logs, clarifications, and Dashboard bulk/drag behavior.
  - v1.1: add contract tests for kanban websocket events, Dashboard reconnect convergence, route-history reset behavior, archived task filtering, and project-boundary isolation.
  - v1.2: implemented dependency readiness rules for `dependsOnTaskIds`, including promotion, cycle rejection, and no cross-project execution.
  - v1.3: in progress: formalize dispatcher/worker protocol with periodic ready-task dispatch, stale-claim reclaim, spawn-failure circuit breaker, heartbeat/progress, and protocol-violation blocking.
  - v1.4: introduce `ProjectTaskRun` attempt history and structured handoff metadata for completion, blocking, retries, and review.
  - v1.5: improve board observability with per-column counts, stale-task indicators, blocked/waiting-input summaries, attempt history, and surfaced routing explanations from `routeHistory`.
  - v1.6: harden external task sync with explicit conflict policy, provider status, and mapping tests for GitHub Projects fields.
  - v2.0: evaluate triage/specify/decompose flows and custom workflow columns only after a migration plan keeps existing `ProjectTaskStatus` API compatibility.

- **Next Implementation Turn**:
  - Add task-worker heartbeat/progress as a typed signal that stale-claim detection can use beyond worker existence/start time, with stale heartbeat reclaim treated as self-healing absence detection rather than a worker fault.
  - Add protocol-violation blocking for workers that exit or finish successfully without the required typed task update, completion evidence, or structured handoff.
  - Extend dispatcher tests to cover stale heartbeat detection, protocol-violation blocking, retry-after-reclaim on a later tick, and structured handoff visibility in `ProjectTaskRun`/Dashboard.

- **Technical Risks**:
  - Dashboard and server can diverge if websocket events are dropped and the UI does not reconcile with a fresh project snapshot.
  - Custom status requests could break runtime routing if `ready`, `in_progress`, `needs_review`, and terminal statuses lose stable meaning.
  - Dependency promotion can deadlock work if cycles, missing tasks, or cross-project references are not rejected before dispatch.
  - Stale worker claims can leave cards stuck in `in_progress` unless the dispatcher has a typed reclaim path.
  - Attempt history can duplicate logs/comments unless task facts, event facts, and run facts have clear ownership.
  - External sync can overwrite local agent assignment, route history, or review state unless conflict handling is explicit.
  - `ProjectTask` can grow into an overloaded model; future fields should be grouped only when they reduce API ambiguity.
  - Archive rules can hide useful completed work if users do not have an obvious archived-task path.
  - Review automation can become brittle if it starts reading natural-language comments instead of structured status, role, and route fields.

- **Open Questions**:
  - What measurable UX targets should kanban own beyond correctness, such as maximum board refresh latency, drag update latency, or supported active task count per project?
  - Should external provider sync be one-way import, two-way sync, or configurable per project for each field class: title/description/status/priority/assignee/comments?
  - Should Sloppy expose kanban as channel/slash-command operations in Telegram/Discord/TUI, and if so which operations are safe while an agent is running?
  - Should `ProjectTaskRun` live in SQLite/project storage immediately, or first be derived from existing task logs and runtime events?
