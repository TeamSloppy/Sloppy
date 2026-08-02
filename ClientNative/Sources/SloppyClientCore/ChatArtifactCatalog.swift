import Foundation

public struct ChatArtifactRecord: Identifiable, Sendable, Equatable {
    public let id: String
    public let attachmentID: String
    public let messageID: String
    public let session: ChatSessionSummary
    public let role: ChatMessageRole
    public let name: String
    public let mimeType: String
    public let sizeBytes: Int
    public let relativePath: String?
    public let createdAt: Date

    public init(
        id: String,
        attachmentID: String,
        messageID: String,
        session: ChatSessionSummary,
        role: ChatMessageRole,
        name: String,
        mimeType: String,
        sizeBytes: Int,
        relativePath: String?,
        createdAt: Date
    ) {
        self.id = id
        self.attachmentID = attachmentID
        self.messageID = messageID
        self.session = session
        self.role = role
        self.name = name
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.relativePath = relativePath
        self.createdAt = createdAt
    }
}

public enum ChatArtifactCatalog {
    public static func build(from details: [ChatSessionDetail]) -> [ChatArtifactRecord] {
        details.flatMap { detail in
            detail.messages.flatMap { message in
                message.segments.compactMap { segment in
                    guard segment.kind == .attachment, let attachment = segment.attachment else {
                        return nil
                    }
                    return ChatArtifactRecord(
                        id: "\(detail.summary.id):\(message.id):\(attachment.id)",
                        attachmentID: attachment.id,
                        messageID: message.id,
                        session: detail.summary,
                        role: message.role,
                        name: attachment.name,
                        mimeType: attachment.mimeType,
                        sizeBytes: attachment.sizeBytes,
                        relativePath: attachment.relativePath,
                        createdAt: message.createdAt
                    )
                }
            }
        }
        .sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id < rhs.id
        }
    }
}
