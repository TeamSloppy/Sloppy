# ADR 0003: Event-Driven Initiative Triggers

- Status: Proposed
- Date: 2026-06-30

## Context

ADR 0002 establishes `Initiative` as the long-lived runtime object for autonomous technical work. That solves how Sloppy should execute and supervise work once a user or operator explicitly starts an initiative. It does not yet solve how initiatives should start or resume from live external signals such as webhooks, GitHub Actions failures, scheduled checks, or internal runtime alerts.

Without a unified trigger model, each new event source would likely add its own custom entrypoint, bespoke task-creation logic, and ad hoc deduplication. That would fragment the initiative runtime and make the system harder to reason about. The autonomous loop should not care whether the wake-up signal came from a user, a webhook, a failed workflow run, or a scheduler tick. It should receive a normalized event and then use the same initiative dispatch logic every time.

The desired product behavior is event-driven autonomy: an external signal should be able to create a new initiative, resume an existing initiative, or append new evidence to an ongoing initiative without requiring a human to manually rephrase the problem in chat.

## Decision

Treat event ingestion as a normalized trigger pipeline:

1. Ingest raw external or internal event payloads.
2. Normalize them into a typed `TriggerEventRecord`.
3. Resolve a matching `TriggerDefinition`.
4. Dispatch the event into the initiative system using a typed dispatch mode.
5. Let the initiative loop decide how to decompose, execute, escalate, and conclude work.

This separates the trigger layer from the execution layer. Triggers should not directly create arbitrary task trees, launch workers, or bypass initiative policy. Their job is to wake or enrich initiatives, not to replace the initiative runtime.

The system should introduce three new first-class concepts:

- `TriggerDefinition`
- `TriggerEventRecord`
- `InitiativeTemplate`

### TriggerDefinition

A `TriggerDefinition` is a project-scoped rule that describes when and how Sloppy should react to an incoming event.

Recommended fields:

- `id`
- `projectId`
- `source`
- `eventType`
- `enabled`
- `dispatchMode`
- `initiativeTemplateId`
- `filters`
- `dedupeWindowSeconds`
- `maxConcurrentInitiatives`
- `metadata`

### TriggerEventRecord

A `TriggerEventRecord` is the normalized representation of one incoming signal after transport-specific verification and parsing.

Recommended fields:

- `id`
- `triggerId`
- `projectId`
- `source`
- `eventType`
- `externalRef`
- `dedupeKey`
- `status`
- `payload`
- `linkedInitiativeId`
- `dispatchResult`
- `receivedAt`
- `processedAt`

### InitiativeTemplate

An `InitiativeTemplate` provides reusable defaults for initiatives started by triggers.

Recommended fields:

- `id`
- `name`
- `triggerKind`
- `defaultTitle`
- `defaultGoal`
- `defaultSuccessMetrics`
- `defaultConstraints`
- `defaultInitialPhase`
- `defaultExecutionMode`
- `metadata`

### TriggerSource

The trigger system should start with explicit source categories rather than untyped strings:

- `webhook`
- `github`
- `github_actions`
- `cron`
- `runtime_signal`

### TriggerDispatchMode

Dispatch behavior must be explicit:

- `create`
- `resume`
- `resume_or_create`
- `append_only`

### TriggerEventStatus

Event processing should use typed lifecycle state:

- `received`
- `deduped`
- `processed`
- `ignored`
- `rejected`
- `failed`

### TriggerDispatchResult

Dispatch outcomes should be explicit:

- `created`
- `resumed`
- `appended`
- `ignored`
- `rejected`

## Trigger Resolution Model

Trigger processing should follow this sequence:

1. Verify authenticity of the source payload.
2. Normalize the payload into a `TriggerEventRecord`.
3. Compute a `dedupeKey`.
4. Reject or ignore duplicates inside the configured dedupe window.
5. Resolve the active `TriggerDefinition`.
6. Determine whether the event should `create`, `resume`, or `append`.
7. Record trigger activity on the initiative.
8. Wake or create the initiative.

