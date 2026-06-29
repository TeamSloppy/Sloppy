# Automations Design

## Status

Proposed design, prepared for review on June 28, 2026.

## Summary

Sloppy should add a first-class `Automations` product surface that lets operators run project workflows automatically on a schedule or in response to external events. The first release should reuse the existing project workflow engine instead of introducing a second orchestration runtime.

An automation is a thin product-layer wrapper around one workflow definition:

- `Workflow`: describes how work executes.
- `Automation`: describes when that workflow should start, with what trigger, in what project/repository context, and with what pre-run policy.

This keeps the system aligned with the existing `WorkflowRunner`, `WorkflowPendingAction`, and Dashboard workflow tooling while moving toward a Cursor-like automation experience.

## Goals

- Add a project-level automation concept that can start workflows automatically.
- Support the first MVP trigger families:
  - manual
  - cron
  - webhook
  - GitHub pull request events
  - GitHub pull request review events
- Keep MVP scope constrained to one automation bound to one project and one repository.
- Allow automations to optionally create or attach a project task before starting the workflow.
- Reuse the existing workflow runtime, human wait states, tool nodes, and run history patterns.
- Expose automation definitions and runs in the Dashboard as a dedicated project surface.

## Non-Goals

- Slack-triggered automations in the first release.
- Multi-repo automations.
- A second automation-specific execution engine.
- Cursor-style team service accounts and full identity matrix in the first release.
- Dedicated per-automation memory stores separate from existing project/agent memory facilities.
- A large built-in library of special-case GitHub actions such as comment/reviewer/PR nodes. Those behaviors should come from workflow steps, not hardcoded automation actions.

## Product Shape

Each project gets a new `Automations` area in the Dashboard.

That area is responsible for:

- listing automation definitions
- creating and editing automation settings
- binding an automation to a workflow
- showing trigger configuration
- showing recent automation runs
- linking to the underlying workflow definition and workflow run

The existing `Workflows` area remains the place where operators visually define execution graphs.

In short:

- `Workflows` = execution graph and runtime behavior
- `Automations` = trigger, repository binding, policy, and run initiation

## MVP Scope

The first release should include:

- project-scoped automation definitions
- project-scoped automation run history
- manual trigger
- cron trigger
- webhook trigger
- GitHub `pull_request` trigger
- GitHub `pull_request_review` trigger
- one automation -> one workflow binding
- one automation -> one repository binding
- optional task creation or task attachment before workflow start
- Dashboard CRUD and run inspection

The first release should not include:

- GitHub issues or issue comments
- Slack triggers
- multi-repo environments
- team-owned automation identities
- automation-level secrets marketplace
- automation-specific DSL blocks beyond the current workflow node system

## Core Model

### AutomationDefinition

`AutomationDefinition` is a new project-scoped object that references one workflow definition.

Suggested shape:

```text
AutomationDefinition
  id
  projectId
  name
  description?
  enabled
  workflowId
  repositoryFullName
  trigger
  taskMode
  model?
  permissionsScope
  createdAt
  updatedAt
```

Notes:

- `workflowId` points at an existing `WorkflowDefinition`.
- `repositoryFullName` is a single bound repository such as `owner/repo`.
- `model` is optional and reserved for future workflow start hints or run metadata.
- `permissionsScope` should be lightweight in MVP and not imply a full Cursor-style service-account model yet.

### TriggerDefinition

`trigger` is a tagged union:

```text
AutomationTrigger
  type = manual | cron | webhook | github_pull_request | github_pull_request_review
  config = typed per trigger kind
```

Trigger configs:

```text
ManualTriggerConfig
  allowed = true

CronTriggerConfig
  schedule
  timezone?

WebhookTriggerConfig
  secretId
  eventName?

GitHubPullRequestTriggerConfig
  repositoryFullName
  actions[]
  branchPatterns[]

GitHubPullRequestReviewTriggerConfig
  repositoryFullName
  reviewStates[]
  branchPatterns[]
```

For MVP:

- `actions[]` can support a narrow allowlist such as `opened`, `synchronize`, `reopened`, `ready_for_review`.
- `reviewStates[]` can support `submitted`, `approved`, `changes_requested`, `commented`.
- branch filtering should be optional but typed.

### TaskMode

Task creation should be optional per automation:

