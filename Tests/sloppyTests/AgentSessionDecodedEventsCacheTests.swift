import Foundation
import Testing
import SloppyRuntime
@testable import Protocols
@testable import sloppy

@Test
func agentSessionStoreDecodedEventsStayCurrentAcrossAppendsAndForeignWrites() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-session-decoded-cache-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let agentID = "cache-agent"
    let catalog = AgentCatalogFileStore(agentsRootURL: rootURL)
    _ = try catalog.createAgent(
        AgentCreateRequest(id: agentID, displayName: "Cache Agent", role: "Testing"),
        availableModels: []
    )
    let store = AgentSessionFileStore(agentsRootURL: rootURL)
    let otherInstance = AgentSessionFileStore(agentsRootURL: rootURL)
    let session = try store.createSession(agentID: agentID, request: AgentSessionCreateRequest(title: "Cached"))

    func message(_ text: String, at second: TimeInterval) -> AgentSessionEvent {
        AgentSessionEvent(
            agentId: agentID,
            sessionId: session.id,
            type: .message,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000 + second),
            message: AgentSessionMessage(role: .user, segments: [AgentMessageSegment(kind: .text, text: text)], userId: "tester")
        )
    }
    func texts(_ detail: AgentSessionDetail) -> [String] {
        detail.events.compactMap { $0.message?.segments.first?.text }
    }

    _ = try store.appendEvents(agentID: agentID, sessionID: session.id, events: [message("one", at: 1)])
    #expect(texts(try store.loadSession(agentID: agentID, sessionID: session.id)) == ["one"])

    // Appends through the same instance keep the cached journal in sync, in createdAt order.
    _ = try store.appendEvents(agentID: agentID, sessionID: session.id, events: [message("three", at: 3)])
    _ = try store.appendEvents(agentID: agentID, sessionID: session.id, events: [message("two", at: 2)])
    #expect(texts(try store.loadSession(agentID: agentID, sessionID: session.id)) == ["one", "two", "three"])

    // A write from another instance must invalidate the first instance's cache.
    _ = try otherInstance.appendEvents(agentID: agentID, sessionID: session.id, events: [message("four", at: 4)])
    #expect(texts(try store.loadSession(agentID: agentID, sessionID: session.id)) == ["one", "two", "three", "four"])

    // So must a write that bypasses the store entirely.
    let path = try store.sessionFilePath(agentID: agentID, sessionID: session.id)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    var line = try encoder.encode(message("five", at: 5))
    line.append(0x0A)
    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    try handle.seekToEnd()
    try handle.write(contentsOf: line)
    try handle.close()
    #expect(texts(try store.loadSession(agentID: agentID, sessionID: session.id)) == ["one", "two", "three", "four", "five"])
}
