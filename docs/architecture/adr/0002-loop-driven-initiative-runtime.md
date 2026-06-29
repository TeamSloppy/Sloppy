# ADR 0002: Loop-Driven Initiative Runtime

- Status: Proposed
- Date: 2026-06-30

## Context

Sloppy already has many of the primitives needed for long-lived autonomous work: project tasks, actor graphs, worker and branch runtime, review flows, Visor supervision, worktrees, artifacts, and project context refresh. What it does not yet have is a single product model that ties these primitives into a durable execution loop for end-to-end technical initiatives.

The desired user experience is not a one-shot agent reply. A user should be able to give Sloppy a technical objective such as "optimize CI so it is fast but still reliable", then step away while the system frames the work, researches the codebase, tests hypotheses, stores evidence, requests human decisions only when needed, and resumes from the same point after those decisions are resolved.

Today, artifacts are primarily workspace-level records. That makes them less useful as project-local operational memory. Initiative evidence, verification output, decision packets, and review notes should live alongside the project they belong to rather than feeling detached from it.

## Decision

Treat long-lived technical work as an `initiative loop`.

1. Introduce `Initiative` as the top-level runtime object for durable autonomous work.
2. Model an initiative as a stateful loop rather than a flat task or a one-shot agent session.
3. Use normal project tasks as child work items inside an initiative, not as the only representation of progress.
4. Keep Kanban as the external state machine for initiatives and their child tasks.
5. Use the actor graph as an escalation, delegation, review, and specialization layer inside the loop rather than requiring every initiative to start in swarm mode.

An initiative should move through explicit macro phases:

- `intake`
- `framing`
- `researching`
- `planning`
- `executing`
- `verifying`
- `reviewing`
- `needs_user_decision`
- `blocked`
- `done`
- `abandoned`

Inside these macro phases, the active agent or delegated actors should iterate through a smaller execution cycle:

1. Select the next hypothesis or work item.
2. Execute directly or delegate to a specialist actor.
3. Verify against explicit success checks.
4. Persist artifacts and decisions.
5. Either continue, request review, request a human decision, or conclude the initiative.

Single-agent execution is the default path. The runtime should escalate initiative complexity only when the work requires it:

- `single-agent mode` for low-risk, narrow, local work
- `delegation mode` when a specialist, verifier, or reviewer is needed
- `swarm mode` only when work can be decomposed into parallel, dependency-aware streams
- `council/review mode` when a trade-off decision needs structured evidence and independent scrutiny

Human interaction should be minimized but explicit. When an initiative cannot continue safely without a user choice, the system should emit a structured `decision packet` that captures:

- the proposed action
- the reason for the proposal
- trade-offs and risks
- the exact user input or external action required
- the resume point that should continue once the decision is resolved

Project-local operational artifacts should live under `.meta` inside the project root. SQLite may continue to index artifact metadata for query, API, and dashboard use, but durable initiative files should be stored in the project folder itself.

Recommended project-local layout:

```text
<project-root>/.meta/
  initiatives/
  tasks/
  artifacts/
  decisions/
  reviews/
  state/
```

This makes `.meta` the durable local context for initiative state, evidence, review notes, and resume data, while the database remains the query and coordination plane.

## Non-Decision

This ADR does not require every task to become an initiative. Small direct tasks may still run outside the full initiative loop when they do not need durable orchestration.

This ADR does not require every initiative to use swarm decomposition. Swarm is an escalation mode, not the default.

This ADR does not define the final persistence schema, API shape, or dashboard UI for initiatives. It establishes the architectural model they should follow.

## Implemented Now

- Sloppy already has tasks, actors, teams, review flows, Visor, worktrees, and persisted artifacts.
- The actor graph already supports hierarchical delegation and peer relationships.
- Visor already supervises long-lived runtime activity and can provide ambient operational state.
- Project roots already support project-specific context and file search.

## Next Changes

- Add a first-class `Initiative` model with explicit phase state.
- Link tasks, reviews, clarifications, and artifacts to an initiative id.
- Add policy-driven transitions between `single-agent`, `delegation`, `swarm`, and `council/review` execution modes.
- Add structured `decision packet` records and resume semantics.
- Move durable initiative artifacts to `<project-root>/.meta/artifacts/` and related `.meta` subdirectories.
- Keep SQLite as an index and query layer for initiative and artifact metadata.
- Expose initiative state, resume point, blockers, and evidence through the Dashboard and API.
- Define loop templates for common technical initiative types such as CI optimization, bugfix, feature delivery, and migration.

## Consequences

Positive:

- Sloppy gets a clear product model for long-lived autonomous technical work.
- Users can interact at the goal and decision level instead of managing each micro-task by hand.
- Actor-based delegation becomes purposeful and policy-driven rather than always-on ceremony.
- Initiative evidence and operational memory become project-local, easier to inspect, and easier to resume.
- The runtime can support both fast-path local work and more complex multi-actor execution without changing the user-facing objective model.

Negative:

- The runtime model becomes more complex than a task-only or chat-only system.
- Initiative orchestration introduces more persistence, policy, and UI surface area.
- Project-local `.meta` state must stay consistent with SQLite indexes and dashboard views.
- Poorly defined success metrics may still cause initiatives to drift or loop too long before escalation.
