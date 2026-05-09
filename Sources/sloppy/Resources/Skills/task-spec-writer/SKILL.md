---
name: task-spec-writer
description: Automatically turns vague work into structured project task briefs with technical requirements, Definition of Done, verification, RFC/ADR expectations, memory follow-up, and clean handoff notes.
userInvocable: false
allowedTools:
  - project.task_list
  - project.task_create
  - project.task_update
  - memory.save
---

# Task Spec Writer

Use this skill whenever you create or materially update a project task. The goal is to leave a task that another agent or engineer can execute without guessing intent, scope, acceptance criteria, or durable context.

## Workflow

1. Inspect existing active tasks with `project.task_list` before creating a new task.
2. Compare by intent, goal, scope, and expected outcome. Update the existing task if it already covers the work.
3. Clarify only high-impact unknowns that would change scope, risk, ownership, or acceptance criteria.
4. Write one canonical task brief in the task description.
5. Add or link RFC/ADR material when the work changes architecture, APIs, persistence, migrations, security posture, or other high-risk behavior.
6. Save durable decisions, user preferences, project conventions, and follow-up obligations with `memory.save` using an explicit scope.

## Task Brief Template

```markdown
## Goal

## Context

## In Scope

## Out of Scope

## Technical Requirements

## Implementation Notes

## Definition of Done

## Tests / Verification

## RFC / ADR

## Memory / Follow-up
```

For small tasks, keep sections short, but do not omit `Definition of Done` or `Tests / Verification` unless the task is purely conversational and not meant for execution.

## Section Guidance

- `Goal`: the outcome, not the implementation step.
- `Context`: relevant repo, product, user, or prior-decision context.
- `In Scope`: concrete behavior and files/subsystems expected to change.
- `Out of Scope`: tempting adjacent work that should not be done.
- `Technical Requirements`: API contracts, data model constraints, compatibility, performance, security, concurrency, UI, or platform requirements.
- `Implementation Notes`: suggested approach, constraints from current code, and known pitfalls.
- `Definition of Done`: observable completion criteria and acceptance checks.
- `Tests / Verification`: exact tests, builds, manual QA, or evidence expected.
- `RFC / ADR`: link an existing artifact, name the new artifact to create, or explicitly say `Not required` with a reason.
- `Memory / Follow-up`: what should be saved with `memory.save`, and what can wait.

## RFC / ADR Policy

Use `docs/adr/` for repository-level durable architecture decisions. Use `.sloppy/adr/` only for workspace-private planning artifacts or when the repository already keeps Sloppy planning there. Link the artifact path from the task description.

Create or update an RFC/ADR when a task includes any of the following:

- public API or wire model changes;
- database schema, migrations, or persistence policy changes;
- architecture, runtime, concurrency, or routing decisions;
- security, permissions, or data-retention changes;
- cross-module behavior that future agents must understand;
- a tradeoff where alternatives were considered and rejected.

## Memory Policy

Use `memory.save` for facts that should survive the current session:

- accepted decisions and rationale;
- user preferences and team conventions;
- project-specific implementation constraints;
- recurring DoD or verification expectations;
- follow-ups that are not fully represented by a project task.

Always set scope explicitly. For a current agent session use `scope_type: channel` and the real `agent:<agentId>:session:<sessionId>` scope id. For agent-wide conventions use `scope_type: agent` and the agent id.
