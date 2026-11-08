---
layout: doc
title: Contributor Validation
---

# Contributor validation

People and coding agents share the [contributor workflow](../designs/contributor-workflow.md).
New features have an English design approved by the human, then a plan, implementation,
scripted validation and independent agent review. Improvements update the affected design;
fixes within an existing contract need reproduction, validation and review.

## Setup

Create a dedicated Python 3.11+ environment; ordinary runner orchestration supports 3.9+.
Install the analyzer dependencies explicitly. This does not install Swift, SwiftLint, Node,
Xcode or browser dependencies; use the relevant build guide for the affected product.

```sh
python3 -m venv .artifacts/contribution-tools
.artifacts/contribution-tools/bin/python -m pip install -r scripts/contribution-requirements.txt
.artifacts/contribution-tools/bin/python scripts/check_contribution.py plan --base origin/main
```

Windows PowerShell:

```powershell
python -m venv .artifacts/contribution-tools
& .artifacts/contribution-tools/Scripts/python.exe -m pip install -r scripts/contribution-requirements.txt
& .artifacts/contribution-tools/Scripts/python.exe scripts/check_contribution.py plan --base origin/main
```

The remaining commands use `python` to mean the interpreter in this environment. They run
from the repository root. `plan` prints selected commands without executing them. The runner
does not silently install/upgrade tools or modify source to make validation pass.

## Start a task

For a feature, prepare the design, give it to the human, then record their actual approval
reference. Create its implementation plan after approval. An improvement can omit `--plan`.
For a bug within an existing contract use `--kind bug`; no design is required by default.

```sh
python scripts/check_contribution.py init --task example --kind feature --design docs/designs/example.md --plan docs/plans/example.md --files Sources/Protocols/API/AgentAPIModels.swift
python scripts/check_contribution.py approve-design --task example --source "Reference to the human's explicit design approval"
python scripts/check_contribution.py documentation --task example --articles docs/guides/example.md --navigation docs/.vitepress/config.ts
python scripts/check_contribution.py scope --task example --files Tests/ProtocolsTests/ExampleTests.swift
```

Only declare the files owned by this task. `scope` expands ownership as files are added.
Pre-existing unrelated work is preserved. Public features/improvements ship a useful guide;
an internal improvement may declare `documentation --internal-only-reason "..."` instead.
Designs, ADRs and plans do not count as user articles.

For multi-stage work, give each stage a concrete deliverable, acceptance criteria, owned scope,
required checks and exclusions. Close each stage with its evidence; the migration remains open
until all required stages pass. Fix regressions and unmet approved requirements within scope.
Record pre-existing adjacent issues separately unless they prevent the agreed result.

## Record behavioral tests

Work in focused Red/Green slices; related cases of one behavior may share a cycle. Refactor and
rerun only after an actual refactoring change. Store the exact test argv as JSON, for example
in ignored `.artifacts/contribution/test-command.json`:

```json
["swift", "test", "--filter", "ExampleTests.expectedBehavior"]
```

```sh
python scripts/check_contribution.py tdd --task example --phase red --command-file .artifacts/contribution/test-command.json --test-files Tests/ProtocolsTests/ExampleTests.swift --expected "Expectation failed" --reason "Describe the missing observable behavior"
python scripts/check_contribution.py tdd --task example --phase green --command-file .artifacts/contribution/test-command.json --test-files Tests/ProtocolsTests/ExampleTests.swift
python scripts/check_contribution.py tdd --task example --phase refactor --command-file .artifacts/contribution/test-command.json --test-files Tests/ProtocolsTests/ExampleTests.swift
python scripts/check_contribution.py tdd-history --task example
```

Red must execute a real test and fail with the expected behavioral assertion. Missing tools,
syntax/import/build failures and empty suites do not qualify. Green uses the same command
and unchanged tests. For work without applicable TDD, use `explain-tdd --task example
--reason "..."`; the independent reviewer examines the explanation. A final green run
does not prove that Red happened before implementation.

Use `--cycle behavior-id --behavior "Observable behavior"` on Red to name a cycle, and `--cycle
behavior-id` on Green/Refactor to select it. Without an ID, Red creates a new cycle and the other
phases use the latest one. Original phase records, failed attempts and log hashes remain in
`tdd_cycles`; the existing `tdd` field exposes the selected cycle for older callers. Old task files
are read compatibly and acquire history when the next cycle is recorded. No manual evidence copies
are needed. Focused cycles establish behavior; owning/downstream suites run at stage boundaries,
and the full applicable profile runs before final review.

## Validate and review

