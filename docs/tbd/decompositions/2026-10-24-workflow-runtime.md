# Workflow runtime — implementation slices

- Created: 2026-10-24.
- Scope and order authorized by the user's instruction to implement the preceding Kent comparison plan, starting with false success and real agents.
- Trunk: main. Working branch for the first slice: codex/workflow-agent-execution.
- Target: <=600 added + removed reviewable lines per slice; cap 1000. Documentation excluded. Earlier Dashboard and unrelated TUI changes stay outside these slices.

| # | Purpose | Size budget | Integration | Depends on | Status |
|---|---|---|---|---|---|
| 1 | Fail explicitly for unexecuted steps and run agent nodes through real, project-scoped sessions; persist their results | 600 | Self-contained correction through existing executor/session APIs; remove the unsafe success fallback | — | in-progress |
| 2 | Pin the graph version and persist/restore original input, node outputs and attempt counts across approvals | 600 | Backward-compatible optional persisted state with tests for old records | 1 | planned |
| 3 | Validate transition outputs and missing references; add independent/continued session context | 600 per context/output sub-slice | Additive contracts; existing serialized graphs migrate explicitly | 2 | planned |
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
- Release builds: pending final verification.

Current boundaries: agent steps use fresh sessions; input/approval waits are preserved in the linked agent session and stop the workflow with an explicit non-success result. Continuing the parent from such waits belongs to the checkpoint/resume slice. Start requests retain the existing synchronous API behavior; durable background scheduling is part of the next execution-state slice.
