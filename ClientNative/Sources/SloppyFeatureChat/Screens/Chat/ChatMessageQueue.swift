import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI
import SwiftUI
import UniformTypeIdentifiers

struct ChatQueuedMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let content: String
    let attachments: [ChatComposerAttachment]
    let quotes: [ChatComposerQuote]
    let references: [ChatComposerReference]

    init(
        id: UUID = UUID(),
        content: String,
        attachments: [ChatComposerAttachment],
        quotes: [ChatComposerQuote] = [],
        references: [ChatComposerReference] = []
    ) {
        self.id = id
        self.content = content
        self.attachments = attachments
        self.quotes = quotes
        self.references = references
    }

    var displayText: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return quotes.isEmpty ? "Attachments only" : "Quoted text"
    }
}

struct ChatMessageQueue {
    private(set) var messages: [ChatQueuedMessage] = []

    var isEmpty: Bool { messages.isEmpty }

    @discardableResult
    mutating func enqueue(
        content: String,
        attachments: [ChatComposerAttachment],
        quotes: [ChatComposerQuote] = [],
        references: [ChatComposerReference] = []
    ) -> ChatQueuedMessage {
        let message = ChatQueuedMessage(content: content, attachments: attachments, quotes: quotes, references: references)
        messages.append(message)
        return message
    }

    mutating func dequeue() -> ChatQueuedMessage? {
        guard !messages.isEmpty else { return nil }
        return messages.removeFirst()
    }

    mutating func cancel(id: UUID) {
        messages.removeAll { $0.id == id }
    }
}
