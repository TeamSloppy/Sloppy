import Foundation
import Testing
import SloppyClientCore
@testable import SloppyFeatureChat

@Suite("Chat message rendering support")
struct ChatMessageRenderingSupportTests {
    @Test("compact duration formatter renders seconds and minutes")
    func compactDurationFormatterRendersDurations() {
        #expect(ChatCompactDurationFormatter.string(for: 12) == "12s")
        #expect(ChatCompactDurationFormatter.string(for: 84) == "1m 24s")
        #expect(ChatCompactDurationFormatter.string(for: 7384) == "2h 03m")
    }

    @Test("consecutive system messages are merged into transcript groups")
    func consecutiveSystemMessagesAreMerged() {
        let firstSystem = ChatMessage(id: "system-1", role: .system, segments: [
            .init(kind: .toolCall, title: "Read file")
        ])
        let secondSystem = ChatMessage(id: "system-2", role: .system, segments: [
            .init(kind: .toolResult, title: "Read result")
        ])
        let user = ChatMessage(id: "user", role: .user, segments: [
            .init(kind: .text, text: "Continue")
        ])
        let thirdSystem = ChatMessage(id: "system-3", role: .system, segments: [
            .init(kind: .status, title: "Running tests")
        ])

        let entries = ChatTranscriptGrouping.entries(from: [
            firstSystem,
            secondSystem,
            user,
            thirdSystem,
        ])

        #expect(entries == [
            .systemGroup([firstSystem, secondSystem]),
            .message(user),
            .systemGroup([thirdSystem]),
        ])
    }
}
