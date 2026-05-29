# Goal Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `/goal` as a persistent TUI goal loop with status controls and a project-task background path.

**Architecture:** Add typed protocol models for session goals, a CoreService-owned goal controller for state and continuation decisions, and TUI slash command integration. Background goals reuse existing project task worker lifecycle.

**Tech Stack:** Swift 6.2, Swift Testing, existing TUI slash command router, `CoreService+Sessions`, `AgentSessionOrchestrator`, project task lifecycle.

---

### Task 1: Command Parsing and Prompt Formatting

**Files:**
- Modify: `Sources/sloppy/TUI/SloppyTUICommands.swift`
- Modify: `Tests/sloppyTests/SloppyTUICommandsTests.swift`

- [x] Add `SloppyTUIGoalCommand` with cases `start(String)`, `status`, `pause`, `resume`, `clear`, `task(String)`, and `failure(String)`.
- [x] Test that `/goal fix tests`, `/goal status`, `/goal pause`, `/goal resume`, `/goal clear`, `/goal task fix tests`, and `/goal bg fix tests` parse correctly.
- [x] Add `SloppyTUIGoalPromptFormatter.initialPrompt(objective:)` and `.continuationPrompt(goal:)`.
- [x] Test that prompts include `[Sloppy goal]`, the objective, verification guidance, and `session.complete`.
- [x] Run `swift test --filter SloppyTUICommandsTests`.

### Task 2: Protocol Models

**Files:**
- Modify: `Sources/Protocols/APIModels.swift`
- Test: `Tests/ProtocolsTests/ProtocolCompatibilityTests.swift`

- [x] Add `AgentSessionGoalStatus`: `active`, `paused`, `waiting_input`, `completed`, `blocked`, `exhausted`, `cleared`.
- [x] Add `AgentSessionGoalRecord` with id, agentId, sessionId, objective, status, attemptCount, maxAttempts, createdAt, updatedAt, lastEvaluation.
- [x] Add `AgentSessionGoalEvaluation` with status, reason, shouldContinue, continuationPrompt.
- [x] Add request/response DTOs for start, status, pause, resume, and clear.
- [x] Add coding compatibility tests with missing optional fields.
- [x] Run `swift test --filter ProtocolCompatibilityTests`.

### Task 3: Core Goal Controller

**Files:**
- Create: `Sources/sloppy/Agent/AgentSessionGoalController.swift`
- Modify: `Sources/sloppy/CoreService+Sessions.swift`
- Test: `Tests/sloppyTests/AgentSessionGoalControllerTests.swift`

- [x] Write failing tests for start/status/pause/resume/clear state transitions.
- [x] Write failing tests for evaluator outcomes: complete via `session.complete`, waiting input, blocked after interrupted run, exhausted after max attempts, incomplete continuation.
- [x] Implement in-memory state keyed by `agentID/sessionID`.
- [x] Add CoreService methods: `startAgentSessionGoal`, `getAgentSessionGoal`, `pauseAgentSessionGoal`, `resumeAgentSessionGoal`, `clearAgentSessionGoal`.
- [x] Run `swift test --filter AgentSessionGoalControllerTests`.

### Task 4: Automatic Continuation

**Files:**
- Modify: `Sources/sloppy/CoreService+Sessions.swift`
- Modify: `Sources/sloppy/Agent/AgentSessionGoalController.swift`
- Test: `Tests/sloppyTests/AgentSessionGoalControllerTests.swift`

- [x] After a goal-started or goal-continuation turn finishes, evaluate appended events.
- [x] If evaluation says continue, post the continuation prompt as `userId: "goal_loop"` with the same mode/effort.
- [x] Guard against recursion while the session is active, pending input, paused, cleared, blocked, completed, or exhausted.
- [x] Skip memory user turn count for `goal_loop`.
- [x] Run `swift test --filter AgentSessionGoalControllerTests`.

### Task 5: TUI Integration

**Files:**
- Modify: `Sources/sloppy/TUI/SloppyTUIBackend.swift`
- Modify: `Sources/sloppy/TUI/SloppyTUIScreen.swift`
- Test: `Tests/sloppyTests/SloppyTUICommandsTests.swift`

- [x] Register `/goal` in `baseSlashCommands` and `handledSlashCommandNames`.
- [x] Add backend protocol methods for goal start/status/pause/resume/clear and local implementations.
- [x] Implement `handleGoalCommand(_:)`.
- [x] Show local cards for status, pause, resume, clear, and errors.
- [x] Start goals through CoreService so automatic continuation is owned by the backend rather than TUI timers.
- [x] Run `swift test --filter SloppyTUICommandsTests`.

### Task 6: Background Goal Path

**Files:**
- Modify: `Sources/sloppy/TUI/SloppyTUIScreen.swift`
- Modify: `Tests/sloppyTests/SloppyTUISessionListTests.swift` or create `Tests/sloppyTests/SloppyTUIGoalCommandTests.swift`

- [x] Implement `/goal task <objective>` and `/goal bg <objective>` by creating a project task with a structured description and `status: ready`.
- [x] Reuse existing background worktree/worker task lifecycle where project review settings enable it.
- [x] Show the created task id and current status in the TUI card.
- [x] Run the narrow TUI goal tests.

### Task 7: Verification

**Files:**
- No code changes.

- [x] Run `swift test --filter SloppyTUICommandsTests`.
- [x] Run `swift test --filter AgentSessionGoalControllerTests`.
- [x] Run `swift test --filter ProtocolCompatibilityTests`.
- [x] Run `swift build --target sloppyTests`.
