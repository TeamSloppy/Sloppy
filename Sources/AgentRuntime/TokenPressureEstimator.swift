import Foundation
import Protocols

public enum ContextPressureSource: String, Codable, Sendable, Equatable {
    case contextLedger = "context_ledger"
    case realUsage = "real_usage"
    case roughRequest = "rough_request"
    case roughMessages = "rough_messages"
}

public struct ContextPressureEstimate: Sendable, Equatable {
    public var tokens: Int
    public var utilization: Double
    public var source: ContextPressureSource

    public init(tokens: Int, utilization: Double, source: ContextPressureSource) {
        self.tokens = max(0, tokens)
        self.utilization = min(max(utilization, 0.0), 1.0)
        self.source = source
    }
}

public struct TokenPressureEstimator: Sendable, Equatable {
    public var contextWindowTokens: Int
    public var mediaPlaceholderTokens: Int
    public var metadataOverheadTokens: Int
    public var jsonStructuralOverheadTokens: Int

    public init(
        contextWindowTokens: Int = 32_000,
        mediaPlaceholderTokens: Int = 768,
        metadataOverheadTokens: Int = 24,
        jsonStructuralOverheadTokens: Int = 16
    ) {
        self.contextWindowTokens = max(1, contextWindowTokens)
        self.mediaPlaceholderTokens = max(1, mediaPlaceholderTokens)
        self.metadataOverheadTokens = max(0, metadataOverheadTokens)
        self.jsonStructuralOverheadTokens = max(0, jsonStructuralOverheadTokens)
    }

    public func estimate(
        messages: [ChannelMessageEntry],
        latestPromptUsage: TokenUsage? = nil
    ) -> ContextPressureEstimate {
        if let latestPromptUsage, latestPromptUsage.prompt > 0 {
            return pressure(tokens: latestPromptUsage.prompt, source: .realUsage)
        }

        let tokens = messages.reduce(0) { total, message in
            total + estimate(message: message)
        }
        return pressure(tokens: tokens, source: .roughMessages)
    }

    public func estimate(request: ChannelMessageRequest) -> ContextPressureEstimate {
        let entry = ChannelMessageEntry(
            userId: request.userId,
            content: request.content,
            attachments: request.attachments
        )
        return pressure(tokens: estimate(message: entry), source: .roughRequest)
    }

    public func estimate(message: ChannelMessageEntry) -> Int {
        var tokens = estimateTextTokens(message.content) + metadataOverheadTokens
        for attachment in message.attachments {
            tokens += estimate(attachment: attachment)
        }
        return max(1, tokens)
    }

    public func estimateTextTokens(_ text: String) -> Int {
        if text.isEmpty { return 0 }
        return max(1, Int((Double(text.count) / 4.0).rounded(.up)))
    }

    public func estimate(attachment: ChannelAttachment) -> Int {
        var tokens = metadataOverheadTokens + jsonStructuralOverheadTokens
        tokens += estimateTextTokens(attachment.id)
        tokens += estimateTextTokens(attachment.mimeType ?? "")
        tokens += estimateTextTokens(attachment.filename ?? "")
        tokens += estimateTextTokens(attachment.url ?? "")
        tokens += estimateTextTokens(attachment.localPath ?? "")
        tokens += estimateTextTokens(
            attachment.platformMetadata
                .sorted { $0.key < $1.key }
                .map { key, value in
                    if Self.isLargeEncodedPayloadKey(key) {
                        return "\(key)=<payload omitted; \(value.count) chars>"
                    }
                    return "\(key)=\(value)"
                }
                .joined(separator: "\n")
        )

        switch attachment.type {
        case .image, .audio, .voice, .video:
            tokens += mediaPlaceholderTokens
        case .document, .file, .unknown:
            tokens += min(max((attachment.sizeBytes ?? 0) / 128, 0), mediaPlaceholderTokens)
        }

        return max(1, tokens)
    }

    private static func isLargeEncodedPayloadKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        return normalized.contains("base64")
            || normalized.contains("datauri")
            || normalized == "data"
            || normalized == "payload"
    }

    private func pressure(tokens: Int, source: ContextPressureSource) -> ContextPressureEstimate {
        ContextPressureEstimate(
            tokens: tokens,
            utilization: Double(max(0, tokens)) / Double(contextWindowTokens),
            source: source
        )
    }
}
