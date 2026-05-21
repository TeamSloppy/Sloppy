import Foundation
import Testing
@testable import Protocols
@testable import sloppy

@Test
func agentSessionStoreCachesListsAndInvalidatesSummarySidecar() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-session-cache-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let agentID = "cache-agent"
    let catalog = AgentCatalogFileStore(agentsRootURL: rootURL)
    _ = try catalog.createAgent(
        AgentCreateRequest(id: agentID, displayName: "Cache Agent", role: "Testing"),
        availableModels: []
    )

    let store = AgentSessionFileStore(agentsRootURL: rootURL)
    let session = try store.createSession(
        agentID: agentID,
        request: AgentSessionCreateRequest(title: "Cached session")
    )
    let summaryURL = rootURL
        .appendingPathComponent(agentID, isDirectory: true)
        .appendingPathComponent("sessions", isDirectory: true)
        .appendingPathComponent("\(session.id).summary.json")
    try? FileManager.default.removeItem(at: summaryURL)
    #expect(!FileManager.default.fileExists(atPath: summaryURL.path))

    let warmed = try store.listSessions(agentID: agentID)
    #expect(warmed.map(\.id) == [session.id])
    #expect(FileManager.default.fileExists(atPath: summaryURL.path))

    let userEvent = AgentSessionEvent(
        agentId: agentID,
        sessionId: session.id,
        type: .message,
        createdAt: Date().addingTimeInterval(60),
        message: AgentSessionMessage(
            role: .user,
            segments: [AgentMessageSegment(kind: .text, text: "Fresh summary text")],
            userId: "tester"
        )
    )
    _ = try store.appendEvents(agentID: agentID, sessionID: session.id, events: [userEvent])
    let afterAppend = try store.listSessions(agentID: agentID)
    #expect(afterAppend.first?.messageCount == 1)
    #expect(afterAppend.first?.lastMessagePreview == "Fresh summary text")

    _ = try store.incrementUserTurnCount(agentID: agentID, sessionID: session.id)
    let afterTurnCount = try store.listSessions(agentID: agentID)
    #expect(afterTurnCount.first?.userTurnCount == 1)

    try store.deleteSession(agentID: agentID, sessionID: session.id)
    #expect(!FileManager.default.fileExists(atPath: summaryURL.path))
    #expect(try store.listSessions(agentID: agentID).isEmpty)
}

@Test
func agentSessionStorePaginatesCachedSessionList() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-session-pagination-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let agentID = "paged-agent"
    let catalog = AgentCatalogFileStore(agentsRootURL: rootURL)
    _ = try catalog.createAgent(
        AgentCreateRequest(id: agentID, displayName: "Paged Agent", role: "Testing"),
        availableModels: []
    )

    let store = AgentSessionFileStore(agentsRootURL: rootURL)
    let first = try store.createSession(agentID: agentID, request: AgentSessionCreateRequest(title: "First"))
    let second = try store.createSession(agentID: agentID, request: AgentSessionCreateRequest(title: "Second"))
    let third = try store.createSession(agentID: agentID, request: AgentSessionCreateRequest(title: "Third"))

    for (index, session) in [first, second, third].enumerated() {
        let event = AgentSessionEvent(
            agentId: agentID,
            sessionId: session.id,
            type: .message,
            createdAt: Date().addingTimeInterval(TimeInterval(index + 1) * 60),
            message: AgentSessionMessage(
                role: .user,
                segments: [AgentMessageSegment(kind: .text, text: "message \(index)")],
                userId: "tester"
            )
        )
        _ = try store.appendEvents(agentID: agentID, sessionID: session.id, events: [event])
    }

    let page = try store.listSessions(agentID: agentID, limit: 1, offset: 1)
    #expect(page.count == 1)
    #expect(page.first?.id == second.id)
}

