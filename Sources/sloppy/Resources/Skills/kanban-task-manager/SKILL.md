---
name: kanban-task-manager
description: Creates and maintains project-board tasks with correct dedupe, umbrella/root linking, dependencies, tags, authors, assignments, and autopilot queue placement.
userInvocable: false
allowedTools:
  - project.current
  - project.task_list
  - project.task_get
  - project.task_create
  - project.task_update
  - project.task_clarification_create
  - memory.save
---

# Kanban Task Manager

Use this skill whenever you create, save, track, decompose, link, assign, retag, or enqueue work as project-board tasks.

## Workflow

1. Call `project.current` to get the project, actors, teams, models, task loop mode, task sync linked projects, and autopilot settings.
2. Call `project.task_list` before creating tasks. Compare active tasks by goal, scope, expected outcome, parent task, tags, and dependencies.
3. Update an existing matching task instead of creating a duplicate. Preserve useful existing description, tags, parent, dependencies, actor/team, selected model, and status unless the user asked to change them.
4. For multi-step work, create one umbrella/root task for the whole objective, then create or update child tasks with `parentTaskId`.
5. Use `dependsOnTaskIds` only when execution order truly matters. Keep independent child tasks dependency-free so parallel or capacity-based execution can work.
6. For task descriptions, use `task-spec-writer` guidance for the canonical brief. This skill owns board placement, links, tags, authors, assignments, and autopilot eligibility.

## Tags

- Keep relevant existing tags.
- Add concise subsystem tags such as `dashboard`, `runtime`, `tools`, `skills`, `api`, `storage`, `client`, or `docs` when they are clearly supported by the request.
- Add type tags such as `bugfix`, `feature`, `refactor`, `test`, `planning`, or `follow-up` when useful for filtering.
- If the work belongs to a configured external board, add the matching `taskSyncSettings.linkedProjects[].tag`.
- Add autopilot include tags only when `autopilotSettings.includedTags` is non-empty and the task should be eligible for autopilot. When `includedTags` is empty, no include tag is required because Autopilot may consider any otherwise eligible root task.

## Authors And Assignments

- Set `changedBy` to a stable audit value for agent-created tasks, preferably `agent:<agentId>` when the current agent id is known.
- If `autopilotSettings.trustedAuthors` is non-empty, autopilot-eligible root tasks must use one of those trusted authors as `changedBy`; otherwise they will not be picked up.
- Set `actorId` or `teamId` only when the user, project context, or existing matching task makes the owner clear.
- Preserve `selectedModel` from an existing related task or parent unless the user asks for a different model.

## Status Policy

- Use `pending_approval` for work that needs human approval before execution.
- When autopilot is enabled and the work should enter autopilot, create a root task in `backlog` with no `parentTaskId`, with an included tag only when `autopilotSettings.includedTags` is non-empty, without any `autopilotSettings.ignoredTags`, and with a trusted `changedBy` if trusted authors are configured.
- Do not set autopilot work to `ready` unless the user explicitly asks for immediate launch. The scheduler will decompose and release eligible `backlog` roots by capacity.
- Use `ready` only for explicit launch, `waiting_input` when a concrete decision is missing, and `blocked` when the task cannot proceed.

## Graph Audit

Before finishing, verify the board shape:

- No duplicate active task already covers the same work.
- Every child task has the intended `parentTaskId`.
- Every dependency references an existing sibling or prerequisite task.
- Umbrella/root tasks summarize the whole objective and child tasks are individually executable.
- Autopilot root eligibility matches `enabled`, `includedTags` (empty means all tags), `ignoredTags` (exclude precedence), `trustedAuthors`, and root-task status.
- Save durable project conventions or recurring tag/author rules with `memory.save` when they should survive the current session.
