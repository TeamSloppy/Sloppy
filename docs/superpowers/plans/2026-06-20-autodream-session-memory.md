# Autodream Session Memory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a periodic autodream runner that reviews recent agent sessions into memory and records processed sessions in SQLite.

**Architecture:** Add `CoreConfig.Visor.Autodream`, persistence records for reviewed sessions, an `AutodreamRunner`, and `CoreService` orchestration that reuses existing memory checkpoints. The runner stays separate from self-improvement proposal curation.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftPM, SQLite via `CSQLite3`.

## Global Constraints

- Preserve existing memory checkpoint tool allowlist and prompt constraints.
- Track processed sessions in the database, not a standalone file.
- Default cadence is every 6 hours plus jitter; make it configurable under Visor.
- Use TDD: write failing tests before production code.

---

### Task 1: Config And Persistence State

**Files:**
- Modify: `Sources/sloppy/CoreConfig.swift`
- Modify: `Sources/sloppy/Stores/PersistenceStore.swift`
- Modify: `Sources/sloppy/Storage/schema.sql`
- Modify: `Sources/sloppy/CorePersistenceFactory.swift`
- Modify: `Sources/sloppy/SQLiteStore.swift`
- Test: `Tests/sloppyTests/AutodreamTests.swift`

**Interfaces:**
- Produces: `CoreConfig.Visor.Autodream`
- Produces: `AutodreamSessionReviewRecord`
- Produces: `PersistenceStore.autodreamSessionReview(agentId:sessionId:)`
- Produces: `PersistenceStore.saveAutodreamSessionReview(_:)`

- [ ] Write failing config and persistence tests.
- [ ] Run `swift test --filter AutodreamTests` and confirm failures.
- [ ] Add config type, schema, SQLite methods, and fallback map.
- [ ] Run `swift test --filter AutodreamTests` and confirm pass.

### Task 2: Candidate Selection And Runner

**Files:**
- Create: `Sources/sloppy/AutodreamRunner.swift`
- Modify: `Sources/sloppy/CoreService.swift`
- Modify: `Sources/sloppy/CoreService+MemoryCheckpoint.swift`
- Modify: `Sources/sloppy/CoreService+GatewayPlugins.swift`
- Test: `Tests/sloppyTests/AutodreamTests.swift`

**Interfaces:**
- Produces: `AutodreamRunnerConfig`
- Produces: `CoreService.runAutodreamPass(reason:)`
- Consumes: `PersistenceStore.autodreamSessionReview(agentId:sessionId:)`

- [ ] Write failing tests for candidate filtering and non-overlapping runner trigger.
- [ ] Run `swift test --filter AutodreamTests` and confirm failures.
- [ ] Implement runner and service pass.
- [ ] Connect runner startup/shutdown to gateway lifecycle.
- [ ] Run `swift test --filter AutodreamTests` and confirm pass.

### Task 3: Verification

**Files:**
- No new files.

- [ ] Run `swift test --filter AutodreamTests`.
- [ ] Run `swift test --filter MemoryCheckpointSchedulingTests`.
- [ ] Run `swift build`.
