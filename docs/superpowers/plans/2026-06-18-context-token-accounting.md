# Context Token Accounting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build accurate context-window accounting, last-turn token economics, compaction pressure based on effective occupancy, and a guarded lean bootstrap path that reduces real uncached input tokens.

**Architecture:** Add a `ContextLedger` value in `AgentRuntime` and keep the runtime as the source of truth for channel context estimates. Feed ledger snapshots into CoreService/TUI `/context`, then move compaction pressure to ledger occupancy. Lean bootstrap is added last behind explicit configuration so behavior can be validated before becoming default.

**Tech Stack:** Swift 6.2, SwiftPM, Swift Testing, `AgentRuntime`, `Protocols`, `Sources/sloppy` CoreService/TUI.

## Global Constraints

- Use Swift Testing macros (`@Test`, `#expect`).
- Do not implement language heuristics for agent behavior.
- Prefer typed signals, runtime events, tool call records, structured model output, or persisted metadata.
- Keep API behavior backward-compatible unless explicitly adding optional fields.
- Run the smallest relevant verification first, then CI-parity commands when touching shared behavior.
- Preserve existing dirty worktree changes outside the files in this plan.

---

## File Structure

- Create `Sources/AgentRuntime/ContextLedger.swift`: focused runtime types for context categories, estimates, provider usage overlay, and compaction pressure.
- Modify `Sources/AgentRuntime/RuntimeSystem.swift`: store latest ledger snapshot per channel.
- Modify `Sources/AgentRuntime/RuntimeSystem+Operations.swift`: expose `contextLedgerSnapshot(channelId:)`.
- Modify `Sources/AgentRuntime/RuntimeSystem+ModelResponse.swift`: build a ledger snapshot before each model call and update it when provider usage is captured.
- Modify `Sources/AgentRuntime/ChannelRuntime.swift`: use ledger occupancy for `contextUtilization` when present.
- Modify `Sources/AgentRuntime/TokenPressureEstimator.swift`: accept ledger occupancy as the preferred source.
- Modify `Tests/AgentRuntimeTests/RuntimeFlowTests.swift`: add focused ledger and pressure tests near existing token/compactor tests.
- Modify `Sources/sloppy/CoreService+Debug.swift`: include ledger data in session context debug response.
- Modify `Sources/sloppy/TUI/SloppyTUIBackend.swift`: add a local/remote method for session context accounting.
- Modify `Sources/sloppy/TUI/SloppyTUIModels.swift`: add TUI summary models for occupancy categories and last-turn economics.
- Modify `Sources/sloppy/TUI/SloppyTUIScreen+Features.swift`: populate `/context` from the ledger snapshot with fallback to existing token usage.
- Modify `Sources/sloppy/TUI/SloppyTUITheme.swift`: render context occupancy and last-turn economics separately.
- Modify `Tests/sloppyTests/SloppyTUIThemeTests.swift`: cover the new display.
- Modify `Sources/sloppy/CoreConfig.swift`: add a guarded lean-bootstrap setting.
- Modify `Sources/sloppy/Agent/AgentPromptComposer.swift`: add lean bootstrap rendering.
- Modify `Sources/sloppy/Agent/AgentSessionOrchestrator.swift`: select full or lean bootstrap by config/agent setting and keep recovery semantics.
- Modify `Tests/sloppyTests/AgentSessionOrchestratorTests.swift`: cover lean bootstrap manifest and full bootstrap fallback.

---

### Task 1: Add Context Ledger Runtime Types

**Files:**
- Create: `Sources/AgentRuntime/ContextLedger.swift`
- Test: `Tests/AgentRuntimeTests/RuntimeFlowTests.swift`

**Interfaces:**
- Produces: `ContextLedgerCategory`, `ContextLedgerEntry`, `ContextLedgerSnapshot`, `ContextLedgerBuilder`, `ContextLedgerSnapshot.withProviderUsage(_:)`, `ContextPressureSource.contextLedger`.
- Consumes: `Protocols.TokenUsage` and `TokenPressureEstimator.estimateTextTokens(_:)`.

- [ ] **Step 1: Write failing tests for ledger totals**

Add near the existing token pressure tests in `Tests/AgentRuntimeTests/RuntimeFlowTests.swift`:

