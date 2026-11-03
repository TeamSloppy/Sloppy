import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Notification socket authentication and recovery")
struct NotificationSocketTests {
    @Test("the notification socket uses the saved token and reads token rotations on reconnect")
    func authenticatedRequest() async throws {
        let baseURL = try #require(URL(string: "https://core.example"))
        let store = AuthSessionStore(persistence: .memory)
        let manager = NotificationSocketManager(baseURL: baseURL, authSessionStore: store)
        await store.saveStaticToken("first-token", for: baseURL)
        let first = try #require(await manager.connectionRequest())
        #expect(first.url?.absoluteString == "wss://core.example/v1/notifications/ws")
        #expect(first.value(forHTTPHeaderField: "Authorization") == "Bearer first-token")
        await store.saveStaticToken("new-token", for: baseURL)
        #expect(await manager.connectionRequest()?.value(forHTTPHeaderField: "Authorization") == "Bearer new-token")
    }

    @Test("local unauthenticated cores keep working without an Authorization header")
    func unauthenticatedRequest() async throws {
        let manager = NotificationSocketManager(baseURL: try #require(URL(string: "http://localhost:25101")),
            authSessionStore: AuthSessionStore(persistence: .memory))
        let request = try #require(await manager.connectionRequest())
        #expect(request.url?.scheme == "ws")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("a reconnect snapshot removes approvals resolved offline and retains newly arriving requests")
    func reconcileAfterReconnect() {
        let fetchedAt = Date()
        var tracker = PendingChatApprovalTracker()
        tracker.apply(record("resolved-offline", updatedAt: fetchedAt.addingTimeInterval(-10)))
        tracker.apply(record("still-pending", updatedAt: fetchedAt.addingTimeInterval(-5)))
        tracker.apply(record("arrived-during-fetch", updatedAt: fetchedAt.addingTimeInterval(1)))
        tracker.reconcilePending([record("still-pending", updatedAt: fetchedAt.addingTimeInterval(-5))], fetchedAt: fetchedAt)
        #expect(tracker.approvalIDs == ["still-pending", "arrived-during-fetch"])
    }

    @Test("an older REST snapshot cannot reintroduce a resolved approval or an expired request")
    func staleSnapshot() {
        let fetchedAt = Date()
        var tracker = PendingChatApprovalTracker()
        tracker.apply(record("resolved", status: "approved", updatedAt: fetchedAt.addingTimeInterval(1)))
        tracker.reconcilePending([
            record("resolved", updatedAt: fetchedAt.addingTimeInterval(-1)),
            PendingToolApprovalRecord(id: "expired", status: "pending", agentId: "agent", sessionId: "chat",
                updatedAt: fetchedAt.addingTimeInterval(-10), expiresAt: fetchedAt.addingTimeInterval(-1)),
        ], fetchedAt: fetchedAt)
        #expect(tracker.approvalIDs.isEmpty)
    }

    private func record(_ id: String, status: String = "pending", updatedAt: Date) -> PendingToolApprovalRecord {
        PendingToolApprovalRecord(id: id, status: status, agentId: "agent", sessionId: "chat", updatedAt: updatedAt)
    }
}
