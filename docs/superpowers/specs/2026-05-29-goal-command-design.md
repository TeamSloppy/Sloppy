# Goal Command Design

## Summary

Add a `/goal` command that turns a TUI chat into a measurable, persistent work loop. The default path keeps the work in the current session, automatically continuing after each turn until a goal evaluator decides the success condition is satisfied, the run is blocked, the user pauses it, or the safety limits are reached.

## User Experience

- `/goal <objective>` starts or replaces the active goal for the current TUI session.
- `/goal status` shows the active goal, state, attempt count, and last evaluator result.
- `/goal pause` stops automatic continuation without deleting goal state.
- `/goal resume` continues a paused goal.
- `/goal clear` removes the active goal.
- `/goal task <objective>` creates a project task and starts the existing project worker flow for background execution.
- `/goal bg <objective>` is an alias for the background task path.

The default command should feel like Claude Code: the user writes a checkable goal such as "make `swift test --filter SloppyTUICommandsTests` pass", then Sloppy keeps working and checking until the condition is true.

## Architecture

The feature has two paths:

1. Session goal loop: new protocol models describe an active session goal and evaluator result. A lightweight `AgentSessionGoalController` owns goal state in `CoreService`, posts the initial goal turn, evaluates the completed turn, and posts structured continuation messages when the goal is still incomplete.
2. Background goal task: `/goal task` and `/goal bg` reuse existing `ProjectTask` and worker lifecycle instead of creating a second background execution system.

Goal state is typed. UI command routing and continuation logic must not inspect arbitrary localized model text to decide completion. Completion comes from an explicit evaluator result, existing `session.complete` evidence, or terminal task state in the background path.

## Goal Evaluation

The first implementation uses a deterministic evaluator interface with a conservative built-in implementation:

- If the user pauses, clears, or interrupts the goal, no continuation is posted.
- If the latest turn ended with a paused input request, the goal becomes `waiting_input`.
- If the latest turn ended interrupted or hit the tool round limit, the goal becomes `blocked`.
- If `session.complete` is present with a non-empty summary, the evaluator may mark the goal complete only when the active goal prompt asked the agent to call `session.complete` after verification.
- Otherwise the goal remains incomplete and receives one continuation prompt.

The controller boundary is designed so a fast model evaluator can replace or augment the built-in evaluator later without changing TUI command behavior.

## Safety

- Default maximum continuations: 8.
- Never continue while a session run is active.
- Never continue while a tool approval or plan input is pending.
- `/stop` interrupts the active run; `/goal pause` prevents future automatic continuation.
- The status card must show when a goal stops because it is complete, blocked, paused, or exhausted.

## Testing

Add focused Swift Testing coverage for:

- `/goal` command parsing and router registration.
- Goal prompt formatting.
- Goal state transitions for start, pause, resume, clear, complete, blocked, and exhausted.
- TUI command handlers calling the new backend methods.
- Background `/goal task` using the existing task creation path.

