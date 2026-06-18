import Foundation
import PluginSDK
import Protocols

struct TelegramForwardBatcher {
    struct Key: Hashable {
        let channelId: String
        let userId: String
        let topicId: String?
    }

    struct DispatchedBatch: Equatable {
        let key: Key
        let content: String
        let attachments: [ChannelAttachment]
        let inboundContext: ChannelInboundContext?
    }

    private enum EntryKind {
        case forwarded
        case attachmentOnly
    }

    private struct PendingEntry {
        let kind: EntryKind
        let content: String
    }

    private struct PendingBatch {
        var entries: [PendingEntry] = []
        var attachments: [ChannelAttachment] = []
        var inboundContext: ChannelInboundContext?
    }

    enum Action: Equatable {
        case buffered(key: Key)
        case dispatch(DispatchedBatch)
    }

    private var pending: [Key: PendingBatch] = [:]

    mutating func consume(
        channelId: String,
        userId: String,
        topicId: String?,
        message: TelegramBotAPI.Message,
        processedText: String,
        inboundContext: ChannelInboundContext?,
        attachments: [ChannelAttachment]
    ) -> Action {
        let key = Key(channelId: channelId, userId: userId, topicId: topicId)

        if let kind = entryKind(message: message, attachments: attachments) {
            var batch = pending[key] ?? PendingBatch()
            batch.entries.append(PendingEntry(kind: kind, content: processedText))
            batch.attachments.append(contentsOf: attachments)
            batch.inboundContext = inboundContext ?? batch.inboundContext
            pending[key] = batch
            return .buffered(key: key)
        }

        guard let batch = pending.removeValue(forKey: key), !batch.entries.isEmpty else {
            return .dispatch(
                DispatchedBatch(
                    key: key,
                    content: processedText,
                    attachments: attachments,
                    inboundContext: inboundContext
                )
            )
        }

        return .dispatch(
            DispatchedBatch(
                key: key,
                content: combinedContent(entries: batch.entries, userMessage: processedText),
                attachments: batch.attachments + attachments,
                inboundContext: inboundContext ?? batch.inboundContext
            )
        )
    }

    mutating func flush(key: Key) -> DispatchedBatch? {
        guard let batch = pending.removeValue(forKey: key), !batch.entries.isEmpty else {
            return nil
        }
        return DispatchedBatch(
            key: key,
            content: combinedContent(entries: batch.entries, userMessage: nil),
            attachments: batch.attachments,
            inboundContext: batch.inboundContext
        )
    }

    private func entryKind(message: TelegramBotAPI.Message, attachments: [ChannelAttachment]) -> EntryKind? {
        if TelegramForwardedMessage.from(message) != nil {
            return .forwarded
        }

        let hasVisibleText = [message.text, message.caption]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { !$0.isEmpty }
        if !hasVisibleText, !attachments.isEmpty {
            return .attachmentOnly
        }

        return nil
    }

    private func combinedContent(entries: [PendingEntry], userMessage: String?) -> String {
        let header: String
        if entries.allSatisfy({ $0.kind == .forwarded }) {
            header = "Forwarded messages:"
        } else if entries.allSatisfy({ $0.kind == .attachmentOnly }) {
            header = "Attachments and media:"
        } else {
            header = "Batched messages:"
        }

        let body = entries.enumerated().map { index, entry in
            "\(index + 1). \(entry.content)"
        }.joined(separator: "\n\n")

        guard let userMessage,
              !userMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return """
            \(header)
            \(body)
            """
        }

        return """
        \(header)
        \(body)

        User message:
        \(userMessage)
        """
    }
}
