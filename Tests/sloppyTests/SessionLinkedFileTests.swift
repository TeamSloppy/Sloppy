import Foundation
import Protocols
import Testing
@testable import sloppy

@Suite("Conversation-linked external files")
struct SessionLinkedFileTests {
    @Test func parsesOnlyExactLocalLinks() {
        #expect(SessionLinkedFilePath.links(in: "[file](/tmp/worktree/AGENTS.md:140) [space](</tmp/My File.swift:3>) [url](file:///tmp/image.jpg#L2)") == ["/tmp/worktree/AGENTS.md", "/tmp/My File.swift", "/tmp/image.jpg"])
        #expect(SessionLinkedFilePath.links(in: "plain /tmp/a.txt [remote](https://host/a.txt) [traversal](/tmp/../secret) [host](file://remote/tmp/a)").isEmpty)
        #expect(SessionLinkedFilePath.absolutePath("relative.txt") == nil)
        #expect(SessionLinkedFilePath.absolutePath("/tmp/../secret") == nil)
    }

    @Test func previewsLinkedWorktreeFileButDeniesUnlinkedPathsAndForeignSessions() async throws {
        let config = CoreConfig.test
        let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let agent = "links-\(UUID().uuidString.prefix(8).lowercased())"
        _ = try await service.createAgent(.init(id: agent, displayName: "Links", role: "Test"))
        let session = try await service.createAgentSession(agentID: agent, request: .init(title: "Links"))
        let other = try await service.createAgentSession(agentID: agent, request: .init(title: "Other"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("AGENTS.md")
        let unlinked = directory.appendingPathComponent("secret.txt")
        try Data("external worktree file".utf8).write(to: file)
        try Data("not linked".utf8).write(to: unlinked)
        let event = AgentSessionEvent(agentId: agent, sessionId: session.id, type: .message,
            message: .init(role: .assistant, segments: [.init(kind: .text, text: "[AGENTS.md](\(file.path):140)")]))
        _ = try await service.sessionStore.appendEvents(agentID: agent, sessionID: session.id, events: [event])
        let response = try await service.readSessionLinkedFile(agentID: agent, sessionID: session.id, path: file.path)
        #expect(response.content == "external worktree file")
        #expect(response.path == file.path)
        await #expect(throws: (any Error).self) {
            try await service.readSessionLinkedFile(agentID: agent, sessionID: session.id, path: unlinked.path)
        }
        await #expect(throws: (any Error).self) {
            try await service.readSessionLinkedFile(agentID: agent, sessionID: other.id, path: file.path)
        }
        await #expect(throws: (any Error).self) {
            try await service.readSessionLinkedFile(agentID: agent, sessionID: session.id, path: directory.path)
        }
        // Existing project read and browse APIs must retain their boundaries.
        let projectID = "linked-test-\(UUID().uuidString.prefix(8).lowercased())"
        let router = CoreRouter(service: service)
        let created = await router.handle(method: "POST", path: "/v1/projects", body: try JSONEncoder().encode(
            ProjectCreateRequest(id: projectID, name: "Linked", description: "Test", channels: [])))
        #expect(created.status == 201)
        await #expect(throws: (any Error).self) { try await service.readProjectFile(projectID: projectID, path: file.path) }
        await #expect(throws: (any Error).self) { try await service.listProjectFiles(projectID: projectID, path: directory.path) }
        let path = "/v1/agents/\(agent)/sessions/\(session.id)/linked-file?path=\(file.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)"
        let routed = await router.handle(method: "GET", path: path, body: nil)
        #expect(routed.status == 200)
        #expect(try JSONDecoder().decode(ProjectFileContentResponse.self, from: routed.body).content == response.content)
    }
}
