import Foundation
import UserNotifications

@MainActor
protocol AgentNotificationCenter: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws
    func add(_ request: UNNotificationRequest) async throws
    func remove(identifier: String)
}

@MainActor
final class SystemAgentNotificationCenter: AgentNotificationCenter {
    private let center: UNUserNotificationCenter

    init(_ center: UNUserNotificationCenter) { self.center = center }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws {
        _ = try await center.requestAuthorization(options: [.alert, .sound])
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func remove(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
