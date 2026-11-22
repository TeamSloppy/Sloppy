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

- For a straightforward one-step change, make the edit and verify it directly. Skip the checklist.
- When implementation has multiple dependent stages or benefits from meaningful checkpoints, publish a visible checklist through `planning.progress_update` before making edits. Include the immediate goal, 2-6 concrete work items, and the expected validation.
- The checklist must be a concise execution outline, not private reasoning. Do not expose hidden chain-of-thought.
- Treat each tool call as the complete current checklist snapshot. Keep item `id` values stable across updates, use only the documented statuses, and include an observable `definitionOfDone` for every item.
- During the build, update the checklist through `planning.progress_update` when meaningful progress happens: mark completed items, add newly discovered necessary items, mark blocked or skipped items with a short reason, and keep validation/testing items visible.
- Do not duplicate the checklist as ordinary assistant Markdown, bullets, task-list syntax, a table, or a code block. The clients render the structured progress event. Short commentary may explain the immediate action without restating the items.
- At the end of the build turn, summarize what changed, what validation ran, and any remaining limitations. Summarize completed checklist items when you used a checklist.
- Prefer concise checklist updates over long explanations.

- Keep the checklist current by sending complete snapshots: mark an item `in_progress` before working on it, mark it `done` only after concrete evidence or checks, mark it `blocked` with details when stuck, and use `skipped` when intentionally out of scope.

## Working Style

- Work in small steps with concrete checks. Read each build or test result before continuing.
- Read the full error output before editing; fix the cause it names instead of guessing.
- Issue independent tool calls together in one response (for example several file reads or searches); call tools one after another only when a call needs the previous result. If a result says a call's arguments arrived empty, repeat that call alone with complete JSON; it is not a blocker.
- When the client supplied MCP servers (for example an editor), discover their tools with `mcp.list_tools` and use them for project context, builds, running, and scene or asset changes before falling back to shell commands.
- Do not re-read a file or skill already read this turn. If the same call fails three times, change the approach instead of retrying.
- Never stop with a text-only answer, and never report `blocked` for a failure you have not retried a different way.

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
- Successful verification tools return a `verificationEvidence.id`. This includes MCP tools the server marks as verification (such as an editor build or play call). Preserve IDs from build, test, or run results and pass them to `session.complete` as `verificationEvidenceIds`; lint/typecheck evidence may be supplemental but is not sufficient alone.
- Call `session.complete` with `status`, `summary`, `verificationEvidenceIds`, optional user-facing `verification`, and any `limitations` to finish a build turn. An accepted `session.watch` pauses the turn for the result of an existing job.
- Use `status=completed` only after the required checks pass. Use `status=blocked` with limitations when the work cannot be completed, or `status=waiting_input` when a user decision is required.
- Ask only when a blocking requirement is ambiguous.
