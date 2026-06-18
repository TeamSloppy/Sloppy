import Foundation
import Testing
@testable import ChannelPluginTelegram
import PluginSDK
import Protocols

@Test
func telegramForwardBatcherBuffersForwardedMessagesUntilUserMessageArrives() throws {
    var batcher = TelegramForwardBatcher()

    let forwardedOne = try decodeMessage(#"""
    {
      "message_id": 10,
      "from": {"id": 100, "first_name": "Sender"},
      "chat": {"id": 200, "type": "private"},
      "date": 1700000000,
      "text": "first forwarded",
      "forward_origin": {
        "type": "user",
        "date": 1699999999,
        "sender_user": {"id": 300, "first_name": "Alice", "username": "alice"}
      }
    }
    """#)
    let forwardedTwo = try decodeMessage(#"""
    {
      "message_id": 11,
      "from": {"id": 100, "first_name": "Sender"},
      "chat": {"id": 200, "type": "private"},
      "date": 1700000001,
      "text": "second forwarded",
      "forward_origin": {
        "type": "user",
        "date": 1699999998,
        "sender_user": {"id": 301, "first_name": "Bob", "username": "bob"}
      }
    }
    """#)
    let userMessage = try decodeMessage(#"""
    {
      "message_id": 12,
      "from": {"id": 100, "first_name": "Sender"},
      "chat": {"id": 200, "type": "private"},
      "date": 1700000002,
      "text": "my own note"
    }
    """#)

    let firstAction = batcher.consume(
        channelId: "general",
        userId: "tg:100",
        topicId: nil,
        message: forwardedOne,
        processedText: TelegramForwardedMessage.contentForModel(text: "first forwarded", message: forwardedOne),
        inboundContext: inboundContext("first forwarded"),
        attachments: [attachment(id: "fwd-1")]
    )
    let secondAction = batcher.consume(
        channelId: "general",
        userId: "tg:100",
        topicId: nil,
        message: forwardedTwo,
        processedText: TelegramForwardedMessage.contentForModel(text: "second forwarded", message: forwardedTwo),
        inboundContext: inboundContext("second forwarded"),
        attachments: [attachment(id: "fwd-2")]
    )
    let finalAction = batcher.consume(
        channelId: "general",
        userId: "tg:100",
        topicId: nil,
        message: userMessage,
        processedText: "my own note",
        inboundContext: inboundContext("my own note"),
        attachments: [attachment(id: "user-1")]
    )

    guard case .buffered = firstAction else {
        Issue.record("Expected first forwarded message to be buffered.")
        return
    }
    guard case .buffered = secondAction else {
        Issue.record("Expected second forwarded message to be buffered.")
        return
    }
    guard case .dispatch(let batch) = finalAction else {
        Issue.record("Expected final action to dispatch a combined payload.")
        return
    }

    #expect(batch.content.contains("Forwarded messages:"))
    #expect(batch.content.contains("1. Forwarded message from @alice:\nfirst forwarded"))
    #expect(batch.content.contains("2. Forwarded message from @bob:\nsecond forwarded"))
    #expect(batch.content.hasSuffix("User message:\nmy own note"))
    #expect(batch.attachments.map(\.id) == ["fwd-1", "fwd-2", "user-1"])
}

@Test
func telegramForwardBatcherScopesPendingMessagesByUserAndTopic() throws {
    var batcher = TelegramForwardBatcher()

    let forwarded = try decodeMessage(#"""
    {
      "message_id": 20,
      "from": {"id": 100, "first_name": "Sender"},
      "chat": {"id": 200, "type": "private"},
      "date": 1700000000,
      "text": "forwarded",
      "forward_origin": {
        "type": "user",
        "date": 1699999999,
        "sender_user": {"id": 300, "first_name": "Alice", "username": "alice"}
      }
    }
    """#)
    let otherUserMessage = try decodeMessage(#"""
    {
      "message_id": 21,
      "from": {"id": 101, "first_name": "Another"},
      "chat": {"id": 200, "type": "private"},
      "date": 1700000001,
      "text": "plain"
    }
    """#)
    let originalUserMessage = try decodeMessage(#"""
    {
      "message_id": 22,
      "from": {"id": 100, "first_name": "Sender"},
      "chat": {"id": 200, "type": "private"},
      "date": 1700000002,
      "text": "follow-up"
    }
    """#)

    _ = batcher.consume(
        channelId: "general",
        userId: "tg:100",
        topicId: "42",
        message: forwarded,
        processedText: TelegramForwardedMessage.contentForModel(text: "forwarded", message: forwarded),
        inboundContext: inboundContext("forwarded"),
        attachments: []
    )

    let otherUserAction = batcher.consume(
        channelId: "general",
        userId: "tg:101",
        topicId: "42",
        message: otherUserMessage,
        processedText: "plain",
        inboundContext: inboundContext("plain"),
        attachments: []
    )
    let originalUserAction = batcher.consume(
        channelId: "general",
        userId: "tg:100",
        topicId: "42",
        message: originalUserMessage,
        processedText: "follow-up",
        inboundContext: inboundContext("follow-up"),
        attachments: []
    )

    guard case .dispatch(let otherBatch) = otherUserAction else {
        Issue.record("Expected other user's message to dispatch immediately.")
        return
    }
    #expect(otherBatch.content == "plain")
    #expect(otherBatch.attachments.isEmpty)
    guard case .dispatch(let batch) = originalUserAction else {
        Issue.record("Expected original user message to flush the pending forwarded batch.")
        return
    }
    #expect(batch.content.contains("Forwarded messages:"))
    #expect(batch.content.hasSuffix("User message:\nfollow-up"))
}

@Test
func telegramForwardBatcherBuffersAttachmentOnlyMessagesAndCanFlushWithoutUserText() throws {
    var batcher = TelegramForwardBatcher()

    let voiceMessage = try decodeMessage(#"""
    {
      "message_id": 30,
      "from": {"id": 100, "first_name": "Sender"},
      "chat": {"id": 200, "type": "private"},
      "date": 1700000000
    }
    """#)
    let fileMessage = try decodeMessage(#"""
    {
      "message_id": 31,
      "from": {"id": 100, "first_name": "Sender"},
      "chat": {"id": 200, "type": "private"},
      "date": 1700000001
    }
    """#)

    let firstAction = batcher.consume(
        channelId: "general",
        userId: "tg:100",
        topicId: nil,
        message: voiceMessage,
        processedText: "Voice message attached: voice.oga\n\nVoice message transcript:\nhello",
        inboundContext: inboundContext("[Attachment]"),
        attachments: [attachment(id: "voice-1", type: .voice, filename: "voice.oga")]
    )
    let secondAction = batcher.consume(
        channelId: "general",
        userId: "tg:100",
        topicId: nil,
        message: fileMessage,
        processedText: "Document attached: spec.pdf",
        inboundContext: inboundContext("[Attachment]"),
        attachments: [attachment(id: "file-1", type: .document, filename: "spec.pdf")]
    )

    guard case .buffered(let key) = secondAction else {
        Issue.record("Expected attachment-only messages to be buffered.")
        return
    }
    guard case .buffered = firstAction else {
        Issue.record("Expected first attachment-only message to be buffered.")
        return
    }
    let flushedBatch = batcher.flush(key: key)
    let flushed = try #require(flushedBatch)
    #expect(flushed.content.contains("Attachments and media:"))
    #expect(flushed.content.contains("1. Voice message attached: voice.oga"))
    #expect(flushed.content.contains("2. Document attached: spec.pdf"))
    #expect(flushed.attachments.map(\.id) == ["voice-1", "file-1"])
}

private func decodeMessage(_ json: String) throws -> TelegramBotAPI.Message {
    try JSONDecoder().decode(TelegramBotAPI.Message.self, from: Data(json.utf8))
}

private func inboundContext(_ text: String) -> ChannelInboundContext {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return ChannelInboundContext(
        mentionsThisBot: trimmed.contains("@sloppy"),
        isReplyToThisBot: false
    )
}

private func attachment(id: String, type: ChannelAttachmentType = .document, filename: String? = nil) -> ChannelAttachment {
    ChannelAttachment(
        id: id,
        type: type,
        mimeType: "text/plain",
        filename: filename ?? "\(id).txt",
        sizeBytes: 1,
        platformMetadata: [:]
    )
}