@Test
func agentSessionStoreDeletesExpiredSessionsAndCompanionFiles() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-session-retention-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let agentID = "retention-agent"
    let catalog = AgentCatalogFileStore(agentsRootURL: rootURL)
    _ = try catalog.createAgent(
        AgentCreateRequest(id: agentID, displayName: "Retention Agent", role: "Testing"),
        availableModels: []
    )

    let store = AgentSessionFileStore(agentsRootURL: rootURL)
    let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
    let freshDate = oldDate.addingTimeInterval(10 * 24 * 60 * 60)
    let oldSession = try store.createSession(
        agentID: agentID,
        request: AgentSessionCreateRequest(title: "Old"),
        createdAt: oldDate
    )
    let freshSession = try store.createSession(
        agentID: agentID,
        request: AgentSessionCreateRequest(title: "Fresh"),
        createdAt: freshDate
    )

    _ = try store.incrementUserTurnCount(agentID: agentID, sessionID: oldSession.id)
    _ = try store.persistAttachments(
        agentID: agentID,
        sessionID: oldSession.id,
        uploads: [
            AgentAttachmentUpload(
                name: "note.txt",
                mimeType: "text/plain",
                sizeBytes: 5,
                contentBase64: "aGVsbG8="
            )
        ]
    )

    let sessionsURL = rootURL
        .appendingPathComponent(agentID, isDirectory: true)
        .appendingPathComponent("sessions", isDirectory: true)
    let oldFileURL = sessionsURL.appendingPathComponent("\(oldSession.id).jsonl")
    let oldSidecarURL = sessionsURL.appendingPathComponent("\(oldSession.id).sidecar.json")
    let oldAssetsURL = sessionsURL.appendingPathComponent("\(oldSession.id).assets", isDirectory: true)

    let deleted = try store.deleteExpiredSessions(
        agentIDs: [agentID],
        olderThan: oldDate.addingTimeInterval(2 * 24 * 60 * 60)
    )

    #expect(deleted.map(\.id) == [oldSession.id])
    #expect(!FileManager.default.fileExists(atPath: oldFileURL.path))
    #expect(!FileManager.default.fileExists(atPath: oldSidecarURL.path))
    #expect(!FileManager.default.fileExists(atPath: oldAssetsURL.path))
    #expect(try store.listSessions(agentID: agentID).map(\.id) == [freshSession.id])
}

@Test
func agentSessionStoreSerializesConcurrentAppends() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-session-concurrent-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let agentID = "concurrent-agent"
    let catalog = AgentCatalogFileStore(agentsRootURL: rootURL)
    _ = try catalog.createAgent(
        AgentCreateRequest(id: agentID, displayName: "Concurrent Agent", role: "Testing"),
        availableModels: []
    )

    let primaryStore = AgentSessionFileStore(agentsRootURL: rootURL)
    let secondaryStore = AgentSessionFileStore(agentsRootURL: rootURL)
    let session = try primaryStore.createSession(
        agentID: agentID,
        request: AgentSessionCreateRequest(title: "Concurrent session")
    )

    let errorCollector = ErrorCollector()
    let iterations = 80
    DispatchQueue.concurrentPerform(iterations: iterations) { index in
        do {
            let event = AgentSessionEvent(
                agentId: agentID,
                sessionId: session.id,
                type: .message,
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                message: AgentSessionMessage(
                    role: .user,
                    segments: [AgentMessageSegment(kind: .text, text: "message \(index)")],
                    userId: "tester"
                )
            )
            let store = index.isMultiple(of: 2) ? primaryStore : secondaryStore
            _ = try store.appendEvents(agentID: agentID, sessionID: session.id, events: [event])
        } catch {
            errorCollector.append(error)
        }
    }

    #expect(errorCollector.errors.isEmpty)
    if let firstError = errorCollector.errors.first {
        throw firstError
    }

    let detail = try primaryStore.loadSession(agentID: agentID, sessionID: session.id)
    let userMessageCount = detail.events.filter { $0.message?.role == .user }.count
    #expect(userMessageCount == iterations)
    #expect(try secondaryStore.listSessions(agentID: agentID).first?.messageCount == iterations)
}

private final class ErrorCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [any Error] = []

    var errors: [any Error] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func append(_ error: any Error) {
        lock.lock()
        defer { lock.unlock() }
        values.append(error)
    }
}
