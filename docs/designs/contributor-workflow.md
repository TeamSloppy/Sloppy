# Contributor workflow

Adoption date: 2026-11-04. This ports the contributor infrastructure requested by the
maintainer from AdaEngine to Sloppy. The migration itself is authorized by that request;
the design-approval stages below govern subsequent feature and improvement work.

## Purpose and scope

People and coding agents use one process and one deterministic validation runner.
Instructions and skills guide decisions; reports establish which commands actually ran.
This infrastructure changes contributor tooling, not Sloppy's product agent runtime.

Preserve the existing SwiftPM, Dashboard, Apple client, SQLite and router boundaries.
Do not add language heuristics to interpret agent behavior. Keep unrelated work intact.

## Work classification and approval

| Kind | Flow |
| --- | --- |
| Feature: a new capability/subsystem | Task → Enrich → Design → human approval → Plan → Code → Review |
| Improvement: extend or rework an existing subsystem | Focused clarification → design update → human approval → implementation → validation → review |
| Bug/maintenance within an existing contract | Reproduce → implement → validate → independent review |

Adding a provider to an existing integration is an improvement. If classification affects
the contract and remains uncertain after inspection, ask the human. Improvements update
the affected design; where none exists, describe current behavior and the proposed change
concisely. Bugs need design approval only when their fix changes the agreed contract.

Designs are English and include behavior, scope, ownership, compatibility, alternatives,
platform impact, observable acceptance criteria and documentation delivery. Present the
actual document and wait for explicit approval before implementation. Reuse approval
already given for the same scope. Silence and agent-authored status fields are not approval.
After approval the agent plans, implements, validates and resolves review findings autonomously.

For multi-stage work, define each stage's deliverable, acceptance criteria, owned scope,
required checks and exclusions before coding it. Close stages with evidence independently;
stage completion never implies that the entire migration is complete. Classify new findings as
regressions, unmet approved requirements, or pre-existing adjacent problems. Fix the first two
within scope; record the third separately unless it prevents the agreed result.

Keep existing documents in `docs/specs/`, `docs/product/`, `docs/architecture/` and
`Apps/docs/adr/`; new designs use `docs/designs/`, feature plans use `docs/plans/`.
An ADR records a lasting decision and rationale. A PRD records requirements; small features
may combine requirements and design. Supersede ADRs rather than rewriting past decisions.

Every feature ships a user-facing article/update, usage example, limitations and navigation.
Public improvements update their guide; internal improvements declare a reviewer-visible
reason why no public guide changes. `docs/.vitepress/dist/` is generated, while Markdown
under `docs/` is authored source. Design/ADR/plan documents do not satisfy this requirement.

## Skills and knowledge

- `sloppy-feature-flow` routes work and enforces stage readiness.
- `sloppy-enrich` settles actual decisions; repository facts are researched independently.
- `sloppy-tdd` uses small behavioral Red → Green → Refactor cycles with retained logs.
- `sloppy-review` runs in a separate subagent context; a different model is optional.

The knowledge base lives in `.agents/knowledge/`. Read only affected subsystem guidance.
The mandatory module/style rules remain in `AGENTS.md` rather than being duplicated.

## Validation and evidence

`python scripts/check_contribution.py` is the common entry point for agents, people,
hooks and CI. `.agents/validation.json` selects profiles from exact changed paths,
including untracked files, deletions and both sides of renames. Owned local packages
are included; third-party `Vendor/` code is not treated as owned source.

The runner uses argv arrays, bounded subprocesses and compact status output. Full logs,
task state and JSON reports live under ignored `.artifacts/contribution/`. It never
modifies source to make checks pass, silently installs tools, or stashes/resets work.
Use Python 3.11+ for the analyzer environment; the orchestrator supports Python 3.9+.

Profiles cover content/diff checks, local secret detection, Ruff, Bandit, Python suites,
SwiftLint lint/analyze, Swift builds/tests and both release executables, downstream Apple
client checks, Dashboard TypeScript/build/tests, and VitePress builds. Initial SwiftLint
rules are deliberately small and version controlled; no mass formatting is part of adoption.
Dashboard has no configured ESLint: content/diff checks provide style validation and
`tsc --noEmit` provides type analysis. Do not claim ESLint ran.

SwiftLint analysis consumes the current verbose compiler log and blocks if compilation
evidence is missing. Runtime smoke, cross-platform and non-Python dependency checks need
real, reviewable argv recipes when not covered by built-in commands. Their absence is a
blocker, not an implied success. Unit tests are not universal SAST/DAST scanners.

