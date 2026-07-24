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

    @Test("adjacent system activity uses compact transcript spacing")
    func adjacentSystemActivityUsesCompactSpacing() {
        let thinking = ChatTranscriptEntry.systemGroup([
            ChatMessage(id: "thinking", role: .system, segments: [
                .init(kind: .thinking, title: "Thinking")
            ])
        ])
        let progress = ChatTranscriptEntry.message(
            ChatMessage(id: "progress", role: .system, segments: [
                .init(kind: .buildProgress)
            ])
        )
        let assistant = ChatTranscriptEntry.message(
            ChatMessage(id: "assistant", role: .assistant, segments: [
                .init(kind: .text, text: "Done")
            ])
        )

        #expect(ChatTranscriptGrouping.usesCompactSpacing(between: thinking, and: progress))
        #expect(!ChatTranscriptGrouping.usesCompactSpacing(between: progress, and: assistant))
    }

    @Test("collapsed system activity shows only currently executing tools")
    func collapsedSystemActivityShowsOnlyCurrentTools() {
        let message = ChatMessage(id: "system", role: .system, segments: [])
        let items = [
            ChatSystemSegmentItem(
                id: "first-call",
                message: message,
                segment: .init(kind: .toolCall, title: "runtime.exec", status: "started")
            ),
            ChatSystemSegmentItem(
                id: "first-result",
                message: message,
                segment: .init(kind: .toolResult, title: "runtime.exec", status: "done")
            ),
            ChatSystemSegmentItem(
                id: "current-call",
                message: message,
                segment: .init(kind: .toolCall, title: "runtime.exec", status: "started")
            ),
            ChatSystemSegmentItem(
                id: "running-thinking",
                message: message,
                segment: .init(kind: .thinking, title: "Thinking", status: "running")
            ),
        ]

        let collapsed = ChatSystemActivityVisibility.visibleItems(from: items, isExpanded: false)
        let expanded = ChatSystemActivityVisibility.visibleItems(from: items, isExpanded: true)

        #expect(collapsed.map(\.id) == ["current-call"])
        #expect(expanded.map(\.id) == items.map(\.id))
    }
}
