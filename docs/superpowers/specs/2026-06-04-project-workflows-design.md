# Project Workflows Design

## Status

Proposed design, approved for implementation planning on June 4, 2026.

## Summary

Sloppy should add a project-scoped visual workflow board for coordinating work between humans, agents, teams, tools, and project tasks. The feature is inspired by visual automation tools such as n8n, but its first-class purpose is project execution rather than generic service integration.

The workflow board answers a different question than the existing Actors Board:

- Actors Board: who exists, what roles they have, how actors and teams relate.
- Workflow Board: when each actor, team, human, or system step participates in a project process.

The first release should be Dashboard-first and team-oriented. Human participation happens through Dashboard pending actions, not Telegram or Discord. Workflow definitions are project-scoped, reusable, and visually editable. Workflow runs are persisted, inspectable, and tied to a specific workflow definition version.

## Goals

- Give project teams a visual, inspectable process for AI-assisted work.
- Make agent work, human approvals, tool checks, retries, and task updates visible in one graph.
- Support reusable project playbooks such as bug fix, feature implementation, review, release prep, and health check workflows.
- Keep control flow typed and deterministic. Do not branch on model prose or localized phrases.
- Preserve auditability through persisted workflow runs and per-step history.
- Integrate with existing project tasks, agents, tools, Actors Board, and Dashboard patterns.

## Non-Goals

- A fully generic n8n clone for arbitrary integrations in the first release.
- Telegram, Discord, or external-channel human approvals in the first release.
- Distributed workflow scheduling or multi-node execution.
- Parallel branch execution in the first MVP, unless it falls out naturally from the graph walker.
- Replacing Actors Board routing, Swarm, or Project Tasks.

## Product Shape

Each project gets a `Workflows` area in the Dashboard.

The area has two modes:

- Design: visual editor for workflow definitions.
- Run: live execution view for a specific workflow run.

Users can also start a workflow from a project task via a `Run workflow...` action. This keeps workflows close to the work they operate on.

## Workflow Concepts

### Definitions

A workflow definition is a versioned graph scoped to a project. It contains lanes, nodes, edges, and editor layout data.

Definitions should be file-backed so project workflows remain inspectable and operator-editable:

```text
workspace/
  workflows/
    <projectId>/
      <workflowId>.json
```

### Runs

A workflow run is one execution of one definition version. Runs and run steps should be SQLite-backed because they are operational history, need status queries, and power Dashboard views.

Each run records the definition version used at start. Editing the workflow later must not mutate or reinterpret existing runs.

### Lanes

Lanes represent responsibility. They make the board useful to a team, not only visually pleasant.

Common lane kinds:

- System
- Human owner
- Manager agent
- Developer team
- Reviewer agent
- QA

Lane labels are project-specific. A node's lane tells the team who owns that step.

## MVP Node Types

The first release should support these node types:

- Trigger: start/manual entry point, later extended to task-ready, cron, Visor, GitHub, and webhook triggers.
- Project Task: load or bind the current task context.
- Agent Step: ask an actor or team to perform work through existing agent/session/project-worker machinery.
- Human Approval: pause the run until a Dashboard user approves, rejects, or requests changes.
- Human Input: pause the run until a Dashboard user provides text or structured input.
- Tool Check: run an approved check or tool, such as a project verification command.
- Condition: branch on typed step output or run context.
- Update Task: update project task status, assignment, notes, or metadata.
- Notify / Comment: add a project-visible comment or notification.
- End: finish the run with completed, blocked, failed, or cancelled outcome.

## Execution Semantics

### Deterministic Graph Walker

The MVP runner should be a deterministic graph walker inside CoreService.

Basic flow:

1. Start from the trigger/start node with run context.
2. Execute the current node.
3. Persist step status, input, output, error, and timestamps.
4. Select the next edge from typed node result.
5. Pause when waiting for a human or long-running agent step.
6. Resume when the Dashboard action or runtime callback arrives.

### Run States

Workflow run statuses:

- queued
- running
- waiting_for_human
- waiting_for_agent
- blocked
- failed
- completed
- cancelled

Step statuses:

- pending
- running
- waiting
- succeeded
- failed
- skipped

### Typed Outputs

Workflow control flow must use typed outputs, not natural-language interpretation.

Example agent step result:

```json
{
  "status": "succeeded",
  "summary": "Implemented the task and updated tests.",
  "artifacts": [],
  "suggestedTaskStatus": "in_review"
}
```

Example human approval result:

```json
{
  "decision": "approved",
  "comment": "Looks good to merge."
}
```

Conditions branch on fields such as `status`, `decision`, `checksPassed`, or explicit output keys.

### Human Wait States

Human steps are first-class wait states. A human approval or input step creates a Dashboard pending action with:

- project ID
- workflow run ID
- node ID
- task ID when applicable
- assignee
- prompt
- available decisions
- created timestamp

The run remains paused until the user acts. The action result is persisted as the step output and the graph walker resumes.