| Result | Meaning | Can satisfy completion? |
| --- | --- | --- |
| `passed` | Required command ran and its output requirements passed | Yes |
| `failed` | Command found a problem | No |
| `blocked` | Tool, environment, adapter or execution evidence is missing | No |
| `not_applicable` | Explicit profile rule excludes the check with a reason | Yes, subject to review |
| `deferred` | Publication-only: unavailable locally, assigned to a real CI job | No |

Timeouts, crashes, empty/fully skipped test runs and missing logs never count as success.
Reports bind source/index/new-file snapshots, task scope, tool state, commands and log
hashes. After changes, rerun affected checks and obtain review of the final state. Local
approval/reviewer records are attestations; they do not authenticate a human or subagent.

TDD Red must show the expected behavioral assertion failure before the production fix.
Import/build/environment failures do not establish Red. Green uses the same command and
test content. Record applicability explanations for prose-only or already implemented
bootstrap work instead of manufacturing historical Red records.

Related cases of one behavior may share a focused Red/Green cycle. Refactor is conditional:
rerun after an actual refactoring change, not merely to rename an unchanged Green result.
Run owning/downstream suites at stage boundaries and the full applicable profile before final
review. Keep identified TDD cycles and their original logs; starting another cycle must not erase
earlier evidence. Existing task state and commands remain readable.

Successful built-in checks may be reused individually when their declared source dependencies,
execution contract, relevant tools/environment and retained log hashes still match. Swift checks
cover all native source/resource roots and manifests; changing a plan alone does not invalidate
them. Known contributor Python checks cover their tooling and fixtures. Unknown dependencies
fall back to the full repository snapshot. Node checks rerun because their ignored transitive
dependencies are not fully captured. Failed, blocked, quick and partial-lane evidence cannot
replace a required complete check. Assemble a fresh complete report for the final worktree and
review that final diff; reuse is never a waiver of required coverage.

## Review, hooks and CI

Before Code → Review run the full applicable profile. A separate reviewer inspects the
request, approved design, plan, final diff, tests, documentation, platform limits and logs.
The reviewer returns `approved`, `changes_requested`, or `needs_human`, tied to the final
snapshot and task fingerprint. The implementer fixes defects; material contract changes
return to the human. Self-review cannot replace the separate context.

The first review reports material findings as a batch, distinguishing demonstrated defects,
missing evidence for critical requirements, and optional recommendations. Blocking findings
identify the violated requirement, concrete scenario, consequence and evidence. Re-review fixes
and their affected interactions; repeat the whole audit when changes are architectural or reveal
a systemic issue. Additional coverage alone is not a demonstrated defect. All unresolved defects
in the agreed scope and missing mandatory evidence still prevent approval.

Hook installation is explicit and local. Existing hooks are backed up and chained with
their arguments, stdin and exit status preserved, including Git LFS. Custom shared/external
hook paths require manual integration. Pre-commit checks staged content and rejects partial
staging/dirty tracked worktrees; pre-push requires the outgoing commit checked out cleanly.
New branches compare against the configured remote merge base, falling back to tracked files.

Publication permits unavailable local checks to defer only to configured, enabled push/PR
jobs. Local failures remain blocking. Unmapped missing adapters also block. Publication and
individual CI-lane reports cannot close a task. Fresh exact-coverage complete reports may
be reused only after snapshot, tool, command and log verification. Node-backed checks
rerun instead of reusing reports for an ignored transitive dependency graph.

Contributor CI runs the same selected commands in portable, Swift, client, native-client, Dashboard and
documentation lanes; the aggregate `Contributor gate` requires selected lanes to succeed.
Legacy disabled Swift-test jobs are not evidence. Existing Linux/macOS release builds,
Windows runtime CI and Dashboard happy-path CI remain relevant downstream checks.
Collect their actual results before claiming supported-platform behavior. CI-lane reports
explicitly identify their limited scope; they do not assert full local task completion.

Hooks are bypassable. A committed workflow does not establish server branch protection.
Making `Contributor gate` a required server status and confirming a hosted run are rollout
steps outside local code validation. Do not claim those settings were changed without evidence.

## Acceptance

The four local skills and knowledge navigation exist; shared profiles cover Sloppy's real
modules and commands; behavioral fixtures prove failures, timeouts, empty tests, stale
evidence, scope changes, documentation gates and hook preservation; imported MIT notices
are preserved; contributor instructions expose the runnable workflow. Report local checks
separately from hosted CI, native platform checks and branch-protection rollout.
