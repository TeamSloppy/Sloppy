import Foundation
import Testing
@testable import SloppyFeatureChat

@Suite("Chat message queue")
struct ChatMessageQueueTests {
    @Test("queued messages preserve order and attachments")
    func preservesOrderAndAttachments() throws {
        let attachment = ChatComposerAttachment(
            name: "context.txt",
            mimeType: "text/plain",
            data: Data("context".utf8)
        )
        var queue = ChatMessageQueue()

        let first = queue.enqueue(content: "first", attachments: [attachment])
        let second = queue.enqueue(content: "second", attachments: [])

        #expect(queue.dequeue() == first)
        #expect(queue.dequeue() == second)
        #expect(queue.isEmpty)
    }

    @Test("queued quotes keep their identity and send as structured annotations")
    func preservesQuotes() throws {
        let quote = ChatComposerQuote(text: "first line\r\nsecond line")
        var queue = ChatMessageQueue()

        let message = queue.enqueue(content: "My question", attachments: [], quotes: [quote])

        #expect(queue.dequeue()?.quotes == [quote])
        #expect(message.displayText == "My question")
        let sent = try #require(ChatSentAnnotations.extract(from:
            ChatComposerQuote.messageContent(message.content, quotes: message.quotes)))
        #expect(sent.annotations.map(\.selectedText) == ["first line\nsecond line"])
        #expect(sent.content == "My question")
        let annotationOnly = try #require(ChatSentAnnotations.extract(from:
            ChatComposerQuote.messageContent("", quotes: [quote])))
        #expect(annotationOnly.content.isEmpty)
        #expect(annotationOnly.annotations == sent.annotations)
    }

    @Test("queued message can be cancelled by identity")
    func cancelsByIdentity() throws {
        var queue = ChatMessageQueue()
        let first = queue.enqueue(content: "first", attachments: [])
        let second = queue.enqueue(content: "second", attachments: [])

        queue.cancel(id: first.id)

        #expect(queue.messages == [second])
    }
}