### Loops and Retry Limits

Loops are allowed but must have policy. For example:

```text
Tool Check failed -> Developer Agent fixes -> Tool Check again
```

Any cycle must declare a limit, such as `maxAttempts`. When the limit is reached, the workflow blocks or escalates to a human step.

### Failure Handling

Failures must become team-visible work:

- mark the step failed or waiting
- mark the run failed or blocked
- persist error details
- show the node in the run overlay
- create a pending action when a human decision is needed

## Data Model

Shared API models should live in `Sources/Protocols/APIModels.swift`.

Suggested model shape:

```text
WorkflowDefinition
  id
  projectId
  name
  version
  lanes[]
  nodes[]
  edges[]
  enabled
  createdAt
  updatedAt

WorkflowLane
  id
  title
  kind
  actorId?
  teamId?

WorkflowNode
  id
  type
  title
  laneId
  config
  positionX
  positionY

WorkflowEdge
  id
  sourceNodeId
  targetNodeId
  conditionKey?

WorkflowRun
  id
  workflowId
  workflowVersion
  projectId
  taskId?
  status
  currentNodeIds[]
  startedBy
  startedAt
  finishedAt?

WorkflowRunStep
  id
  runId
  nodeId
  status
  input
  output
  error
  startedAt
  finishedAt?
```

Flexible node configuration and typed step output can start as JSON values, but externally visible enums should be explicit.

## API Surface

The MVP should expose project-scoped endpoints:

```text
GET    /v1/projects/{projectId}/workflows
POST   /v1/projects/{projectId}/workflows
GET    /v1/projects/{projectId}/workflows/{workflowId}
PUT    /v1/projects/{projectId}/workflows/{workflowId}
DELETE /v1/projects/{projectId}/workflows/{workflowId}

POST   /v1/projects/{projectId}/workflows/{workflowId}/runs
GET    /v1/projects/{projectId}/workflow-runs
GET    /v1/projects/{projectId}/workflow-runs/{runId}
POST   /v1/projects/{projectId}/workflow-runs/{runId}/cancel

GET    /v1/projects/{projectId}/workflow-actions
POST   /v1/projects/{projectId}/workflow-actions/{actionId}/resolve
```

The run creation request can include `taskId`, `startedBy`, and optional input.

## Dashboard UX

### Workflows Area

The project `Workflows` view should have:

- left sidebar: workflow list, deferred template imports, recent runs
- center: lane-based canvas with nodes and edges
- right panel: selected node configuration, validation issues, run step details

### Design Mode

Design mode supports creating nodes, connecting edges, editing node config, arranging lanes, saving definitions, and validating before run.

Validation should catch:

- missing start/trigger node
- dangling required nodes
- condition nodes without branches
- agent steps without actor or team binding
- human steps without Dashboard assignee
- cycles without retry policy

### Run Mode

Run mode renders the same graph with execution overlay:

- completed: green
- running: blue
- waiting for human: yellow
- failed or blocked: red
- skipped: gray

Clicking a run step shows input, output, artifacts, errors, timestamps, and actor or human owner.

### Pending Actions Inbox

Human actions should also appear outside the canvas in a project-level pending actions inbox. This prevents users from having to inspect a graph to discover that they need to act.

Each item should show:

- workflow name
- task title when applicable
- waiting step
- prompt
- primary decisions

## Integration Points

- Project Tasks: workflows can start from, update, and annotate tasks.
- Actors Board: agent, human, and team references come from the actor graph; workflow nodes do not duplicate actor definitions.
- Agent runtime/session orchestration: agent steps reuse existing execution machinery rather than inventing a separate model-call path.
- Tool policy: tool checks run through existing authorization and execution services.
- Visor: future bulletins can include blocked workflow runs and pending human actions.
- Dashboard routing: Workflows become a project route and project task action.

## Recommended MVP

Build the first implementation in this order:

1. Shared workflow models and validation helpers.
2. File-backed workflow definition store.
3. SQLite-backed run, step, and pending-action persistence.
4. CoreService workflow CRUD and manual run APIs.
5. Simple graph runner for start, project task, condition, update task, human approval, and end nodes.
6. Agent step and tool check integration.
7. Dashboard Workflows view with lane canvas, node inspector, validation, and save.
8. Run overlay and pending actions inbox.
9. `Run workflow...` action from project tasks.

## Deferred Capabilities

- Automatic triggers for task-ready, cron, Visor, GitHub, and webhooks.
- Workflow templates and import/export.
- External-channel human approvals.
- Parallel branches.
- Rich retry/backoff policies.
- Workflow run SSE stream.
- Marketplace-like workflow presets.
- Full integration-node catalog similar to n8n.

## Open Questions

- Whether workflow definitions should be editable as raw JSON in the Dashboard.
- Whether workflow run history should support replay from a previous step.
- Whether project templates should ship in repo docs, workspace files, or backend defaults.
- How deeply agent steps should integrate with existing Swarm behavior in the MVP.
