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

    @Test("queued quotes keep their identity and send as Markdown blockquotes")
    func preservesQuotes() {
        let quote = ChatComposerQuote(text: "first line\r\nsecond line")
        var queue = ChatMessageQueue()

        let message = queue.enqueue(content: "My question", attachments: [], quotes: [quote])

        #expect(queue.dequeue()?.quotes == [quote])
        #expect(message.displayText == "My question")
        #expect(
            ChatComposerQuote.messageContent(message.content, quotes: message.quotes)
                == "> first line\n> second line\n\nMy question"
        )
        #expect(ChatComposerQuote.messageContent("", quotes: [quote]) == "> first line\n> second line")
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