```swift
@Test
func contextLedgerSeparatesOccupancyFromLastTurnEconomics() {
    let snapshot = ContextLedgerSnapshot(
        channelId: "ledger-channel",
        contextWindowTokens: 10_000,
        reservedOutputTokens: 1_000,
        entries: [
            ContextLedgerEntry(category: .bootstrapStatic, label: "AGENTS.md", estimatedTokens: 2_000, cachePolicy: .cacheable),
            ContextLedgerEntry(category: .toolsSchema, label: "native tools", estimatedTokens: 1_500, cachePolicy: .cacheable),
            ContextLedgerEntry(category: .currentTurn, label: "user", estimatedTokens: 100, cachePolicy: .uncacheable),
        ],
        lastTurnUsage: TokenUsage(prompt: 3_700, completion: 80, cachedInputTokens: 3_000, cacheCreationInputTokens: 400, reasoningTokens: 12)
    )

    #expect(snapshot.contextWindowUsedTokens == 3_600)
    #expect(snapshot.contextWindowFreeTokens == 5_400)
    #expect(snapshot.lastTurnInputTokens == 3_700)
    #expect(snapshot.lastTurnCachedInputTokens == 3_000)
    #expect(snapshot.lastTurnUncachedInputTokens == 700)
    #expect(snapshot.lastTurnCacheCreationInputTokens == 400)
    #expect(snapshot.lastTurnCompletionTokens == 80)
    #expect(snapshot.lastTurnReasoningTokens == 12)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter contextLedgerSeparatesOccupancyFromLastTurnEconomics
```

Expected: FAIL because `ContextLedgerSnapshot` and related types do not exist.

- [ ] **Step 3: Implement ledger types**

Create `Sources/AgentRuntime/ContextLedger.swift`:

```swift
import Foundation
import Protocols

public enum ContextLedgerCategory: String, Codable, Sendable, Equatable, CaseIterable {
    case systemInstructions = "system_instructions"
    case bootstrapStatic = "bootstrap_static"
    case toolsSchema = "tools_schema"
    case sessionTranscript = "session_transcript"
    case currentTurn = "current_turn"
    case attachments
    case memory
    case planner
    case toolResults = "tool_results"
    case reservedOutput = "reserved_output"
}

public enum ContextLedgerCachePolicy: String, Codable, Sendable, Equatable {
    case unknown
    case uncacheable
    case cacheable
    case cached
}

public struct ContextLedgerEntry: Codable, Sendable, Equatable {
    public var category: ContextLedgerCategory
    public var label: String
    public var estimatedTokens: Int
    public var cachePolicy: ContextLedgerCachePolicy

    public init(
        category: ContextLedgerCategory,
        label: String,
        estimatedTokens: Int,
        cachePolicy: ContextLedgerCachePolicy = .unknown
    ) {
        self.category = category
        self.label = label
        self.estimatedTokens = max(0, estimatedTokens)
        self.cachePolicy = cachePolicy
    }
}

public struct ContextLedgerSnapshot: Codable, Sendable, Equatable {
    public var channelId: String
    public var contextWindowTokens: Int
    public var reservedOutputTokens: Int
    public var entries: [ContextLedgerEntry]
    public var lastTurnUsage: TokenUsage?

    public init(
        channelId: String,
        contextWindowTokens: Int,
        reservedOutputTokens: Int,
        entries: [ContextLedgerEntry],
        lastTurnUsage: TokenUsage? = nil
    ) {
        self.channelId = channelId
        self.contextWindowTokens = max(1, contextWindowTokens)
        self.reservedOutputTokens = max(0, reservedOutputTokens)
        self.entries = entries
        self.lastTurnUsage = lastTurnUsage
    }

    public var contextWindowUsedTokens: Int {
        entries.reduce(0) { $0 + $1.estimatedTokens }
    }

    public var contextWindowFreeTokens: Int {
        max(0, contextWindowTokens - reservedOutputTokens - contextWindowUsedTokens)
    }

    public var utilization: Double {
        min(1.0, Double(contextWindowUsedTokens + reservedOutputTokens) / Double(contextWindowTokens))
    }

    public var lastTurnInputTokens: Int { lastTurnUsage?.prompt ?? 0 }
    public var lastTurnCachedInputTokens: Int { lastTurnUsage?.cachedInput ?? 0 }
    public var lastTurnCacheCreationInputTokens: Int { lastTurnUsage?.cacheCreationInput ?? 0 }
    public var lastTurnCompletionTokens: Int { lastTurnUsage?.completion ?? 0 }
    public var lastTurnReasoningTokens: Int { lastTurnUsage?.reasoning ?? 0 }

    public var lastTurnUncachedInputTokens: Int {
        max(0, lastTurnInputTokens - lastTurnCachedInputTokens)
    }

    public func withProviderUsage(_ usage: TokenUsage) -> ContextLedgerSnapshot {
        var copy = self
        copy.lastTurnUsage = usage
        return copy
    }
}

public struct ContextLedgerBuilder: Sendable {
    private let estimator: TokenPressureEstimator

    public init(estimator: TokenPressureEstimator) {
        self.estimator = estimator
    }

    public func estimateTextTokens(_ text: String) -> Int {
        estimator.estimateTextTokens(text)
    }
}
```

