# Workflow runtime — implementation slices

- Created: 2026-10-24.
- Scope and order authorized by the user's instruction to implement the preceding Kent comparison plan, starting with false success and real agents.
- Trunk: main. Working branch for the first slice: codex/workflow-agent-execution.
- Delivery: [draft PR #60](https://github.com/TeamSloppy/Sloppy/pull/60), not merged or marked ready for review.
- Target: <=600 added + removed reviewable lines per slice; cap 1000. Documentation excluded. Earlier Dashboard and unrelated TUI changes stay outside these slices.

| # | Purpose | Size budget | Integration | Depends on | Status |
|---|---|---|---|---|---|
| 1 | Fail explicitly for unexecuted steps and run agent nodes through real, project-scoped sessions; persist their results | 600 | Self-contained correction through existing executor/session APIs; remove the unsafe success fallback | — | in-review |
| 2a | Pin the graph and persist full execution checkpoints; restore approvals idempotently | 600 | Atomic execution journal, existing SQLite history API retained | 1 | in-review |
| 2b | Resume waiting agent sessions and collect human input without losing prior outputs | 600 | Typed waiting outcome and session reconciliation; original session retained | 2a | in-review |
| 2c | Recover queued, completed and interrupted execution at startup without repeating uncertain side effects | 600 | Rehydrate history from checkpoints; safe recovery or explicit reconciliation | 2b | in-review |
| 3a | Validate transitions and template references before execution; reject ambiguous routing | 600 | Additive typed conditions; preserve valid legacy keys and drafts; validate before replacing saved graphs | 2c | implemented |
| 3b | Validate output contracts and expose structured agent results and transition controls | 600 | Optional output schema and JSON mode; legacy text mode retained | 3a | implemented |
| 3c | Choose new or shared agent sessions and persist each step's message boundary | 600 | Default remains new; shared sessions explicitly reference an earlier step in the same run | 3b | implemented |
| 4 | Execute multiple branches and wait at a join; aggregate outputs and cancellation | 600 per fan-out/join sub-slice | Validate executable topology; unsupported graphs fail until fully supported | 2, 3 | planned |
| 5 | Bind task input and execution workspace/worktree policy; recovery and status delivery | 600 per task/worktree sub-slice | Explicit execution policy using existing project machinery | 2 | planned |

## First slice

In scope: no success for a missing executor or unsupported executable block; no implicit success when no outgoing transition matches; live running step state; actual agent creation/posting via the existing runtime; structured terminal-outcome checks; persisted session IDs and assistant output; deterministic runner and service integration tests.

Out of scope: checkpoint recovery, session continuation across nodes, parallel joins, workflow-specific worktrees, and production deployment. These remain the following authorized slices.

No temporary toggle or replacement framework is introduced. The old no-op success fallback is deleted as part of slice 1, so no toggle cleanup is owed. Existing supported manual tools and human approval paths must remain covered.

## Decision log

- 2026-10-24: Recorded the user's accepted ordering. Start with one review-sized correction; reuse `ToolExecutor`, `createAgentSession`, `postAgentSessionMessage` and typed `executionOutcome`, without a second agent runtime or interpretation of model prose.

## Slice 1 verification

- Reviewable code: 585 lines including tests; the earlier canvas redesign is excluded from this slice.
- `swift test --skip-build --filter '[Ww]orkflow'`: 33 tests passed on the final compiled Swift implementation, including persisted-session integration, input/output handoff, live running state, provider errors, unsupported blocks and concurrent start identities.
- Dashboard tests extracted from the exact staged PR files: 22 passed. Current working-tree Dashboard tests: 26 passed, including the earlier canvas tests. Dashboard typecheck and production build passed.
- Full `swift test --parallel`: recorded 35 issues across 21 test functions, then stalled and was interrupted. No clean full-suite result is claimed. A serial rerun of the workflow tests plus three failing-area tests passed all workflow tests and the WebSocket test; two Visor tests still failed with five issues. Their baseline status has not been established.
- macOS release builds passed: `swift build -c release --product sloppy` and `swift build -c release --product SloppyNode`. GitHub CI was still running at handoff.

Slice 1 boundaries at delivery: agent steps used fresh sessions; input/approval waits were preserved in the linked session and stopped the workflow with an explicit non-success result. Parent continuation and background scheduling are implemented by the following state/resume stage.

## State/resume stage

- 2026-10-24: The user explicitly requested approval, user-answer and server-restart continuation. Split the approved state phase into 2a/2b/2c to keep each change reviewable; all three remain the current task. PR 60 remains draft and is the stack base, with no implicit merge authorization.
- Slice 2a: 539 reviewable lines. All 36 workflow tests passed, including a SQLite-backed CoreService recreation after the live definition was modified/deleted, original input and upstream output preservation, idempotent approval, persistence failure and loop-attempt budget continuity.

- Slice 2a is [draft PR 61](https://github.com/TeamSloppy/Sloppy/pull/61), stacked on PR 60.
- Slice 2b: all 38 workflow tests passed, including a real `planning.request_input` tool call followed by an answer or cancellation in the original session. Manual Human Input requires a response and passes it downstream. Dashboard typecheck and an isolated browser fixture verified the response field, disabled empty Continue, and exact comment payload.
- Slice 2b is [draft PR 62](https://github.com/TeamSloppy/Sloppy/pull/62), stacked on PR 61.
- 2026-10-25, slice 2c: startup rebuilds the query index from atomic checkpoints and restores the pinned cursor. Completed steps are skipped; interrupted agent steps continue in the original session. Uncertain external effects remain blocked for reconciliation. Shutdown fences subsequent writes from the old executor.
- Dashboard requests background execution and polls active/waiting runs. Decisions are persisted before returning a background receipt. Existing API clients retain synchronous behavior. Polling retries transient failures while the server restarts.
- Final Swift validation: 94 tests in seven workflow/session/heartbeat/input suites passed. Recovery covers answers and cancellations saved before restart or submitted afterward, including the gap before the next model request. A moved cursor does not reuse a previous visit to the same node after a loop. Earlier race coverage also passed three additional runs.
- Slice 2c contains 568 reviewable code/test lines. Exact PR Dashboard sources passed typecheck, production build and all 22 tests; the working-tree canvas version passed 26 tests as well.
- Final macOS release builds passed for both `sloppy` and `SloppyNode` after the cursor and persisted-answer fixes. Production services were not restarted or deployed.
- The browser fixture verified the response UI and background queued-to-completed refresh after a simulated fetch failure. Backend proof comes from SQLite-backed service recreation and the actual native session pipeline with a local model fixture; the production Sloppy server was not restarted.
- Recovery assumes a single Core owner per workspace. Automatic replay of an external operation whose result was not durably recorded is intentionally blocked; operator reconciliation remains required. Full-suite coverage is limited as recorded under slice 1.
- 2026-10-25: The user explicitly authorized publishing the final commits and creating the draft PR for slice 2c.
- Slice 2c is [draft PR 63](https://github.com/TeamSloppy/Sloppy/pull/63), stacked on PR 62.

## Output and session stage

- 2026-10-25: The user requested the next approved stage: output/transition validation and new/shared sessions. The existing per-output/context slice budget is refined into 3a/3b/3c without expanding scope. Existing PRs remain drafts; no merge or production deployment is implied.
- Optional contracts and explicit session policies deliver complete behavior within each slice. No temporary toggle, replacement runtime or cleanup debt is introduced. Parallel branches and automatic compaction remain outside this stage.
- Slice 3a: 53 workflow tests passed, including typed equality without coercion, ambiguous/default routing, unresolved references before tool execution, preserved saved definitions on invalid updates, resume attempt identity and legacy wire compatibility. Dashboard typecheck passed. Input fixtures now supply the input their prompts actually require.
- Slice 3b: 66 workflow/input tests passed, including strict JSON, typed required/enum/array contracts, no downstream execution after invalid output, user-input continuation, preserved execution metadata and typed condition parsing through `project.workflow`. Dashboard typecheck/build passed. Browser fixture verified schema/format payloads, blocked invalid JSON saves, and a boolean transition value retained as boolean.
- Reviewable lines: 335 in slice 3a, 382 in slice 3b. The exact staged Dashboard for 3b passed typecheck, production build and 22 tests independently of the earlier canvas redesign.
- Slice 3c: 72 focused workflow/input tests passed. Shared-step tests cover separate answers in one session, isolation between runs, project scope rejection, input waits with JSON output, restart before posting a bound request, missing history boundaries and skipped sources. Browser fixture preserved the shared source, selected agent and output contract in the save payload.
- Final selected validation: 113 tests in ten workflow/session/input/heartbeat suites passed. Exact staged Dashboard sources for 3c passed typecheck, production build and 22 tests. Slice 3c contains 336 reviewable lines.
- Full `swift test --parallel --skip-build` recorded 62 issues across 18 test files and was stopped at the explicit 180-second limit. All seven workflow suites passed within that run. No clean full-suite result or baseline classification is claimed for the other failures (tools/bridge/terminal/Visor/session/memory/runtime/HTTP/TUI tests).
- Final macOS release builds passed for both `sloppy` and `SloppyNode` with all three slices. The production service was not restarted or deployed.
- 2026-10-25: The user explicitly authorized creating all three stage-3 draft PRs in TeamSloppy/Sloppy. The three implementation branches are pushed.
