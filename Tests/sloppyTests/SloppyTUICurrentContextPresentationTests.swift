import AgentRuntime
import Foundation
import Protocols
import Testing
@testable import sloppy

@Suite struct SloppyTUICurrentContextPresentationTests {
    private func plain(_ value: String) -> String {
        value.replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression)
    }

    @Test func aggregate220335DoesNotBecomeContextOccupancy() {
        let summary = SloppyTUITokenUsageSummary(
            promptTokens: 220_000, completionTokens: 335, totalTokens: 220_335,
            contextWindowTokens: 272_000, costUSD: nil
        )
        #expect(summary.usagePercent == nil)
        #expect(summary.freeTokens == nil)
        let composer = plain(SloppyTUITheme.composerMetaLine(
            width: 500, mode: .auto, model: "sonnet", agent: "agent", provider: "provider",
            tokenUsage: summary, lastTurnTokenUsage: .init(prompt: 220_000, completion: 335)
        ))
        #expect(composer.contains("window 272K"))
        #expect(composer.contains("spent 220K"))
        #expect(composer.contains("turn 220K"))
        #expect(!composer.contains("ctx 220K"))
        #expect(!composer.contains("81%"))
        let progress = plain(SloppyTUITheme.contextUsageProgressLine(width: 500, summary: summary))
        #expect(progress.contains("window 272K"))
        #expect(progress.contains("spent 220.3K"))
        #expect(!progress.contains("81%"))
    }

    @Test func missingModelWindowRemainsUnknown() {
        let summary = SloppyTUITokenUsageSummary(
            promptTokens: 0, completionTokens: 0, totalTokens: 0,
            contextWindowTokens: 0, costUSD: nil
        )
        let composer = plain(SloppyTUITheme.composerMetaLine(
            width: 100, mode: .auto, model: "test", agent: "agent", provider: "provider",
            tokenUsage: summary
        ))
        #expect(composer.contains("context unknown"))
    }

    @Test @MainActor func modelWindowUsesExactCatalogMetadata() {
        let models: [ProviderModelOption] = [
            .init(id: "test:exact", title: "Exact", contextWindow: "1.0M", contextWindowTokens: 1_048_576),
            .init(id: "test:legacy", title: "Legacy", contextWindow: "128K"),
        ]
        #expect(SloppyTUIScreen.contextWindowTokens(for: "test:exact", in: models) == 1_048_576)
        #expect(SloppyTUIScreen.contextWindowTokens(for: "test:legacy", in: models) == 128_000)
        #expect(SloppyTUIScreen.contextWindowTokens(for: "test:missing", in: models) == 0)
    }

    @Test func ledgerOccupancyAndTurnSpendingStaySeparate() {
        let ledger = ContextLedgerSnapshot(
            channelId: "test", contextWindowTokens: 272_000, reservedOutputTokens: 0,
            entries: [.init(category: .sessionTranscript, label: "Transcript", estimatedTokens: 43_556)],
            lastTurnUsage: .init(prompt: 220_000, completion: 335)
        )
        let summary = SloppyTUITokenUsageSummary(
            promptTokens: 220_000, completionTokens: 335, totalTokens: 220_335,
            contextWindowTokens: ledger.contextWindowTokens, costUSD: nil,
            contextUsedTokens: ledger.contextWindowUsedTokens
        )
        #expect(summary.usagePercent == 16)
        #expect(summary.freeTokens == 228_444)
        let composer = plain(SloppyTUITheme.composerMetaLine(
            width: 500, mode: .auto, model: "sonnet", agent: "agent", provider: "provider",
            tokenUsage: summary, lastTurnTokenUsage: ledger.lastTurnUsage
        ))
        #expect(composer.contains("ctx 44K/272K"))
        #expect(composer.contains("16%"))
        #expect(composer.contains("spent 220K"))
        #expect(composer.contains("turn 220K"))
        #expect(!composer.contains("81%"))
    }

    @Test func contextCardDoesNotFallbackToSessionSpent() {
        let usage = TokenUsageResponse(items: [], totalPromptTokens: 220_000,
                                       totalCompletionTokens: 335, totalTokens: 220_335)
        let summary = SloppyTUIContextUsageSummaryBuilder.makeSummary(
            modelTitle: "Test", modelID: "test", contextWindowLabel: "272K",
            usage: usage, ledger: nil,
            pendingContextAttached: false, pendingUploadCount: 0
        )
        #expect(summary.usagePercent == nil)
        #expect(summary.totalTokens == 0)
        #expect(summary.spentTokens == 220_335)
        let card = plain(SloppyTUITheme.contextUsageMarkdown(summary))
        #expect(card.contains("current context unknown"))
        #expect(card.contains("272K context"))
        #expect(card.contains("Session spent: 220.3K tokens"))
        #expect(!card.contains("81%"))
        #expect(!card.contains("220.3K/272k"))
    }
}
