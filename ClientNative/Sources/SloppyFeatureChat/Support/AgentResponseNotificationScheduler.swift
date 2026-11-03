import Foundation
import UserNotifications
import SloppyClientCore
import Logging

public struct AgentResponseCompletionNotification: Sendable, Equatable {
    public let agentName: String
    public let sessionTitle: String
    public let responsePreview: String?
    public let agentId: String
    public let sessionId: String
    public let messageId: String

    public init(
        agentName: String,
        sessionTitle: String,
        responsePreview: String?,
        agentId: String,
        sessionId: String,
        messageId: String
    ) {
        self.agentName = agentName
        self.sessionTitle = sessionTitle
        self.responsePreview = responsePreview
        self.agentId = agentId
        self.sessionId = sessionId
        self.messageId = messageId
    }

    public var identifier: String {
        "agent-response.\(sessionId).\(messageId)"
    }

    public var title: String {
        "\(agentName) finished responding"
    }

    public var body: String {
        let preview = responsePreview?
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard let preview, !preview.isEmpty else {
            return "The agent’s response is ready."
        }
        return String(preview.prefix(240))
    }

    public var deepLink: String {
        var components = URLComponents()
        components.scheme = "sloppy"
        components.host = "session"
        components.queryItems = [
            URLQueryItem(name: "agent", value: agentId),
            URLQueryItem(name: "id", value: sessionId),
        ]
        return components.url?.absoluteString ?? "sloppy://open"
    }
}

public struct AgentToolApprovalNotification: Sendable, Equatable {
    public let approvalId: String
    public let agentId: String
    public let sessionId: String
    public let tool: String
    public let reason: String?
    public let expiresAt: Date?

    public init?(approval: PendingToolApprovalRecord) {
        guard approval.status == "pending", let agentId = approval.agentId,
              let sessionId = approval.displaySessionId ?? approval.sessionId else { return nil }
        self.approvalId = approval.id
        self.agentId = agentId
        self.sessionId = sessionId
        self.tool = approval.tool ?? "tool"
        self.reason = approval.reason
        self.expiresAt = approval.expiresAt
    }

    public init?(notification: AppNotification) {
        guard notification.type == .toolApproval else { return nil }
        let formatter = ISO8601DateFormatter()
        let expiresAt = notification.metadata["expiresAt"].flatMap { text in
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: text)
        }
        self.init(approval: PendingToolApprovalRecord(
            id: notification.metadata["approvalId"] ?? notification.id,
            status: notification.metadata["status"] ?? "pending",
            agentId: notification.metadata["agentId"], sessionId: notification.metadata["sessionId"],
            displaySessionId: notification.metadata["displaySessionId"], tool: notification.metadata["tool"],
            reason: notification.metadata["reason"] ?? notification.message,
            updatedAt: notification.timestamp, expiresAt: expiresAt
        ))
    }

    public var identifier: String { "tool-approval.\(approvalId)" }
    public var deepLink: String {
        AgentResponseCompletionNotification(agentName: agentId, sessionTitle: "", responsePreview: nil,
            agentId: agentId, sessionId: sessionId, messageId: approvalId).deepLink
    }
}

@MainActor
public protocol AgentResponseNotificationScheduling: AnyObject {
    func prepareAuthorization() async
    func schedule(_ notification: AgentResponseCompletionNotification) async
    func scheduleApproval(_ notification: AgentToolApprovalNotification) async
    func dismissApproval(id: String)
}

public extension AgentResponseNotificationScheduling {
    func scheduleApproval(_ notification: AgentToolApprovalNotification) async {}
    func dismissApproval(id: String) {}
}

@MainActor
public final class LocalAgentResponseNotificationScheduler: AgentResponseNotificationScheduling {
    public static let shared = LocalAgentResponseNotificationScheduler()

