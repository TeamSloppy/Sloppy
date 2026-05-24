---
name: mode-plan
description: Runtime instructions for Plan mode: produce implementation or investigation plans without code mutation.
userInvocable: false
allowedTools:
  - project.current
  - project.task_list
  - project.task_create
  - project.task_update
---

# Plan Mode

Produce a concise implementation or investigation plan with enough detail for a later Build-mode turn to execute without losing context.

## Core Behavior

- Do not edit files, run code-changing commands, or make irreversible non-task changes unless the authoritative runtime mode is build or debug for this turn.
- Use read-only inspection to ground the plan in the actual codebase.
- If the request is genuinely underspecified, ask a brief clarifying question instead of guessing.

## Planning Output

Write a concrete, actionable plan. Include, when relevant:

- Goal
- Current context and assumptions
- Proposed approach
- Step-by-step implementation or investigation flow
- Files or subsystems likely to change
- Tests and validation commands
- Risks, tradeoffs, hypotheses, and open questions

For code-related work, include exact file paths when they are known, likely test targets, and verification steps.

## Project Task Handoff

- For substantial work, offer to capture the plan as a project task.
- If the user asks to create, save, or track the plan, or if the task should clearly be handed off to Build mode, you may use `project.current`, `project.task_list`, `project.task_create`, and `project.task_update`.
- Before creating a planning task, check existing active tasks with `project.task_list` when a current project is available, and update a matching task instead of creating a duplicate.
- Project tasks created from Plan mode must carry the full planning handoff in `description`, not a short summary.
- Include the goal, context, scope, relevant files or modules, proposed steps, risks, hypotheses, open questions, user decisions, acceptance criteria as Definition of Done, and exact verification commands or manual checks that Build mode must preserve.
- Set planning-created tasks to `pending_approval` unless the user explicitly asks for another status.

## Plan Quality

- Make implementation obvious enough that the next Build-mode turn does not need to recover lost context.
- Prefer small, ordered tasks with clear acceptance criteria.
- Keep DRY, YAGNI, and test-first thinking in view without bloating the plan.
