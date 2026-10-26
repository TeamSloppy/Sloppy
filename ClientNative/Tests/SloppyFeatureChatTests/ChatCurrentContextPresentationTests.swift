import Foundation
import SloppyClientCore
import Testing
@testable import SloppyFeatureChat

@Suite("Current context presentation")
@MainActor
struct ChatCurrentContextPresentationTests {
    @Test func aggregate220335CannotBecomeNativeContextOccupancy() throws {
        let api = SloppyAPIClient(baseURL: try #require(URL(string: "http://context.invalid")))
        let model = ChatScreenViewModel(
            apiClient: api, cacheStore: ClientCacheStore(path: ":memory:"),
            settings: ClientSettings(), connectionMonitor: ConnectionMonitor(baseURL: api.baseURL),
            restoresLastSession: false, responseNotificationScheduler: ContextTestNotifications(), onOpenSettings: { _ in }
        )
        defer { model.closeSession() }
        #expect(model.contextUsage == nil)
        model.contextTokenUsage = .init(prompt: 220_000, completion: 335)
        #expect(model.contextTokenUsage?.total == 220_335)
        #expect(model.contextUsage == nil)
        // A smaller turn and a zero turn are still not an authoritative context signal.
        model.contextTokenUsage = .init(prompt: 43_556, completion: 0)
        #expect(model.contextUsage == nil)
        model.contextTokenUsage = .init(prompt: 0, completion: 0)
        #expect(model.contextUsage == nil)
    }

    @Test func explicitlyKnownContextKeepsItsOwnPercentage() {
        let known = ChatContextUsage(usedTokens: 43_556, limitTokens: 272_000)
        #expect(known.percentage == 16)
        #expect(known.usedTokens == 43_556)
        #expect(known.fraction < 0.17)
    }

    @Test func unknownComposerUsesQuestionMarkRatherThanZeroProgress() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Sources/SloppyFeatureChat/Screens/Chat/Views/ChatComposerOptionsMenu.swift"
        ), encoding: .utf8)
        #expect(source.contains("Image(systemName: \"questionmark.circle\")"))
        #expect(source.contains("Current context unknown"))
        #expect(source.contains("Turn (aggregate):"))
        #expect(!source.contains("usage?.fraction ?? 0"))
    }
}

@MainActor
private final class ContextTestNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}
