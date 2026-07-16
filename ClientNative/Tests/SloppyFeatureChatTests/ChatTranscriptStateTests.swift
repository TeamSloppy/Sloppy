import Foundation
import Testing
import SloppyClientCore
@testable import SloppyFeatureChat

@Suite("ChatTranscriptState")
@MainActor
struct ChatTranscriptStateTests {
    @Test("replaceAll keeps only a recent window visible for large histories")
    func replaceAllShowsRecentWindowForLargeHistory() {
        let transcript = ChatTranscriptState()
        let messages = makeMessages(count: 150)

        transcript.replaceAll(messages)

        #expect(transcript.messages.count == 64)
        #expect(transcript.messages.first?.id == "msg-86")
        #expect(transcript.messages.last?.id == "msg-149")
        #expect(transcript.hasEarlierMessages == true)
        #expect(transcript.hiddenMessageCount == 86)
    }

    @Test("append keeps the recent window and newer messages visible")
    func appendKeepsRecentWindowVisible() {
        let transcript = ChatTranscriptState()
        transcript.replaceAll(makeMessages(count: 70))

        transcript.append(message(id: "msg-70", index: 70))

        #expect(transcript.messages.count == 65)
        #expect(transcript.messages.first?.id == "msg-6")
        #expect(transcript.messages.last?.id == "msg-70")
        #expect(transcript.hasEarlierMessages == true)
    }

    @Test("revealEarlierMessages restores earlier transcript pages")
    func revealEarlierMessagesRestoresEarlierPages() {
        let transcript = ChatTranscriptState()
        transcript.replaceAll(makeMessages(count: 150))

        transcript.revealEarlierMessages()

        #expect(transcript.messages.count == 128)
        #expect(transcript.messages.first?.id == "msg-22")
        #expect(transcript.messages.last?.id == "msg-149")
        #expect(transcript.hasEarlierMessages == true)
        #expect(transcript.hiddenMessageCount == 22)
    }

    @Test("streaming assistant text accumulates across separate UI flushes")
    func streamingAssistantTextAccumulatesAcrossFlushes() {
        let transcript = ChatTranscriptState()

        transcript.appendStreamingAssistantText("Hello", messageId: "streaming-assistant-session")
        transcript.appendStreamingAssistantText(", world", messageId: "streaming-assistant-session")

        #expect(transcript.messages.count == 1)
        #expect(transcript.messages.first?.role == .assistant)
        #expect(transcript.messages.first?.textContent == "Hello, world")
    }

    @Test("history reconciliation preserves optimistic and streamed messages")
    func reconciliationPreservesLocalMessages() {
        let transcript = ChatTranscriptState()
        let optimistic = ChatMessage(
            id: "optimistic-user-1",
            role: .user,
            segments: [ChatMessageSegment(kind: .text, text: "Now")],
            createdAt: Date(timeIntervalSince1970: 2)
        )
        transcript.replaceAll([message(id: "server-1", index: 0)])
        transcript.append(optimistic)

        transcript.reconcile(with: [message(id: "server-1", index: 0, text: "Updated")])

        #expect(transcript.messages.map(\.id) == ["server-1", "optimistic-user-1"])
        #expect(transcript.messages.first?.textContent == "Updated")
    }

    @Test("final assistant atomically replaces the streaming placeholder")
    func finalAssistantReplacesStreamingPlaceholder() {
        let transcript = ChatTranscriptState()
        transcript.appendStreamingAssistantText("Draft", messageId: "streaming-assistant-session")
        let final = ChatMessage(
            id: "assistant-final",
            role: .assistant,
            segments: [ChatMessageSegment(kind: .text, text: "Final")]
        )

        transcript.replaceStreamingAssistant(
            messageId: "streaming-assistant-session",
            with: final
        )

        #expect(transcript.messages.count == 1)
        #expect(transcript.messages.first?.id == "assistant-final")
        #expect(transcript.messages.first?.textContent == "Final")
    }

    @Test("late activity is inserted before the streaming assistant")
    func lateActivityStaysBeforeStreamingAssistant() {
        let transcript = ChatTranscriptState()
        transcript.appendStreamingAssistantText("Draft", messageId: "streaming-assistant-session")
        let thinking = ChatMessage(
            id: "thinking-1",
            role: .assistant,
            segments: [ChatMessageSegment(kind: .thinking, text: "Planning")]
        )

        transcript.upsert(thinking, before: "streaming-assistant-session")

        #expect(transcript.messages.map(\.id) == ["thinking-1", "streaming-assistant-session"])
    }

    private func makeMessages(count: Int) -> [ChatMessage] {
        (0..<count).map { message(id: "msg-\($0)", index: $0) }
    }

    private func message(id: String, index: Int, text: String? = nil) -> ChatMessage {
        ChatMessage(
            id: id,
            role: index.isMultiple(of: 2) ? .user : .assistant,
            segments: [ChatMessageSegment(kind: .text, text: text ?? "message \(index)")],
            createdAt: Date(timeIntervalSince1970: TimeInterval(index))
        )
    }
}