Update `Sources/AgentRuntime/TokenPressureEstimator.swift`:

```swift
public enum ContextPressureSource: String, Codable, Sendable, Equatable {
    case contextLedger = "context_ledger"
    case realUsage = "real_usage"
    case roughRequest = "rough_request"
    case roughMessages = "rough_messages"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
swift test --filter contextLedgerSeparatesOccupancyFromLastTurnEconomics
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentRuntime/ContextLedger.swift Sources/AgentRuntime/TokenPressureEstimator.swift Tests/AgentRuntimeTests/RuntimeFlowTests.swift
git commit -m "Add context ledger runtime types"
```

---

### Task 2: Record Ledger Snapshots Around Model Calls

**Files:**
- Modify: `Sources/AgentRuntime/RuntimeSystem.swift`
- Modify: `Sources/AgentRuntime/RuntimeSystem+Operations.swift`
- Modify: `Sources/AgentRuntime/RuntimeSystem+ModelResponse.swift`
- Modify: `Sources/AgentRuntime/RuntimeSystem+ModelSupport.swift`
- Test: `Tests/AgentRuntimeTests/RuntimeFlowTests.swift`

**Interfaces:**
- Consumes: `ContextLedgerSnapshot` from Task 1.
- Produces: `RuntimeSystem.contextLedgerSnapshot(channelId:) async -> ContextLedgerSnapshot?`.

- [ ] **Step 1: Write failing test for runtime snapshot capture**

Add to `Tests/AgentRuntimeTests/RuntimeFlowTests.swift`:

```swift
@Test
func runtimeRecordsContextLedgerForNativeModelCall() async throws {
    let provider = PromptCapturingModelProvider()
    let system = RuntimeSystem(
        modelProvider: provider,
        defaultModel: "prompt-capturing",
        compactorConfiguration: CompactorConfiguration(contextWindowTokens: 8_000)
    )
    await system.setChannelBootstrap(channelId: "ledger-runtime", content: "Stable bootstrap instructions.")

    _ = try await system.respond(
        channelId: "ledger-runtime",
        userId: "user",
        prompt: "Hello",
        options: RuntimeMessageOptions(model: "prompt-capturing")
    )

    let snapshot = try #require(await system.contextLedgerSnapshot(channelId: "ledger-runtime"))
    #expect(snapshot.channelId == "ledger-runtime")
    #expect(snapshot.entries.contains { $0.category == .bootstrapStatic })
    #expect(snapshot.entries.contains { $0.category == .currentTurn })
    #expect(snapshot.contextWindowTokens == 8_000)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter runtimeRecordsContextLedgerForNativeModelCall
```

Expected: FAIL because `contextLedgerSnapshot(channelId:)` does not exist.

- [ ] **Step 3: Store snapshots in `RuntimeSystem`**

In `Sources/AgentRuntime/RuntimeSystem.swift`, add next to `bootstrapByChannel`:

```swift
/// Latest context accounting snapshot per channel. This is diagnostic and
/// compaction input; it does not store full prompt text.
var contextLedgerByChannel: [String: ContextLedgerSnapshot] = [:]
```

In `updateModelProvider(...)`, after `channelToolAllowList.removeAll()` add:

```swift
contextLedgerByChannel.removeAll()
```

- [ ] **Step 4: Expose snapshot accessor**

In `Sources/AgentRuntime/RuntimeSystem+Operations.swift`, add near `channelBootstrapContent`:

```swift
func contextLedgerSnapshot(channelId: String) async -> ContextLedgerSnapshot? {
    contextLedgerByChannel[channelId]
}
```

- [ ] **Step 5: Add a helper that estimates the next model call**

In `Sources/AgentRuntime/RuntimeSystem+ModelSupport.swift`, add:

