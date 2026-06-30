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