```text
AutomationTaskMode
  none
  create_task
  attach_to_existing_if_match
  create_or_attach
```

Default for MVP should be `none`.

This keeps the GitHub integration flexible:

- some automations only annotate or inspect code
- some automations should create project tasks
- some automations should reuse an existing project task when one already matches the PR

### AutomationRun

Automations should persist their own run records, separate from workflow runs, while linking to them.

Suggested shape:

```text
AutomationRun
  id
  automationId
  projectId
  workflowId
  workflowRunId?
  repositoryFullName
  triggerType
  triggerEventId?
  status
  taskId?
  summary?
  startedAt
  finishedAt?
```

Run statuses:

- queued
- running
- waiting_for_workflow
- completed
- failed
- cancelled
- ignored

`ignored` is important for GitHub/webhook delivery when a trigger arrives but does not match branch, action, or policy filters.

## Runtime Architecture

The implementation should not create a new execution engine.

Instead:

1. Trigger ingestion creates an `AutomationRun`.
2. The automation layer validates the trigger and resolves repository/project context.
3. Optional pre-run task policy executes.
4. The automation layer maps the trigger payload into typed workflow input.
5. The existing `WorkflowRunner` starts the referenced workflow.
6. The automation run stores the linked `workflowRunId`.

This means the automation layer owns:

- trigger ingestion
- policy enforcement
- event filtering
- task pre-processing
- workflow input construction
- run-level audit records

And the workflow layer continues to own:

- graph walking
- tool execution
- agent steps
- human wait states
- retries and conditions
- workflow step history

## Trigger Contracts

### Manual

Manual runs are operator-initiated from the Dashboard.

Input contract:

```json
{
  "source": "manual",
  "actor": "human:admin",
  "inputs": {}
}
```

### Cron

Cron should reuse the existing scheduler primitives where practical, but the scheduling target should become an automation, not just a raw message into a channel.

Input contract:

```json
{
  "source": "cron",
  "schedule": "0 9 * * 1-5",
  "triggeredAt": "2026-06-28T12:00:00Z"
}
```

### Webhook

Webhook should accept a generic typed envelope:

```json
{
  "source": "webhook",
  "eventName": "build.failed",
  "headers": {},
  "body": {},
  "receivedAt": "2026-06-28T12:00:00Z"
}
```

MVP webhook behavior should focus on:

- validating the secret
- mapping the payload into workflow input
- preserving raw payload for debugging

### GitHub Pull Request

GitHub PR events should be normalized into a typed payload rather than passed as opaque prose.

Suggested input:

```json
{
  "source": "github",
  "eventType": "pull_request",
  "action": "opened",
  "repository": {
    "fullName": "owner/repo",
    "defaultBranch": "main"
  },
  "pullRequest": {
    "number": 42,
    "title": "Fix flaky tests",
    "url": "https://github.com/owner/repo/pull/42",
    "headRef": "fix/flaky-tests",
    "baseRef": "main",
    "authorLogin": "octocat",
    "draft": false
  },
  "sender": {
    "login": "octocat"
  }
}
```

### GitHub Pull Request Review

Suggested input:

```json
{
  "source": "github",
  "eventType": "pull_request_review",
  "action": "submitted",
  "repository": {
    "fullName": "owner/repo"
  },
  "pullRequest": {
    "number": 42,
    "title": "Fix flaky tests",
    "url": "https://github.com/owner/repo/pull/42"
  },
  "review": {
    "state": "approved",
    "body": "Looks good",
    "authorLogin": "reviewer"
  },
  "sender": {
    "login": "reviewer"
  }
}
```

## Task Policy

Task policy runs before the workflow starts.

Behavior by mode:

- `none`: do nothing
- `create_task`: always create a new project task from trigger metadata
- `attach_to_existing_if_match`: look up an existing task by deterministic match rules
- `create_or_attach`: try match first, create if none exists

For GitHub-based automations, deterministic match rules should be explicit and typed. Examples:

- repository + PR number
- repository + review event + PR number
- repository + branch + title hash

MVP should prefer the simplest stable rule:

- `repositoryFullName + pullRequest.number`

If a task is created or matched, the resulting `taskId` should be injected into workflow input and stored on the automation run.

## Repository Binding

The MVP must keep repository context simple:

- each automation binds to exactly one repository
- each automation belongs to exactly one project
- GitHub triggers only activate when the repository in the event matches the configured repository