```swift
func makeContextLedgerSnapshot(
    channelId: String,
    userMessage: String,
    modelProvider: any ModelProvider,
    includeTools: Bool,
    maxOutputTokens: Int
) -> ContextLedgerSnapshot {
    let estimator = TokenPressureEstimator(contextWindowTokens: channels.contextWindowTokens)
    var entries: [ContextLedgerEntry] = []

    if let systemInstructions = modelProvider.systemInstructions?.trimmingCharacters(in: .whitespacesAndNewlines),
       !systemInstructions.isEmpty {
        entries.append(ContextLedgerEntry(
            category: .systemInstructions,
            label: "provider system instructions",
            estimatedTokens: estimator.estimateTextTokens(systemInstructions),
            cachePolicy: .cacheable
        ))
    }

    if let bootstrap = bootstrapByChannel[channelId]?.trimmingCharacters(in: .whitespacesAndNewlines),
       !bootstrap.isEmpty {
        entries.append(ContextLedgerEntry(
            category: .bootstrapStatic,
            label: "channel bootstrap",
            estimatedTokens: estimator.estimateTextTokens(bootstrap),
            cachePolicy: .cacheable
        ))
    }

    let tools = sanitizedModelTools(channelId: channelId, modelProvider: modelProvider, includeTools: includeTools)
    let toolSchemaTokens = tools.reduce(0) { partial, tool in
        partial + estimator.estimateTextTokens(tool.name) + estimator.estimateTextTokens(tool.description)
    }
    if toolSchemaTokens > 0 {
        entries.append(ContextLedgerEntry(
            category: .toolsSchema,
            label: "native tool schemas",
            estimatedTokens: toolSchemaTokens,
            cachePolicy: .cacheable
        ))
    }

    entries.append(ContextLedgerEntry(
        category: .currentTurn,
        label: "current user message",
        estimatedTokens: estimator.estimateTextTokens(userMessage),
        cachePolicy: .uncacheable
    ))

    return ContextLedgerSnapshot(
        channelId: channelId,
        contextWindowTokens: channels.contextWindowTokens,
        reservedOutputTokens: max(0, maxOutputTokens),
        entries: entries
    )
}
```

If `channels.contextWindowTokens` is not accessible, add this public/internal accessor to `ChannelRuntime` in Task 3 before using it:

```swift
public nonisolated var configuredContextWindowTokens: Int { pressureEstimator.contextWindowTokens }
```

and call `channels.configuredContextWindowTokens`.

- [ ] **Step 6: Record snapshot before model streaming**

In `Sources/AgentRuntime/RuntimeSystem+ModelResponse.swift`, immediately after `let options = modelProvider.generationOptions(...)` in the native response path, add:

```swift
let ledger = makeContextLedgerSnapshot(
    channelId: channelId,
    userMessage: modelUserMessage,
    modelProvider: modelProvider,
    includeTools: toolInvoker != nil,
    maxOutputTokens: 1024
)
contextLedgerByChannel[channelId] = ledger
```

When provider usage is captured, replace:

```swift
await channels.recordTokenUsage(channelId: channelId, usage: tokenUsage)
```

with:

```swift
if let existingLedger = contextLedgerByChannel[channelId] {
    contextLedgerByChannel[channelId] = existingLedger.withProviderUsage(tokenUsage)
}
await channels.recordTokenUsage(channelId: channelId, usage: tokenUsage)
```

- [ ] **Step 7: Run test to verify it passes**

Run:

```bash
swift test --filter runtimeRecordsContextLedgerForNativeModelCall
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/AgentRuntime/RuntimeSystem.swift Sources/AgentRuntime/RuntimeSystem+Operations.swift Sources/AgentRuntime/RuntimeSystem+ModelSupport.swift Sources/AgentRuntime/RuntimeSystem+ModelResponse.swift Tests/AgentRuntimeTests/RuntimeFlowTests.swift
git commit -m "Record context ledger snapshots"
```

---

### Task 3: Use Ledger Occupancy for Context Pressure and Compaction

**Files:**
- Modify: `Sources/AgentRuntime/ChannelRuntime.swift`
- Modify: `Sources/AgentRuntime/TokenPressureEstimator.swift`
- Modify: `Sources/AgentRuntime/RuntimeSystem+Messaging.swift`
- Modify: `Sources/AgentRuntime/RuntimeSystem+ModelResponse.swift`
- Test: `Tests/AgentRuntimeTests/RuntimeFlowTests.swift`

**Interfaces:**
- Consumes: `ContextLedgerSnapshot.utilization`.
- Produces: `TokenPressureEstimator.estimate(messages:latestPromptUsage:ledgerSnapshot:)`.

- [ ] **Step 1: Write failing test for pressure source**

Add to `Tests/AgentRuntimeTests/RuntimeFlowTests.swift`:

```swift
@Test
func tokenPressurePrefersLedgerOccupancyOverLastPromptUsage() {
    let estimator = TokenPressureEstimator(contextWindowTokens: 10_000)
    let ledger = ContextLedgerSnapshot(
        channelId: "pressure-ledger",
        contextWindowTokens: 10_000,
        reservedOutputTokens: 1_000,
        entries: [
            ContextLedgerEntry(category: .bootstrapStatic, label: "bootstrap", estimatedTokens: 2_000),
            ContextLedgerEntry(category: .currentTurn, label: "turn", estimatedTokens: 500),
        ],
        lastTurnUsage: TokenUsage(prompt: 9_500, completion: 100, cachedInputTokens: 8_000)
    )

    let pressure = estimator.estimate(messages: [], latestPromptUsage: ledger.lastTurnUsage, ledgerSnapshot: ledger)
    #expect(pressure.source == .contextLedger)
    #expect(pressure.tokens == 3_500)
    #expect(pressure.utilization == 0.35)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter tokenPressurePrefersLedgerOccupancyOverLastPromptUsage
```

