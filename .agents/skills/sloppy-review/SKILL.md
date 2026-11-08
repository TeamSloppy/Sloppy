---
name: sloppy-review
description: Independently review a Sloppy change against its accepted scope, code and evidence; re-review fixes and affected interactions. Use in a separate subagent context before task completion.
---

# Sloppy Independent Review

Operate in a separate context from the implementer. A different model is optional. If independent
subagents are unavailable, report a blocker instead of presenting self-review as independent review.

Read applicable AGENTS instructions, [the knowledge index](../../knowledge/README.md), the original
request, accepted design, implementation plan if present, task boundaries, final diff, and runner report.
Inspect implementation and nearest tests yourself. Resolve APIs and platform behavior from real code.
Run targeted additional checks when existing evidence does not establish a material claim.
Use disposable fixtures or task-owned scratch directories; preserve unrelated work.

Check behavioral completeness, regressions, failure paths, architectural boundaries, Swift isolation
and ownership, typed agent decisions, runtime resource handling, meaningful tests, platform compatibility,
unjustified hardcoding, secrets, and design/documentation freshness. Investigate missing analysis,
empty/skipped suites, ignored warnings, broadened exclusions, and stale or misleading reports.
Read recorded TDD exceptions and approval sources; a local JSON field does not authenticate a human.
For each feature, inspect the delivered user article and navigation, not only its design/ADR or API comments.
Verify instructions/examples match the shipped API and platform/backend support; examine docs/example
checks and relevant VitePress builds. User-facing improvements must update guides; internal-only
explanations must be justified. Missing or inaccurate required user documentation prevents approval.

Do not change production code or approve your own fixes. Give the implementer actionable findings
with severity, location, concrete consequence, and expected behavior. Return implementation defects
for correction. Escalate ambiguous requirements and necessary deviations from the accepted design
to the human; do not silently rewrite the design to match the implementation.

On the first pass, inspect the agreed scope and report material findings as a batch. Distinguish:
- A demonstrated defect: a violated requirement, concrete scenario, consequence and evidence
  from code or execution. A new test is not required to prove an obvious defect in code.
- Missing evidence: a critical accepted invariant cannot be established by the available checks.
  Explain the invariant and the meaningful validation needed; do not call it a reproduced defect.
- A recommendation: optional coverage or an adjacent pre-existing issue that does not prevent
  the agreed result. Record it separately from blocking findings.

Re-review corrected findings and the interactions affected by their fixes in the final diff. Reopen
the full audit when architectural changes or a systemic problem warrant it. Do not seek a new class
of hypothetical edge cases just because the previous findings are closed. New real defects still
block acceptance when they violate the agreed scope. If findings keep broadening, consolidate the
remaining acceptance gaps for the implementer instead of issuing one unrelated extension at a time.

Use `snapshot` immediately before recording the final review. Write a local JSON report under
`.artifacts/contribution/` using this schema:

```json
{
  "reviewer": "independent-subagent-id",
  "context": "separate-context-reference",
  "snapshot": "value-returned-by-the-runner",
  "task_fingerprint": "task_fingerprint-returned-by-the-runner",
  "user_documentation_reviewed": true,
  "verdict": "approved",
  "findings": [],
  "recommendations": []
}
```

Use `changes_requested` for implementation findings and `needs_human` for unresolved design decisions.
Never approve while findings remain unresolved or mandatory checks are blocked.
The implementer imports the result with `record-review` and calls `verify --stage done`.
Any subsequent relevant edit requires affected checks and review of the final state. Reused checks
must have matching input contracts and intact logs; a final full-profile report and final-diff review
are still required. A passing stage is not approval of unfinished migration stages.