This reduces ambiguity around:

- task matching
- workflow input shaping
- permissions
- auditability
- future webhook routing

Multi-repo support can come later as an explicit extension rather than hidden complexity in the first release.

## Permissions and Identity

The MVP should not attempt to fully clone Cursor’s identity model.

However, the data model should leave room for it with a lightweight field such as:

```text
AutomationPermissionsScope
  private
  project_visible
  project_managed
```

For the first release this can remain mostly UI and policy metadata, with actual execution continuing to use the existing Sloppy integration credentials and project environment wiring.

Important constraint:

- changing visibility must not silently change which GitHub or webhook credentials are used until a future service-account design is implemented

## API Surface

Suggested HTTP routes:

```text
GET    /v1/projects/{projectId}/automations
POST   /v1/projects/{projectId}/automations
GET    /v1/projects/{projectId}/automations/{automationId}
PUT    /v1/projects/{projectId}/automations/{automationId}
DELETE /v1/projects/{projectId}/automations/{automationId}

POST   /v1/projects/{projectId}/automations/{automationId}/run
GET    /v1/projects/{projectId}/automation-runs
GET    /v1/projects/{projectId}/automation-runs/{runId}

POST   /v1/automation-webhooks/{automationId}
POST   /v1/github/automations/events
```

The GitHub ingestion endpoint can later fan out internally to matching automations, but in MVP it should remain tightly scoped to:

- repository match
- trigger type match
- action/state filter match

## Storage

Definitions should be file-backed like workflows so they remain inspectable and portable:

```text
workspace/
  automations/
    <projectId>/
      <automationId>.json
```

Operational history should be SQLite-backed:

- `automation_runs`
- optional `automation_run_events` if needed for ingestion diagnostics

The workflow run history remains in existing workflow tables and is linked by `workflowRunId`.

## Dashboard UX

Project `Automations` tab should include:

- left list of automations
- create/edit form
- trigger type selector
- repository binding field
- workflow picker
- task mode selector
- enable/disable control
- recent automation runs
- run details panel with link to workflow run

Recommended initial editor structure:

1. Basic info
2. Trigger
3. Workflow binding
4. Task policy
5. Recent runs

The UI should not embed the full workflow graph editor directly. Instead it should link to the selected workflow in the existing `Workflows` area.

## Error Handling

Automation ingestion failures should be visible and diagnosable without corrupting workflow state.

Key rules:

- invalid trigger payload -> reject or mark ignored without starting workflow
- repository mismatch -> ignored run or no-op delivery log
- task pre-processing failure -> automation run failed, no workflow run started
- workflow start failure -> automation run failed with linked error details
- duplicate GitHub delivery -> detect by delivery/event ID when available

GitHub and webhook handling should prefer idempotent processing with a stable external event identifier where available.

## Testing Strategy

Add focused tests for:

- automation definition Codable round trips
- file-backed automation definition store CRUD
- task mode policy behavior
- cron/manual/webhook trigger-to-run translation
- GitHub PR event filtering by repository and action
- GitHub review event filtering by repository and review state
- router tests for automation CRUD and run inspection
- Dashboard API client coverage for automation routes

Do not rely on natural-language matching for trigger semantics. All routing decisions must use typed fields.

## Implementation Phases

### Phase 1: Core models and persistence

- add `AutomationDefinition`, trigger DTOs, task mode enums, and `AutomationRun`
- add file-backed automation definition store
- add SQLite persistence for automation runs

### Phase 2: Core service and HTTP API

- add CRUD methods
- add manual run path
- add task pre-processing layer
- add run history queries

### Phase 3: Trigger ingestion

- add cron-backed automation firing
- add webhook endpoint
- add GitHub PR and PR review event ingestion

### Phase 4: Dashboard

- add project `Automations` tab
- add editor and run list
- add links into workflows and workflow runs

### Phase 5: Hardening

- add idempotency for webhook/GitHub events
- add validation and diagnostics
- tighten trigger filter behavior

## Open Follow-Ups

These are intentionally deferred, not unresolved blockers for MVP:

- Slack triggers
- GitHub issue and issue comment triggers
- multi-repo automations
- service-account-backed team-owned automations
- per-automation memory files
- richer GitHub action shortcuts
- workflow templates specialized for automation use cases
