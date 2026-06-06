---
name: development-code-review
description: "Review code changes locally for correctness, maintainability, security, tests, and release risk."
version: 1.0.0
author: Sloppy Team
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [Development, Code-Review, Quality, Testing, Security]
    related_skills: [github-code-review, codebase-inspection, tdd-workflow]
---

# Development Code Review

Use this skill when the user asks for a code review, pre-merge review, local diff review, quality pass, or risk assessment that is not specifically tied to GitHub PR operations.

This skill focuses on review judgment and structured findings. Use `github-code-review` when the work requires GitHub PR comments, approvals, or GitHub API/`gh` operations.

## Review Principles

- Review the actual diff first, then inspect full files for context where needed.
- Prioritize correctness, safety, user-visible behavior, maintainability, and test coverage.
- Prefer actionable findings with file/line references and concrete fixes.
- Avoid nitpicks unless they reveal a real maintainability or consistency issue.
- Do not rewrite code unless the user asks for implementation; provide review findings first.

## Standard Review Flow

1. Identify the change scope:
   - `git status --short`
   - `git diff --stat`
   - `git diff --staged --stat` when reviewing staged changes
   - `git diff main...HEAD --stat` when reviewing branch changes
2. Read the diff:
   - `git diff`
   - `git diff --staged`
   - `git diff main...HEAD`
3. Inspect full file context for non-trivial findings.
4. Check tests and validation paths.
5. Produce structured review output.

## Review Checklist

### Correctness

- Does the implementation match the requested behavior?
- Are edge cases handled: empty inputs, nil/null, invalid data, large data, concurrency, retries, and partial failure?
- Are error paths explicit and user-safe?
- Are state transitions and persistence updates consistent?

### Security and Privacy

- No secrets, tokens, credentials, or private data are introduced.
- User input is validated or safely encoded.
- File paths, URLs, shell commands, and SQL queries are protected from injection.
- Permissions, authorization, and tenant/project boundaries are preserved.

### Maintainability

- Names are clear and domain-appropriate.
- The change is localized and avoids unnecessary abstraction.
- Existing architecture and conventions are respected.
- Duplicate logic is avoided or justified.
- Public APIs and data contracts remain backward-compatible unless intentionally changed.

### Testing

- Tests cover the main behavior and important failure/edge cases.
- Existing tests are updated when behavior changes.
- The validation command is appropriate for the changed area.
- Flaky, slow, or environment-dependent tests are called out.

### Performance and Reliability

- No avoidable N+1 queries, unbounded loops, large memory copies, or blocking calls are introduced.
- Async/cancellation behavior remains safe.
- Retries, timeouts, and resource cleanup are considered where relevant.

### Documentation and UX

- User-facing text is clear and consistent.
- Docs, comments, examples, or changelog entries are updated when needed.
- Errors and empty states are actionable.

## Output Format

Use this format for review results:

```md
## Code Review Summary

Overall: <approve | request changes | comments only>
Risk: <low | medium | high>

### Blocking Findings
- `path/to/file.ext:line` — Problem summary.
  - Impact: Why this matters.
  - Suggestion: Concrete fix.

### Non-Blocking Suggestions
- `path/to/file.ext:line` — Suggestion and rationale.

### Test Gaps
- Missing coverage for <case> in <area>.

### Looks Good
- Positive observations about design, tests, or risk handling.

### Validation Reviewed
- Commands inspected or run: `<command>`
- Result: <pass | fail | not run, with reason>
```

## Severity Guidance

- **Blocking**: correctness bugs, security/privacy problems, data loss, broken public APIs, missing required tests for risky behavior, or release blockers.
- **Non-blocking**: maintainability improvements, clarity issues, optional test additions, or small consistency improvements.
- **Nit**: style-only comments. Include only when the user requested a detailed style review.

## Important Constraints

- Do not expose hidden chain-of-thought. Show concise review rationale only.
- Do not fabricate line numbers. If exact line numbers are unavailable, cite file paths and describe the location.
- Do not claim tests passed unless they were actually run or verified from reliable evidence.
