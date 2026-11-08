---
name: sloppy-feature-flow
description: Guide Sloppy features and improvements through requirements, English design, human approval, planning, implementation, scripted validation, and independent review. Use when introducing or extending a capability; fixes within an existing contract use the shorter bug workflow.
---

# Sloppy Feature Flow

Read [the accepted workflow](../../../docs/designs/contributor-workflow.md) and
[workflow commands](../../knowledge/workflow.md). Resolve links relative to this skill's directory.

## Classify and Enrich

Inspect the repository and preserve existing work. A new subsystem is a feature; extending an existing
one, including adding a provider to an existing integration or reworking a runtime service, is an improvement.
Ask the human when classification is uncertain. Present the feature flow when a new feature is detected.

Use [sloppy-enrich](../sloppy-enrich/SKILL.md) to settle requirements and design decisions.
Do not ask the user for facts discoverable from code, tests, configuration, or connected tools.
An improvement may need only a focused clarification rather than a full feature interview.

## Design and Human Approval

Create or update the relevant design under `docs/designs/`, in English. Include scope,
behavior, ownership, important alternatives, constraints, platform impact, and acceptance criteria.
An improvement updates the existing design; create a concise design if one is missing.
Include a user-documentation delivery plan: article source, navigation, verified example and docs checks.
Every feature ships a discoverable user-facing article/update. User-facing improvements update their guides;
an internal-only improvement records a reviewed reason. Follow [user documentation](../../knowledge/user-documentation.md).
Reuse accepted ADRs. New lasting architectural decisions belong in `docs/architecture/adr/`;
supersede changed decisions instead of rewriting their historical meaning.

Give the actual document to the user to study. Wait for their explicit approval before planning or
implementation. Silence, a generated status field, or the agent's own judgment is not approval.
Record the source using `approve-design`; explain that a local record is an attestation, not authentication.

## Plan, Implement, Validate

After approval, create the feature implementation plan under `docs/plans/`. Additional
approval of that plan is required only when the user requests it. Improvements do not need a new
permanent plan for every task. Use the module guidance in `AGENTS.md` and
[sloppy-tdd](../sloppy-tdd/SKILL.md) for implementation.
For multi-stage work, define each stage's concrete deliverable, acceptance criteria, owned scope,
required checks and exclusions before implementing it. Record completion with evidence at stage
boundaries; keep the overall task open until every required stage is complete. Approval of all stages
authorizes their execution without repeated approval requests within the accepted contract.
Classify new findings as a regression, an unmet approved requirement, or a pre-existing adjacent issue.
Fix the first two within scope. Record adjacent issues separately unless they prevent the agreed result;
do not silently turn them into more requirements for the current stage.
Declare article/navigation paths with `documentation`; implement the guide in the same change as the code.
An ADR, design, changelog or API comment does not satisfy the user-article requirement. Update the VitePress navigation and verify examples before review. Author sources in `docs/`; `docs/.vitepress/dist/` is generated output.

Initialize local task state with the explicitly owned paths. Expand that scope as files are added;
do not include unrelated user changes. Use the runner before moving to the next stage. Do not edit
validation rules, suppress warnings, or delete tests merely to obtain a passing result.
Missing tools and unavailable required platforms block completion; use corresponding CI/hardware evidence.

## Independent Review and Completion

After the full Code → Review validation, invoke [sloppy-review](../sloppy-review/SKILL.md)
in a separate subagent context. A different model is optional. Supply the task, approved design,
plan, boundaries, diff, and validation report. Keep the reviewer independent of implementation.

Obtain a consolidated first review. Fix implementation findings, rerun affected checks, and request
review of the fixes and affected interactions in the final state. Broaden review when architectural
changes or systemic defects justify it, rather than restarting the entire audit after every fix.
If successive reviews keep discovering new classes of problems, consolidate the remaining acceptance
gaps and revisit the stage boundaries before continuing one finding at a time. Unresolved in-scope
defects and mandatory evidence still block completion; a stage boundary is not a waiver.
Return substantive design changes or ambiguities to the human. Finish with `verify --stage done`.
Report exact passed checks and remaining blockers. A local success does not establish hosted CI,
branch protection, or behavior on platforms that were not exercised.
