import Foundation

public enum AppNotificationType: String, Codable, Sendable {
    case confirmation
    case agentError = "agent_error"
    case systemError = "system_error"
    case pendingApproval = "pending_approval"
    case toolApproval = "tool_approval"
}

public struct AppNotification: Codable, Sendable, Identifiable {
    public var id: String
    public var type: AppNotificationType
    public var title: String
    public var message: String
    public var timestamp: Date
    public var metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        type: AppNotificationType,
        title: String,
        message: String,
        timestamp: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.message = message
        self.timestamp = timestamp
        self.metadata = metadata
    }
}