This means the trigger layer is thin and typed. The initiative loop remains the single place where hypothesis generation, task decomposition, verification, decision packets, and escalation rules live.

## Create vs Resume

The dispatch decision should not be implicit or language-based. It should be a policy decision driven by:

- `dispatchMode`
- the event `dedupeKey`
- the event `externalRef`
- the presence of an already-active initiative that matches the same scope

For `resume_or_create`, the runtime should search for an open initiative using:

- the same `projectId`
- the same `initiativeTemplateId`
- the same normalized scope key for that trigger type

If a matching active initiative exists, the event resumes it. Otherwise it creates a new initiative.

## GitHub Actions MVP

The first high-value template should be `ci_failure`.

Recommended trigger:

- `source = github_actions`
- `eventType = workflow_run.failed`
- `dispatchMode = resume_or_create`

The normalizer should extract at least:

- repository
- workflow name
- branch
- commit SHA
- run ID
- run URL
- conclusion

Recommended `dedupeKey`:

`github_actions:<repo>:<workflow>:<run_id>:failed`

Recommended resume scope:

`<repo>:<workflow>:<branch>`

This lets Sloppy avoid duplicate initiatives for the same failed run while still treating repeated failures on the same workflow and branch as evidence for the same ongoing initiative.

## Generic Webhooks

The webhook transport should be generic. Known sources such as GitHub Actions are adapters on top of it, not separate orchestration systems.

Recommended routes:

- `GET /v1/projects/:projectId/triggers`
- `POST /v1/projects/:projectId/triggers`
- `PATCH /v1/projects/:projectId/triggers/:triggerId`
- `DELETE /v1/projects/:projectId/triggers/:triggerId`
- `GET /v1/projects/:projectId/trigger-events`
- `GET /v1/projects/:projectId/trigger-events/:eventId`
- `POST /v1/projects/:projectId/triggers/:triggerId/fire`

The generic fire endpoint should accept raw payload plus transport metadata, then pass through source-specific normalization before dispatch.

## Guardrails

The trigger system must include protection against noisy or malicious event streams:

- source authenticity verification
- payload size limits
- artifact extraction limits
- dedupe windows
- per-trigger rate limits
- `maxConcurrentInitiatives`
- explicit rejection state for invalid or unauthorized events

This keeps event-driven autonomy from turning into event-driven spam or runaway initiative creation.

## Non-Decision

This ADR does not specify the final webhook signature format for each provider.

This ADR does not define full provider-specific adapters for all external systems.

This ADR does not require every event source to create new initiatives. Some sources should only append evidence or resume active initiatives.

## Implemented Now

- ADR 0002 defines the initiative loop and decision packet model.
- Sloppy already supports workflows, automations, task lifecycle events, and source-control-aware project contexts.
- The initiative runtime now supports create, resume-adjacent decision packets, task linkage, completion rules, and dashboard visibility.

## Next Changes

- Add persistence models for `TriggerDefinition`, `TriggerEventRecord`, and `InitiativeTemplate`.
- Add a generic webhook ingestion route.
- Add a GitHub Actions payload normalizer and `ci_failure` initiative template.
- Add create vs resume scope resolution with dedupe windows.
- Add trigger event history in the Dashboard with links to the initiatives they created or resumed.
- Attach normalized trigger payloads as initiative-local evidence artifacts under `.meta`.
- Add rate limiting and max-concurrency enforcement.

## Consequences

Positive:

- Sloppy gets a single architecture for event-driven initiative creation and resume.
- External signals can wake the same autonomous loop already used for human-started work.
- Providers such as GitHub Actions become adapters rather than separate runtime systems.
- Deduplication and resume policy become explicit and auditable.

Negative:

- The orchestration model gains another persistence and API layer.
- Trigger normalization and verification add complexity before initiative execution begins.
- Poorly chosen scope keys or dedupe windows could still create duplicate or stale initiatives.
