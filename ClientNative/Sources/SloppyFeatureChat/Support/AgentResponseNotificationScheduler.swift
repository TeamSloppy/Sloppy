import Foundation
import UserNotifications

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

@MainActor
public protocol AgentResponseNotificationScheduling: AnyObject {
    func prepareAuthorization() async
    func schedule(_ notification: AgentResponseCompletionNotification) async
}

@MainActor
public final class LocalAgentResponseNotificationScheduler: AgentResponseNotificationScheduling {
    public static let shared = LocalAgentResponseNotificationScheduler()

    private let center: UNUserNotificationCenter
    private var authorizationTask: Task<Void, Never>?

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func prepareAuthorization() async {
        if let authorizationTask {
            await authorizationTask.value
            return
        }

        let task = Task { @MainActor [center] in
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        authorizationTask = task
        await task.value
    }

    public func schedule(_ notification: AgentResponseCompletionNotification) async {
        await prepareAuthorization()

        let settings = await center.notificationSettings()
        var canSchedule = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        #if os(iOS) || os(visionOS)
        canSchedule = canSchedule || settings.authorizationStatus == .ephemeral
        #endif
        guard canSchedule else {
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
}