Expected: FAIL because the overload does not exist.

- [ ] **Step 3: Update estimator**

In `Sources/AgentRuntime/TokenPressureEstimator.swift`, change `estimate` signature and first branch:

```swift
public func estimate(
    messages: [ChannelMessageEntry],
    latestPromptUsage: TokenUsage? = nil,
    ledgerSnapshot: ContextLedgerSnapshot? = nil
) -> ContextPressureEstimate {
    if let ledgerSnapshot {
        return pressure(
            tokens: ledgerSnapshot.contextWindowUsedTokens + ledgerSnapshot.reservedOutputTokens,
            source: .contextLedger
        )
    }

    if let latestPromptUsage, latestPromptUsage.prompt > 0 {
        return pressure(tokens: latestPromptUsage.prompt, source: .realUsage)
    }

    let tokens = messages.reduce(0) { total, message in
        total + estimate(message: message)
    }
    return pressure(tokens: tokens, source: .roughMessages)
}
```

- [ ] **Step 4: Thread ledger into channel pressure**

In `Sources/AgentRuntime/ChannelRuntime.swift`, add a field to channel state:

```swift
var latestContextLedger: ContextLedgerSnapshot?
```

Add a method:

```swift
public func recordContextLedger(channelId: String, snapshot: ContextLedgerSnapshot) {
    var state = ensureChannel(channelId: channelId)
    state.latestContextLedger = snapshot
    state.contextUtilization = pressureEstimator.estimate(
        messages: state.messages,
        latestPromptUsage: state.latestPromptUsage,
        ledgerSnapshot: snapshot
    ).utilization
    channels[channelId] = state
}
```

Update existing context estimation calls in `ChannelRuntime` to pass `state.latestContextLedger`.

- [ ] **Step 5: Record ledger into ChannelRuntime when runtime creates it**

In `Sources/AgentRuntime/RuntimeSystem+ModelResponse.swift`, after assigning `contextLedgerByChannel[channelId] = ledger`, add:

```swift
await channels.recordContextLedger(channelId: channelId, snapshot: ledger)
```

After provider usage updates the ledger, add:

```swift
if let updatedLedger = contextLedgerByChannel[channelId] {
    await channels.recordContextLedger(channelId: channelId, snapshot: updatedLedger)
}
```

- [ ] **Step 6: Run pressure and compactor tests**

Run:

```bash
swift test --filter tokenPressurePrefersLedgerOccupancyOverLastPromptUsage
swift test --filter compactorThresholdsProduceEvents
```

