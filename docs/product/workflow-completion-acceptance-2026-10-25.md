# Workflow completion acceptance — 2026-10-25

The accepted Kent-comparison plan is implemented in `codex/workflow-parallel-controls`,
updating existing draft PR 70. The user explicitly requested finishing the remaining
work in one branch/PR instead of extending the earlier PR chain. The larger review
size is deliberate; unrelated TUI changes and Xcode preferences are excluded.

## Delivered behavior

| Capability | Evidence |
| --- | --- |
| Durable real execution and validated routing/results | Existing workflow agent/output/session/transition/recovery suites retained |
| Task snapshot and exclusive task ownership | Actual task fields remain fixed through approval/restart; ordinary pickup and competing root runs respect ownership; repaired children retain ownership |
| Project, task, existing and new worktree selection | Real disposable Git checkouts, pinned revision/provider/branch/path, cwd confinement and invalid-choice rejection |
| Setup/restart/reconciliation | Setup is recorded before execution; uncertain setup requires a decision; confirmed setup does not repeat |
| New/shared/compact sessions | Native session pipeline, distinct summary/working sessions, saved handoff phase and selected source history boundary |
| Parallel/all/first-completed Merge | Process overlap/barrier, durable branch state, joined outputs, winner selection, immediate interrupt and retired waits |
| Expression and Loop | Typed bounded parser, short circuit, arithmetic/type errors, persistent iteration cap and legacy block_kind guards |
| Project Task / Notify / child workflow | Real snapshot output, registered test gateway delivery receipt, child waits/failure/recursion/restart/deleted live definition and reuse on retry |
| Retry / verified result / cancel | Saved incoming input, retained prior effects, validated native/child completion, operator/evidence audit, cancelled questions and owned work |
| Editor | Earlier canvas redesign included; task/environment/input launch, native questions, child navigation, retry/cancel, compact/join/block controls, invalid JSON guards and readable command output |

The detailed request/response contracts and limits are in
[Workflow execution and contracts](../guides/workflow-contracts.md).

## Live server and browser acceptance

A separate `sloppy` process listened only on loopback port 25114 with a disposable
workspace and SQLite database. The real editor used its API through a local proxy;
no API responses were mocked. Native provider behavior is tested separately through
the native pipeline with a local model fixture, without external model charges.

The browser started `Durable task & worktree` from `Original acceptance task`, with
input ticket WF-42, New Worktree from HEAD, and a setup marker command. The workflow
ran setup and a preparation command, then waited for human approval. While paused,
the live task was renamed and the source repository gained a new commit. The server
was stopped and relaunched with the same configuration/database.

The same pending action remained available. Approving in the browser completed the
original run and changed the live task status to done. The command output still held
the original task title and ticket in the original worktree. The live task's new title
was retained. Git inspection confirmed the worktree stayed at its initially pinned
commit while the source HEAD had advanced. Setup and preparation markers were both
exactly `x`, with one approval attempt and one preparation attempt.

![Real completed workflow with saved task and worktree binding](/design/workflow-task-binding-2026-10-25.png)

## Verification scope

143 selected Swift tests in 22 suites passed, together with 29 Dashboard workflow tests,
Dashboard typecheck and production build. Both final macOS release products (`sloppy`,
`SloppyNode`) and their CLI help smoke checks passed. Full results are recorded in the [delivery map](../tbd/decompositions/2026-10-24-workflow-runtime.md).
The selected regression covers workflows plus session inbox, plan input and heartbeat.

The full parallel Swift suite was attempted with a 180-second limit and stopped after
65 issues across 16 other test files. Saved logs from the preceding stage already had
62 issues across the same major areas. A separate 44-test repeat of NodeMesh, desktop,
tool hooks and memory scheduling passed. This does not establish every full-suite
failure as pre-existing, and a clean full-suite result is not claimed.

The implementation retains explicit bounds: flat parallel groups of 2–16 branches,
one execution directory per run, eight workflow levels, bounded expressions,
and a durable 25-attempt per-node budget. Worktrees are retained; effects are not rolled
back automatically. Merge and production deployment are separate actions.
