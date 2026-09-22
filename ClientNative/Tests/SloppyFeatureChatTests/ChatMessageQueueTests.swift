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

    @Test("queued message can be cancelled by identity")
    func cancelsByIdentity() throws {
        var queue = ChatMessageQueue()
        let first = queue.enqueue(content: "first", attachments: [])
        let second = queue.enqueue(content: "second", attachments: [])

        queue.cancel(id: first.id)

        #expect(queue.messages == [second])
    }
}