```sh
python scripts/check_contribution.py run --task example --stage review
python scripts/check_contribution.py snapshot --task example
python scripts/check_contribution.py record-review --task example --file .artifacts/contribution/review.json
python scripts/check_contribution.py verify --task example --stage done
```

The separate reviewer uses the snapshot and task fingerprint in its report; the schema is
in `.agents/skills/sloppy-review/SKILL.md`. Reviews check implementation,
tests, user documentation/examples, architecture and platform limitations. Fix findings and
refresh affected evidence before requesting approval of the final state. Material design
deviations return to the human. Local records do not authenticate reviewer/human identities.

The first review collects findings as a batch. Blocking findings identify a violated requirement,
scenario, consequence and evidence; missing evidence for a critical invariant is identified separately.
Optional coverage and unrelated existing issues are recommendations. Re-review fixes and affected
interactions; repeat the full audit for architectural changes or systemic problems. Unresolved
in-scope defects and missing mandatory evidence continue to block approval.

For stateless checks, including CI, use `check --files FILE...` or `--files-from paths.json`.
Supply meaningful JSON argv recipes with `--runtime-command`, `--platform-command` and
`--dependency-command` where built-in adapters cannot establish the required result.
Missing recipes remain blocked; an echo command is not evidence of runtime or platform behavior.

| Status | Meaning |
| --- | --- |
| `passed` | Executed check passed |
| `failed` | Check found a problem |
| `blocked` | Tool, environment, adapter or execution evidence is missing |
| `not_applicable` | Explicit profile rule excludes a check, with a reason |
| `deferred` | Publication-only: unavailable locally and still required in the named CI job |

Only passed and justified inapplicable checks satisfy completion. The runner exits 0 for
success, 1 for a failed check and 2 for blocked/incomplete validation. Publication may exit 0
with mapped deferred checks, but its report cannot satisfy `verify --stage done`.

Full logs, JSON reports and local task state live under `.artifacts/contribution/`, excluded
from Git. Reports bind source/index/new-file snapshots, tools, commands and log hashes.
If inputs or logs change, rerun checks. `plan` shows exactly what each profile will run.

Each validation run assembles a report for the current full snapshot. Successful built-in checks
can print `REUSED` when their execution contract, dependency inputs, relevant tools/environment
and retained log hash still match. Native checks cover source/resource roots, local packages,
vendor dependencies and manifests. Contributor Python checks cover runner code, policy and test
fixtures. Plans and skills are not compiler inputs. New/deleted files and ignored resources within
these source roots invalidate the affected check. Generated `.build`, `.artifacts`, `node_modules`
and Python bytecode directories are excluded from general source traversal; resolved `checkouts`,
binary `artifacts` and `workspace-state.json` in the check's actual Swift scratch directory are
explicit compiler inputs. Changed resolution during a run prevents retaining its old cache key.
The Apple client manifest can select external AdaEngine/SwiftTerm trees, so client builds/tests
rerun until that dependency graph is fully described. External scratch paths also rerun. Node checks,
compiler-log adapters and unknown recipes rerun conservatively. Failures, blocked checks and quick/partial-lane
results cannot supply reusable complete evidence. The final report, inventory and independent
review must still match the final diff; a reused command retains its original log and provenance.
SwiftLint analysis requires current compiler logs; Dashboard uses existing TypeScript/Vite
and Node tests, with no claim that ESLint is configured.

## Git hooks and CI

```sh
python scripts/check_contribution.py install-hooks
```

Installation is opt-in per checkout. Existing hooks, including Git LFS, are preserved and
chained with their arguments, stdin and exit status. Shared/external hook paths need manual
integration. Hook conflicts stop installation before overwriting originals.

Pre-commit runs quick checks and rejects partial staging/unstaged tracked worktrees.
Pre-push requires the outgoing branch checked out cleanly. It checks the outgoing diff and
reuses only fresh exact-coverage reports. Node-backed checks rerun because ignored
transitive dependencies can change independently of Git. New branches use the remote merge base, falling
back to all tracked files if the base is unavailable. No reset/stash/clean is performed.

Inspect publication checks with `plan --publication --base origin/main`, or execute them
with `check --publication`. Only explicitly mapped unavailable checks may defer to real
enabled CI jobs. Local failures and missing unmapped prerequisites still block a push.

Contributor CI runs selected portable, Swift, Apple-client, native SwiftUI client, Dashboard and documentation
lanes through this same runner. A lane report is partial evidence, never a complete task
report. The aggregate `Contributor gate` must be made a required status in server branch
rules for actual merge blocking; retain the existing Windows and Dashboard happy-path required
checks for changes that need them. A local workflow file and installed hooks do not establish
that hosted CI or branch protection has been enabled.