Expected: both PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentRuntime/ChannelRuntime.swift Sources/AgentRuntime/TokenPressureEstimator.swift Sources/AgentRuntime/RuntimeSystem+ModelResponse.swift Tests/AgentRuntimeTests/RuntimeFlowTests.swift
git commit -m "Use context ledger for pressure estimates"
```

---

### Task 4: Expose Ledger Data to `/context`

**Files:**
- Modify: `Sources/sloppy/CoreService+Debug.swift`
- Modify: `Sources/sloppy/TUI/SloppyTUIBackend.swift`
- Modify: `Sources/sloppy/TUI/SloppyTUIModels.swift`
- Modify: `Sources/sloppy/TUI/SloppyTUIScreen+Features.swift`
- Modify: `Sources/sloppy/TUI/SloppyTUITheme.swift`
- Test: `Tests/sloppyTests/SloppyTUIThemeTests.swift`

**Interfaces:**
- Consumes: `RuntimeSystem.contextLedgerSnapshot(channelId:)`.
- Produces: `SloppyTUIContextUsageSummary.ledgerCategories` and last-turn fields.

- [ ] **Step 1: Write failing TUI rendering test**

Add to `Tests/sloppyTests/SloppyTUIThemeTests.swift`:

```swift
@Test
func contextUsageMarkdownSeparatesWindowAndLastTurnEconomics() {
    let summary = SloppyTUIContextUsageSummary(
        modelTitle: "GPT Test",
        modelID: "openai-oauth:gpt-test",
        contextWindowLabel: "10K",
        promptTokens: 3_700,
        completionTokens: 80,
        totalTokens: 3_780,
        contextWindowTokens: 10_000,
        pendingContextAttached: false,
        pendingUploadCount: 0,
        ledgerCategories: [
            .init(label: "Bootstrap", tokens: 2_000),
            .init(label: "Tools", tokens: 1_500),
            .init(label: "Current turn", tokens: 100),
        ],
        lastTurnInputTokens: 3_700,
        lastTurnCachedInputTokens: 3_000,
        lastTurnUncachedInputTokens: 700,
        lastTurnCacheCreationInputTokens: 400,
        lastTurnCompletionTokens: 80,
        lastTurnReasoningTokens: 12
    )

    let markdown = SloppyTUITheme.contextUsageMarkdown(summary)
    #expect(markdown.contains("Context window"))
    #expect(markdown.contains("Last turn"))
    #expect(markdown.contains("Cached input"))
    #expect(markdown.contains("Uncached input"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter contextUsageMarkdownSeparatesWindowAndLastTurnEconomics
```

Expected: FAIL because the new initializer fields do not exist.

- [ ] **Step 3: Add TUI models**

In `Sources/sloppy/TUI/SloppyTUIModels.swift`, add:

```swift
struct SloppyTUIContextCategorySummary: Equatable {
    var label: String
    var tokens: Int
}
```

Extend `SloppyTUIContextUsageSummary` with defaulted fields:

```swift
var ledgerCategories: [SloppyTUIContextCategorySummary] = []
var lastTurnInputTokens: Int = 0
var lastTurnCachedInputTokens: Int = 0
var lastTurnUncachedInputTokens: Int = 0
var lastTurnCacheCreationInputTokens: Int = 0
var lastTurnCompletionTokens: Int = 0
var lastTurnReasoningTokens: Int = 0
```

- [ ] **Step 4: Add backend method**

In `Sources/sloppy/TUI/SloppyTUIBackend.swift`, add to `SloppyTUIBackend`:

```swift
func contextLedgerSnapshot(channelId: String) async -> ContextLedgerSnapshot?
```

Add `import AgentRuntime` at the top of the file.

In `LocalSloppyTUIBackend`:

```swift
func contextLedgerSnapshot(channelId: String) async -> ContextLedgerSnapshot? {
    await service.runtime.contextLedgerSnapshot(channelId: channelId)
}
```

In the remote backend implementation, return `nil` first:

```swift
func contextLedgerSnapshot(channelId: String) async -> ContextLedgerSnapshot? {
    nil
}
```

- [ ] **Step 5: Populate `/context` summary from ledger**

In `Sources/sloppy/TUI/SloppyTUIScreen+Features.swift`, inside `showContextUsage()`, fetch:

```swift
let ledger = await service.contextLedgerSnapshot(channelId: currentSessionChannelID())
let ledgerCategories = ledger?.entries.map {
    SloppyTUIContextCategorySummary(label: $0.category.rawValue, tokens: $0.estimatedTokens)
} ?? []
let effectiveTotalTokens = ledger?.contextWindowUsedTokens ?? usage.totalPromptTokens
```

Pass the new fields to `SloppyTUIContextUsageSummary`:

```swift
promptTokens: effectiveTotalTokens,
completionTokens: usage.totalCompletionTokens,
totalTokens: effectiveTotalTokens + usage.totalCompletionTokens,
...
ledgerCategories: ledgerCategories,
lastTurnInputTokens: ledger?.lastTurnInputTokens ?? 0,
lastTurnCachedInputTokens: ledger?.lastTurnCachedInputTokens ?? 0,
lastTurnUncachedInputTokens: ledger?.lastTurnUncachedInputTokens ?? 0,
lastTurnCacheCreationInputTokens: ledger?.lastTurnCacheCreationInputTokens ?? 0,
lastTurnCompletionTokens: ledger?.lastTurnCompletionTokens ?? 0,
lastTurnReasoningTokens: ledger?.lastTurnReasoningTokens ?? 0
```

- [ ] **Step 6: Render the two sections**

In `Sources/sloppy/TUI/SloppyTUITheme.swift`, update `contextUsageMarkdown(_:)` so the text block includes:

```swift
let categoryLines = summary.ledgerCategories.isEmpty
    ? "\(muted("No context ledger yet; using token usage fallback."))"
    : summary.ledgerCategories.map { item in
        "\(muted("-")) \(foreground(item.label)): \(foreground(formatTokenCountShort(item.tokens) + " tokens"))"
    }.joined(separator: "\n")

let lastTurnLines = [
    "\(muted("-")) Input: \(foreground(formatTokenCountShort(summary.lastTurnInputTokens) + " tokens"))",
    "\(muted("-")) Cached input: \(foreground(formatTokenCountShort(summary.lastTurnCachedInputTokens) + " tokens"))",
    "\(muted("-")) Uncached input: \(foreground(formatTokenCountShort(summary.lastTurnUncachedInputTokens) + " tokens"))",
    "\(muted("-")) Cache creation: \(foreground(formatTokenCountShort(summary.lastTurnCacheCreationInputTokens) + " tokens"))",
    "\(muted("-")) Output: \(foreground(formatTokenCountShort(summary.lastTurnCompletionTokens) + " tokens"))",
    "\(muted("-")) Reasoning: \(foreground(formatTokenCountShort(summary.lastTurnReasoningTokens) + " tokens"))",
].joined(separator: "\n")
```

Insert these under headings `Context window` and `Last turn`.

- [ ] **Step 7: Run TUI test**

Run:

```bash
swift test --filter contextUsageMarkdownSeparatesWindowAndLastTurnEconomics
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/sloppy/TUI/SloppyTUIBackend.swift Sources/sloppy/TUI/SloppyTUIModels.swift Sources/sloppy/TUI/SloppyTUIScreen+Features.swift Sources/sloppy/TUI/SloppyTUITheme.swift Tests/sloppyTests/SloppyTUIThemeTests.swift
git commit -m "Show context ledger in TUI context view"
```

---

### Task 5: Add Lean Bootstrap Policy Behind Configuration

**Files:**
- Modify: `Sources/sloppy/CoreConfig.swift`
- Modify: `Sources/sloppy/Agent/AgentPromptComposer.swift`
- Modify: `Sources/sloppy/Agent/AgentSessionOrchestrator.swift`
- Test: `Tests/sloppyTests/AgentSessionOrchestratorTests.swift`

**Interfaces:**
- Produces: `CoreConfig.AgentRuntimeContext.bootstrapMode`, `AgentPromptComposer.composeLeanAgentSessionBootstrap(context:)`.
- Consumes: existing `AgentDocumentBundle`, `InstalledSkill`, and `PromptRenderContext`.

- [ ] **Step 1: Write failing test for lean bootstrap manifest**

Add to `Tests/sloppyTests/AgentSessionOrchestratorTests.swift` near existing bootstrap tests:

```swift
@Test
func agentSessionLeanBootstrapUsesManifestInsteadOfLargeDocuments() async throws {
    let agentID = "lean-bootstrap-agent"
    let largeAgents = String(repeating: "Large AGENTS body.\n", count: 500)
    let (catalogStore, sessionStore, agentsRootURL) = try makeAgentSessionFixture(
        agentID: agentID,
        documents: AgentDocumentBundle(
            userMarkdown: "User preferences",
            agentsMarkdown: largeAgents,
            soulMarkdown: "Soul",
            identityMarkdown: "Identity"
        )
    )
    let provider = SessionCapturingModelProvider(models: ["mock:default"])
    let runtime = RuntimeSystem(modelProvider: provider, defaultModel: "mock:default")
    var config = CoreConfig.default
    config.agentRuntimeContext.bootstrapMode = .lean
    let orchestrator = AgentSessionOrchestrator(
        runtime: runtime,
        sessionStore: sessionStore,
        agentCatalogStore: catalogStore,
        agentSkillsStore: AgentSkillsFileStore(agentsRootURL: agentsRootURL),
        availableModels: [ProviderModelOption(id: "mock:default", title: "Mock")],
        persistedModelContext: (config, false)
    )

    let session = try await orchestrator.createSession(agentID: agentID, request: AgentSessionCreateRequest())
    let channelID = "agent:\(agentID):session:\(session.id)"
    let bootstrap = try #require(await runtime.channelBootstrapContent(channelId: channelID))

    #expect(bootstrap.contains("[Agent context manifest]"))
    #expect(bootstrap.contains("AGENTS.md"))
    #expect(!bootstrap.contains(String(repeating: "Large AGENTS body.\n", count: 20)))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter agentSessionLeanBootstrapUsesManifestInsteadOfLargeDocuments
```

Expected: FAIL because `agentRuntimeContext.bootstrapMode` does not exist.

- [ ] **Step 3: Add config**

In `Sources/sloppy/CoreConfig.swift`, add:

```swift
public struct AgentRuntimeContextConfig: Codable, Sendable, Equatable {
    public enum BootstrapMode: String, Codable, Sendable, Equatable {
        case full
        case lean
    }

    public var bootstrapMode: BootstrapMode
    public var leanInlineTokenLimit: Int

    public init(bootstrapMode: BootstrapMode = .full, leanInlineTokenLimit: Int = 512) {
        self.bootstrapMode = bootstrapMode
        self.leanInlineTokenLimit = max(0, leanInlineTokenLimit)
    }
}
```

Add `public var agentRuntimeContext: AgentRuntimeContextConfig` to `CoreConfig`, initialize it in `.default`, and include it in coding keys with decode fallback:

```swift
agentRuntimeContext = try container.decodeIfPresent(AgentRuntimeContextConfig.self, forKey: .agentRuntimeContext) ?? .init()
```

- [ ] **Step 4: Add lean composer method**

In `Sources/sloppy/Agent/AgentPromptComposer.swift`, add:

```swift
func composeLeanAgentSessionBootstrap(context: PromptRenderContext, inlineTokenLimit: Int) throws -> Prompt {
    guard let sessionID = context.sessionID,
          let bootstrapMarker = context.bootstrapMarker,
          let documents = context.documents
    else {
        throw ComposerError.unsupportedProcess
    }
    let estimator = TokenPressureEstimator()
    func documentLine(_ name: String, _ content: String) -> String {
        let tokens = estimator.estimateTextTokens(content)
        if tokens <= inlineTokenLimit {
            return "- \(name): inline below\n\n[\(name)]\n\(content)"
        }
        return "- \(name): available in agent directory; load it with `files.read` when relevant (\(tokens) estimated tokens)."
    }
    let skillsEntries = buildSkillsEntries(skills: context.installedSkills)
    return Prompt {
        bootstrapMarker
        "Session context initialized."
        "Agent: \(context.agentID)"
        "Current session ID: \(sessionID)"
        ""
        "[Agent context manifest]"
        documentLine("AGENTS.md", documents.agentsMarkdown)
        documentLine("USER.md", documents.userMarkdown)
        documentLine("IDENTITY.md", documents.identityMarkdown)
        documentLine("SOUL.md", documents.soulMarkdown)
        if !context.installedSkills.isEmpty {
            ""
            "[Skills manifest]"
            skillsEntries
        }
        ""
        try templateLoader.loadPartial(named: "session_capabilities")
        ""
        try templateLoader.loadPartial(named: "tools_instruction")
    }
}
```

- [ ] **Step 5: Select lean composer in orchestrator**

In `Sources/sloppy/Agent/AgentSessionOrchestrator.swift`, before composing `bootstrapPrompt`, compute:

```swift
let runtimeContext = persistedModelContext.config.agentRuntimeContext
```

Replace the composer call with:

```swift
if runtimeContext.bootstrapMode == .lean {
    bootstrapPrompt = try promptComposer.composeLeanAgentSessionBootstrap(
        context: .agentSessionBootstrap(
            agentID: agentID,
            sessionID: sessionID,
            bootstrapMarker: Self.sessionContextBootstrapMarker,
            documents: documents,
            installedSkills: installedSkills,
            agentDirectoryPath: agentDirectoryPath
        ),
        inlineTokenLimit: runtimeContext.leanInlineTokenLimit
    )
} else {
    bootstrapPrompt = try promptComposer.compose(
        context: .agentSessionBootstrap(
            agentID: agentID,
            sessionID: sessionID,
            bootstrapMarker: Self.sessionContextBootstrapMarker,
            documents: documents,
            installedSkills: installedSkills,
            agentDirectoryPath: agentDirectoryPath
        )
    )
}
```

- [ ] **Step 6: Run lean bootstrap test**

Run:

```bash
swift test --filter agentSessionLeanBootstrapUsesManifestInsteadOfLargeDocuments
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/sloppy/CoreConfig.swift Sources/sloppy/Agent/AgentPromptComposer.swift Sources/sloppy/Agent/AgentSessionOrchestrator.swift Tests/sloppyTests/AgentSessionOrchestratorTests.swift
git commit -m "Add lean agent session bootstrap mode"
```

---

### Task 6: Verify End-to-End Accounting

**Files:**
- Modify only files needed to fix failures discovered by verification.

**Interfaces:**
- Consumes all tasks above.
- Produces a green narrow suite and a documented remaining-risk note if broad CI is not run.

- [ ] **Step 1: Run focused runtime tests**

Run:

```bash
swift test --filter RuntimeFlowTests
```

Expected: PASS.

- [ ] **Step 2: Run focused sloppy tests**

Run:

```bash
swift test --filter AgentSessionOrchestratorTests
swift test --filter SloppyTUIThemeTests
```

Expected: PASS.

- [ ] **Step 3: Build the main product**

Run:

```bash
swift build -c release --product sloppy
```

Expected: PASS.

- [ ] **Step 4: Inspect `/context` manually in TUI**

Run:

```bash
swift run sloppy
```

Open an agent session, send one small message, then run `/context`.

Expected:

- The context window section shows category rows.
- The last-turn section shows input, cached, uncached, cache creation, output, and reasoning.
- If no provider cache details exist, cached/cache creation fields are zero and the ledger categories still explain occupancy.

- [ ] **Step 5: Commit verification fixes**

If any fixes were required:

```bash
git add <fixed-files>
git commit -m "Stabilize context accounting verification"
```

If no fixes were required, do not create an empty commit.

---

## Self-Review

- Spec coverage: ledger categories, separate metrics, compaction occupancy, `/context` display, provider cache reporting, and lean bootstrap are each covered by a task.
- Placeholder scan: no placeholder markers or unspecified implementation steps remain.
- Type consistency: `ContextLedgerSnapshot`, `ContextLedgerEntry`, `ContextLedgerCategory`, `ContextLedgerCachePolicy`, and `contextLedgerSnapshot(channelId:)` are introduced before later tasks consume them.
