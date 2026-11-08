---
name: sloppy-tdd
description: Implement testable Sloppy behavior and bug fixes through focused Red/Green cycles, conditional refactoring, and retained production-path evidence. Use during implementation after any required design approval.
---

# Sloppy TDD

Read [testing and validation](../../knowledge/validation.md) and
[runner commands](../../knowledge/workflow.md). Respect any pending design approval.
New Swift package tests use Swift Testing; Python and JavaScript follow the owning suite's conventions.

Identify one observable behavior and its owning module. Inspect neighboring production code and tests.
Select a focused test command that runs deterministically and selects at least one relevant test.
For a bug, reproduce the actual failure; for new behavior, express the next missing behavior.
Related cases of one behavior may share a cycle. Use a focused command for Red/Green, owning and
downstream suites at stage boundaries, and the full applicable profile before final review.

## Red

Write the focused test before the production change. Run `tdd --phase red` with the exact argv,
test-file paths, expected failure expression, and a behavioral explanation.
Read the result to establish that the intended assertion failed. Missing dependencies, import/syntax
errors, timeouts, and broken builds are not behavioral Red evidence; resolve the prerequisite first.
Use `--cycle ID --behavior "observable behavior"` to identify a new Red when useful. Green/Refactor
may select that ID; existing commands default to the latest cycle. `tdd-history --task TASK` exposes
retained cycles and attempts. Do not manually copy JSON between cycles or overwrite original logs.

Do not introduce deliberate production defects merely to manufacture a Red phase. If an existing test
already covers the behavior, identify the missing scenario or record a justified applicability explanation.
Do not replace real project, filesystem, service, UI, or runtime behavior with a source-text check
or mock-only assertion when that production path is material.

## Green

Implement the smallest production change satisfying the test. Run `tdd --phase green` with the same
command and unchanged test content. A passing test after changing its expected result does not complete
the previous cycle; start a new Red cycle if the requirement genuinely changes.
Work in behavior slices rather than writing all tests and the full implementation in separate batches.

## Refactor

After Green, assess whether refactoring is useful. If no further code change is needed, retain Green
as the completed cycle; do not repeat an identical command solely to create a Refactor record.
After an actual behavior-preserving refactor, run `tdd --phase refactor` and the affected checks.
Watch actor isolation, Sendable, ownership, typed events, allocations, and platform conditionals.
Use the shared runner before independent review. It can reuse successful built-in checks whose
declared inputs, tools and logs still match; the final report must cover the complete current scope.

For documentation-only changes or cases without testable behavior, record `explain-tdd --reason` and
make the explanation visible to the reviewer. An unavailable test environment is blocked, not inapplicable.
Do not claim historic TDD ordering from a final green run. Bootstrap/external test evidence requires an
explicit explanation and review of the original logs or transcript, not fabricated phase records.
