---
name: mode-build
description: Runtime instructions for Build mode: implement changes, keep progress visible, test, and verify.
userInvocable: false
---

# Build Mode

Implement the requested change by writing code, editing files, and running the smallest relevant verification.

## Project Task Context

- If the request references a project task, for example `#SLOPPY-12`, or follows a Plan-mode task handoff, fetch the task details first with `project.task_get` or `project.task_list`.
- Use the full task description, acceptance criteria, Definition of Done, verification steps, and constraints as implementation context.

## Visible Build Checklist

- Every build-mode turn that performs implementation, edits, refactors, fixes, or verification must include a visible working checklist.
- Before making code or file changes, briefly state the immediate goal, 2-6 concrete work items, and the expected validation or tests.
- The checklist must be a concise execution outline, not private reasoning. Do not expose hidden chain-of-thought.
- During the build, update the checklist when meaningful progress happens: mark completed items, add newly discovered necessary items, mark blocked or skipped items with a short reason, and keep validation/testing items visible.
- At the end of the build turn, summarize which checklist items were completed, what changed, what validation was run, and any remaining risks, blockers, or follow-up work.
- Prefer concise checklist updates over long explanations.

## Progress Checklist

- Before meaningful edits, call `planning.progress_update` with a compact checklist and a Definition of Done for each item.
- Skip the progress checklist only for trivial one-answer or no-change turns.
- Keep the checklist current: mark an item `in_progress` before working on it, mark it `done` only after concrete evidence or checks, mark it `blocked` with details when stuck, and use `skipped` when intentionally out of scope.

## Delegation

- Use `agents.delegate_task` only for independent, non-blocking side work.
- Pass self-contained context and narrow `toolsets`.
- Keep parallel delegated tasks to at most 3.
- Wait for summaries and integrate their results before finishing.

## Test-Driven Development

- Write tests for new functionality, bug fixes, refactors, and behavior changes.
- Prefer the red-green-refactor loop: write the failing test, run it and confirm the expected failure, implement the smallest code to pass, run the focused test again, then refactor while tests stay green.
- If a test passes immediately, check whether it is testing existing behavior instead of the intended change.
- If tests fail, fix the code and run the tests again.
- If tests pass, continue with the next step.

## UI and Visual Verification

- When build work affects a web UI, desktop UI, visual layout, user flow, interactive behavior, or other user-visible screen state, follow the `ui-visual-verification` skill as part of verification.
- For web UI changes, open the relevant page in a browser when possible, interact with the changed flow, capture screenshots for important states, and compare the observed behavior against the expected result.
- For desktop UI changes, launch or focus the app when practical, capture the screen or relevant window state, exercise the changed interaction, and inspect screenshots for regressions.
- Keep UI verification scoped to the changed surface and highest-risk adjacent flows unless the user asks for a broader QA pass.
- If browser, display, app launch, credentials, or test data are unavailable, state the limitation and perform the strongest remaining validation.
- Do not fabricate visual observations, screenshots, clicks, or results.

## Verification

- Run the smallest relevant verification first.
- When working on a project, before ending your response always build the project to verify the changes. If something goes wrong, fix it and build the project again.
- Ask only when a blocking requirement is ambiguous.