    private let center: any AgentNotificationCenter
    private var notifiedApprovalIDs: Set<String> = []
    private var resolvedApprovalIDs: Set<String> = []
    private var approvalExpirationTasks: [String: Task<Void, Never>] = [:]
    private let logger = Logger(label: "sloppy.local-notifications")
    private var authorizationTask: Task<Void, Never>?

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = SystemAgentNotificationCenter(center)
    }

    init(notificationCenter: any AgentNotificationCenter) {
        self.center = notificationCenter
    }

    private func canSchedule() async -> Bool {
        let status = await center.authorizationStatus()
        if status == .authorized || status == .provisional { return true }
        #if os(iOS) || os(visionOS)
        if status == .ephemeral { return true }
        #endif
        return false
    }

    public func prepareAuthorization() async {
        if let authorizationTask {
            await authorizationTask.value
            return
        }

        let task = Task { @MainActor [center] in
            guard await center.authorizationStatus() == .notDetermined else { return }
            try? await center.requestAuthorization()
        }
        authorizationTask = task
        await task.value
    }

    public func schedule(_ notification: AgentResponseCompletionNotification) async {
        await prepareAuthorization()

        guard await canSchedule() else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.subtitle = notification.sessionTitle
        content.body = notification.body
        content.sound = .default
        content.threadIdentifier = notification.sessionId
        content.categoryIdentifier = "AGENT_RESPONSE_COMPLETE"
        content.userInfo = ["deepLink": notification.deepLink]

        let request = UNNotificationRequest(
            identifier: notification.identifier,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    public func scheduleApproval(_ notification: AgentToolApprovalNotification) async {
        guard !resolvedApprovalIDs.contains(notification.approvalId),
              notification.expiresAt.map({ $0 > Date() }) ?? true,
              notifiedApprovalIDs.insert(notification.approvalId).inserted else { return }
        await prepareAuthorization()
        guard await canSchedule(),
              !resolvedApprovalIDs.contains(notification.approvalId),
              notifiedApprovalIDs.contains(notification.approvalId),
              notification.expiresAt.map({ $0 > Date() }) ?? true else {
            notifiedApprovalIDs.remove(notification.approvalId)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Approval required"
        let reason = notification.reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let reason, !reason.isEmpty { content.body = reason }
        else { content.body = "Allow \(notification.tool) to continue this chat." }
        content.sound = .default
        content.threadIdentifier = notification.sessionId
        content.categoryIdentifier = "TOOL_APPROVAL_REQUIRED"
        content.userInfo = ["deepLink": notification.deepLink]
        do {
            try await center.add(UNNotificationRequest(identifier: notification.identifier, content: content, trigger: nil))
            // A resolution can arrive while the notification center is adding the request.
            guard notifiedApprovalIDs.contains(notification.approvalId) else {
                dismissApproval(id: notification.approvalId)
                return
            }
            if let expiresAt = notification.expiresAt {
                approvalExpirationTasks[notification.approvalId] = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(max(0, expiresAt.timeIntervalSinceNow)))
                    guard !Task.isCancelled else { return }
                    self?.dismissApproval(id: notification.approvalId)
                }
            }
        } catch {
            notifiedApprovalIDs.remove(notification.approvalId)
            logger.warning("Failed to show approval notification: \(error)")
        }
    }

    public func dismissApproval(id: String) {
        resolvedApprovalIDs.insert(id)
        notifiedApprovalIDs.remove(id)
        approvalExpirationTasks.removeValue(forKey: id)?.cancel()
        let identifier = "tool-approval.\(id)"
        center.remove(identifier: identifier)
    }

    public func updateToolApproval(_ notification: AppNotification) async {
        guard notification.type == .toolApproval else { return }
        let id = notification.metadata["approvalId"] ?? notification.id
        guard (notification.metadata["status"] ?? "pending") == "pending" else {
            dismissApproval(id: id)
            return
        }
        if let approval = AgentToolApprovalNotification(notification: notification) {
            await scheduleApproval(approval)
        }
    }

}
