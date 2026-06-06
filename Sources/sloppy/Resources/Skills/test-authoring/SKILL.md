---
name: test-authoring
description: "Design and write focused unit, integration, regression, and acceptance tests with reliable validation commands."
version: 1.0.0
author: Sloppy Team
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [Development, Testing, QA, Regression, Acceptance]
    related_skills: [tdd-workflow, development-code-review]
---

# Test Authoring

Use this skill when the user asks to add tests, improve coverage, write regression tests, define validation, or convert requirements into executable checks.

## Test Planning

Before writing tests, identify:

- the behavior under test;
- the public API, UI, command, or workflow that exposes the behavior;
- the smallest reliable test level: unit, integration, end-to-end, or manual validation;
- required fixtures, mocks, or test data;
- the focused command to run the new or changed tests.

Prefer the lowest test level that still proves the behavior with confidence.

## Test Types

### Unit Tests

Use unit tests for pure logic, transformations, validators, parsers, reducers, and small services with isolated dependencies.

Good unit tests are fast, deterministic, and specific. Avoid asserting private implementation details unless there is no better seam.

### Integration Tests

Use integration tests when correctness depends on persistence, transport, filesystem behavior, plugin boundaries, generated resources, or interactions between components.

Keep integration fixtures minimal and clean them up reliably.

### Regression Tests

Use regression tests when fixing a reported bug. A good regression test:

- fails before the fix;
- names the previously broken behavior;
- protects against the same class of failure returning;
- avoids overfitting to incidental implementation details.

### Acceptance Tests

Use acceptance tests or scenario tests for user-visible workflows, CLI behavior, dashboard flows, or API contracts.

Acceptance tests should verify outcomes that matter to the user, not every internal step.

## Authoring Checklist

- [ ] The test name states the expected behavior.
- [ ] Arrange/Act/Assert or Given/When/Then structure is clear.
- [ ] Assertions are specific and meaningful.
- [ ] The test is deterministic and does not depend on real credentials, network, clock timing, or global state unless controlled.
- [ ] Fixtures are small and readable.
- [ ] Cleanup is automatic for temporary files, database state, servers, and processes.
- [ ] The focused validation command is documented or run.

## Validation Strategy

Run validation in layers:

1. The single new test or narrowest matching test filter.
2. Nearby tests for the changed component.
3. Broader suite only when risk, conventions, or user request justify it.

Always report exactly what was run and the result. If validation cannot be run, explain the blocker and provide the best available manual verification.

## Common Pitfalls

- Testing implementation details instead of behavior.
- Writing tests that pass before the production change when a regression or TDD flow requires a red step.
- Overusing snapshots without targeted assertions.
- Depending on test order or shared mutable state.
- Hiding flaky timing behavior with arbitrary sleeps.
- Claiming coverage for an edge case that is only indirectly exercised.

## Output Format

When reporting test work, use:

```md
## Test Summary

Added/updated:
- `path/to/test.ext` — covers <behavior>

Validation:
- `<command>` — <pass/fail/not run>

Coverage notes:
- Covered: <cases>
- Not covered / follow-up: <cases or none>
```

## Constraints

- Do not fabricate test results.
- Do not introduce heavyweight test infrastructure without confirming it matches project conventions.
- Do not skip existing project test conventions in favor of a new framework unless explicitly requested.
