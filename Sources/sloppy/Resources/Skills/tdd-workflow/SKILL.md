---
name: tdd-workflow
description: "Drive implementation with test-first red-green-refactor workflow and focused validation loops."
version: 1.0.0
author: Sloppy Team
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [Development, TDD, Testing, Build, Refactor]
    related_skills: [development-code-review, test-authoring]
---

# TDD Workflow

Use this skill when the user asks to implement behavior with TDD, add a regression fix, build from acceptance criteria, or create tests before changing production code.

## Core Loop

Follow a visible red-green-refactor loop:

1. **Clarify behavior**: identify the smallest observable behavior to prove.
2. **Red**: write or update a focused failing test first.
3. **Verify red**: run the smallest relevant test command and confirm the expected failure.
4. **Green**: make the minimal production change to pass.
5. **Verify green**: rerun the focused test, then broaden validation as needed.
6. **Refactor**: improve structure while preserving behavior.
7. **Final validation**: run the agreed test scope and summarize results.

## Build-Mode Checklist Integration

When active in build mode, include the visible build checklist with TDD-specific items:

```md
Goal: Implement <behavior> using TDD.

Checklist:
- [ ] Identify the expected behavior and test seam
- [ ] Add a failing test for the behavior
- [ ] Run focused test and confirm red
- [ ] Implement minimal production change
- [ ] Rerun focused test and confirm green
- [ ] Refactor if needed and rerun validation
```

Update the checklist after each meaningful red/green/refactor milestone.

## Choosing the First Test

Prefer a test that is:

- user-observable or API-observable;
- small enough to fail for one clear reason;
- close to the behavior boundary, not implementation details;
- stable and deterministic;
- easy to run repeatedly.

If no test framework exists, first inspect project conventions and propose the smallest test harness addition before creating one.

## Regression Fix Flow

For bugs and regressions:

1. Reproduce the bug manually or with existing tests.
2. Add a regression test that fails for the reported bug.
3. Confirm the test fails for the correct reason.
4. Fix the bug with the smallest safe change.
5. Confirm the regression test passes.
6. Run nearby tests to guard against collateral damage.

## Test Quality Checklist

- The test name describes behavior, not implementation.
- The test fails before the production change.
- Assertions prove the important outcome, not incidental details.
- Edge cases and failure paths are covered when risk justifies them.
- The test avoids sleeps, network dependencies, real credentials, and order dependence unless explicitly required.
- Fixtures are minimal and readable.

## Refactor Guidance

Refactor only after a green test unless the code cannot be safely tested without a small seam extraction. During refactor:

- keep behavior unchanged;
- rerun the focused test after structural changes;
- avoid mixing broad cleanup with the requested feature;
- call out any follow-up cleanup that is valuable but out of scope.

## Output Expectations

In the final response, include:

- the behavior implemented;
- the failing test added or updated;
- evidence that the test failed before the fix when available;
- production files changed;
- validation commands and results;
- any remaining risk or follow-up work.

## Constraints

- Do not invent red/green evidence. If the red step could not be run, say why.
- Do not expose hidden chain-of-thought. Show concise TDD rationale and visible checklist updates only.
- Do not broaden the test suite excessively when a focused command is enough for the current step.
