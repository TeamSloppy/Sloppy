import Foundation
import Testing
@testable import Protocols
@testable import sloppy

@Test
func agentDocumentsCanBeScopedPerUserWithRootFallback() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-agent-docs-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let store = AgentCatalogFileStore(agentsRootURL: rootURL)
    _ = try store.createAgent(
        AgentCreateRequest(
            id: "helper",
            displayName: "Helper",
            role: "Assistant"
        ),
        availableModels: []
    )

    try store.writeAgentScopedMarkdown(
        agentID: "helper",
        userID: "alice",
        field: .memory,
        markdown: "# Memory\n\n- Alice prefers short answers.\n"
    )
    try store.writeAgentScopedMarkdown(
        agentID: "helper",
        userID: "bob",
        field: .memory,
        markdown: "# Memory\n\n- Bob prefers detailed answers.\n"
    )

    let alice = try store.readAgentDocuments(agentID: "helper", userID: "alice")
    let bob = try store.readAgentDocuments(agentID: "helper", userID: "bob")
    let unknown = try store.readAgentDocuments(agentID: "helper", userID: "carol")

    #expect(alice.memoryMarkdown.contains("Alice prefers short answers."))
    #expect(!alice.memoryMarkdown.contains("Bob prefers detailed answers."))
    #expect(bob.memoryMarkdown.contains("Bob prefers detailed answers."))
    #expect(!bob.memoryMarkdown.contains("Alice prefers short answers."))
    #expect(!unknown.memoryMarkdown.contains("Alice prefers short answers."))
    #expect(!unknown.memoryMarkdown.contains("Bob prefers detailed answers."))
    #expect(alice.userMarkdown.contains("Prefers practical, result-oriented responses."))
}
