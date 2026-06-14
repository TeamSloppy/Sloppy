import Foundation

struct TelegramForwardedMessage: Equatable {
    let attribution: String?
    let date: Int?

    var header: String {
        if let attribution, !attribution.isEmpty {
            return "Forwarded message from \(attribution):"
        }
        return "Forwarded message:"
    }

    static func from(_ message: TelegramBotAPI.Message) -> TelegramForwardedMessage? {
        if let origin = message.forwardOrigin {
            return TelegramForwardedMessage(
                attribution: origin.attribution,
                date: origin.date
            )
        }

        if message.forwardFrom != nil || message.forwardSenderName != nil || message.forwardFromChat != nil || message.forwardDate != nil {
            let attribution = message.forwardFrom?.displayName
                ?? message.forwardSenderName
                ?? message.forwardFromChat?.displayName
                ?? message.forwardSignature
            return TelegramForwardedMessage(
                attribution: attribution,
                date: message.forwardDate
            )
        }

        return nil
    }

    static func contentForModel(text: String, message: TelegramBotAPI.Message) -> String {
        guard let forwarded = from(message) else {
            return text
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return forwarded.header
        }
        return "\(forwarded.header)\n\(trimmed)"
    }
}

extension TelegramBotAPI.Chat {
    var displayName: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        return String(id)
    }
}
