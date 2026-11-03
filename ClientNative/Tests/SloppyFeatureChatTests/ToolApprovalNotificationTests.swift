import Foundation
import SloppyClientCore
import Testing
import UserNotifications
@testable import SloppyFeatureChat

@Suite("Tool approval notifications")
struct ToolApprovalNotificationTests {
    @Test("ACP permission events without approval metadata still create a chat notification")
    func acpPermissionEvent() throws {
        let event = AppNotification(id: "permission-event", type: .toolApproval,
            title: "Tool approval required", message: "Allow workspace command",
            metadata: ["agentId": "agent", "sessionId": "chat"])
        let notification = try #require(AgentToolApprovalNotification(notification: event))
        #expect(notification.approvalId == event.id)
        #expect(notification.reason == event.message)
        #expect(notification.sessionId == "chat")
    }

    @Test("fractional expiry timestamps are retained")
    func fractionalExpiry() throws {
        let event = AppNotification(type: .toolApproval, title: "Approval", message: "",
            metadata: ["agentId": "agent", "sessionId": "chat", "expiresAt": "2026-11-03T13:00:00.125Z"])
        #expect(try #require(AgentToolApprovalNotification(notification: event)).expiresAt != nil)
    }

    @Test("worker approval links to the parent chat and retains its expiry")
    func parentChatLink() throws {
        let expiry = Date().addingTimeInterval(600)
        let record = PendingToolApprovalRecord(id: "approval", status: "pending", agentId: "agent/one",
            sessionId: "worker", displaySessionId: "parent chat", tool: "runtime.exec",
            updatedAt: Date(), expiresAt: expiry)
        let notification = try #require(AgentToolApprovalNotification(approval: record))
        let components = try #require(URLComponents(string: notification.deepLink))
        #expect(components.queryItems?.first { $0.name == "id" }?.value == "parent chat")
        #expect(components.queryItems?.first { $0.name == "agent" }?.value == "agent/one")
        #expect(notification.expiresAt == expiry)
        #expect(notification.identifier == "tool-approval.approval")
    }

    @Test("resolved approvals cannot create a new actionable notification", arguments: ["approved", "rejected", "timed_out"])
    func resolvedApproval(status: String) {
        let record = PendingToolApprovalRecord(id: "approval", status: status, agentId: "agent",
            sessionId: "chat", updatedAt: Date())
        #expect(AgentToolApprovalNotification(approval: record) == nil)
    }
}

@Suite("Tool approval notification delivery")
@MainActor
struct ToolApprovalNotificationDeliveryTests {
    @Test("approval notifications request permission, carry sound and open the parent chat once")
    func requestsPermissionAndDeliversOnce() async throws {
        let center = ApprovalNotificationCenter(status: .notDetermined)
        let scheduler = LocalAgentResponseNotificationScheduler(notificationCenter: center)
        let notification = try approval()
        await scheduler.scheduleApproval(notification)
        await scheduler.scheduleApproval(notification)
        #expect(center.authorizationRequests == 1)
        let request = try #require(center.requests.first)
        #expect(center.requests.count == 1)
        #expect(request.content.title == "Approval required")
        #expect(request.content.body == "Allow runtime.exec to continue this chat.")
        #expect(request.content.sound != nil)
        #expect(request.content.categoryIdentifier == "TOOL_APPROVAL_REQUIRED")
        #expect(request.content.userInfo["deepLink"] as? String == notification.deepLink)
        #expect(request.content.threadIdentifier == "parent")
    }

    @Test("permission events without approvalId reach the notification center")
    func deliversACPEvent() async {
        let center = ApprovalNotificationCenter()
        let scheduler = LocalAgentResponseNotificationScheduler(notificationCenter: center)
        let event = AppNotification(id: "acp", type: .toolApproval, title: "Tool approval required", message: "Approve command",
            metadata: ["agentId": "agent", "sessionId": "chat"])
        await scheduler.updateToolApproval(event)
        #expect(center.requests.first?.identifier == "tool-approval.acp")
        #expect(center.requests.first?.content.body == "Approve command")
    }

    @Test("resolved notifications are removed and delayed pending events cannot revive them")
    func resolutionPreventsReplay() async throws {
        let center = ApprovalNotificationCenter()
        let scheduler = LocalAgentResponseNotificationScheduler(notificationCenter: center)
        let notification = try approval()
        await scheduler.scheduleApproval(notification)
        await scheduler.updateToolApproval(AppNotification(type: .toolApproval, title: "Resolved", message: "",
            metadata: ["approvalId": "approval", "status": "approved"]))
        await scheduler.scheduleApproval(notification)
        #expect(center.delivered.isEmpty)
        #expect(center.requests.count == 1)
        #expect(center.removed.contains(notification.identifier))
    }

    @Test("a resolution arriving during delivery removes the just-added notification")
    func resolutionDuringAdd() async throws {
        let center = ApprovalNotificationCenter()
        let scheduler = LocalAgentResponseNotificationScheduler(notificationCenter: center)
        center.duringAdd = { scheduler.dismissApproval(id: "approval") }
        await scheduler.scheduleApproval(try approval())
        #expect(center.delivered.isEmpty)
    }

    @Test("denied permission can recover after the user enables notifications in system settings")
    func permissionRecovery() async throws {
        let center = ApprovalNotificationCenter(status: .denied)
        let scheduler = LocalAgentResponseNotificationScheduler(notificationCenter: center)
        await scheduler.scheduleApproval(try approval())
        #expect(center.requests.isEmpty)
        center.status = .authorized
        await scheduler.scheduleApproval(try approval())
        #expect(center.requests.count == 1)
    }

    @Test("expired approval requests never produce notifications")
    func expiredApproval() async throws {
        let center = ApprovalNotificationCenter()
        let scheduler = LocalAgentResponseNotificationScheduler(notificationCenter: center)
        await scheduler.scheduleApproval(try approval(expiresAt: .distantPast))
        #expect(center.requests.isEmpty)
    }

    private func approval(expiresAt: Date? = nil) throws -> AgentToolApprovalNotification {
        try #require(AgentToolApprovalNotification(approval: PendingToolApprovalRecord(
            id: "approval", status: "pending", agentId: "agent", sessionId: "worker", displaySessionId: "parent",
            tool: "runtime.exec", updatedAt: Date(), expiresAt: expiresAt)))
    }
}

@MainActor
private final class ApprovalNotificationCenter: AgentNotificationCenter {
    var status: UNAuthorizationStatus
    var authorizationRequests = 0
    var requests: [UNNotificationRequest] = []
    var delivered: Set<String> = []
    var removed: Set<String> = []
    var duringAdd: (() -> Void)?

    init(status: UNAuthorizationStatus = .authorized) { self.status = status }
    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async throws {
        authorizationRequests += 1
        status = .authorized
    }
    func add(_ request: UNNotificationRequest) async throws {
        requests.append(request)
        duringAdd?()
        delivered.insert(request.identifier)
    }
    func remove(identifier: String) {
        removed.insert(identifier)
        delivered.remove(identifier)
    }
}
