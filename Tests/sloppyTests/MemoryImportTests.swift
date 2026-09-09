import Foundation
import Testing
@testable import AgentRuntime
@testable import Protocols
@testable import sloppy

@Suite
struct MemoryImportTests {
    @Test
    func skillAndExportPromptAreInstalledForAgents() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder(), sharedSkillsRootURLs: [])
        _ = try await service.createAgent(AgentCreateRequest(id: "import-owner", displayName: "Import Owner", role: "Assistant"))
        let skills = try await service.listAgentSkills(agentID: "import-owner")
        let skill = try #require(skills.skills.first { $0.id == "bundled/memory-import" })
        #expect(skill.userInvocable)
        #expect(Set(["files.read", "memory.search", "memory.get", "memory.save"]).isSubset(of: Set(skill.allowedTools)))
        let path = URL(fileURLWithPath: skill.localPath)
        #expect(FileManager.default.fileExists(atPath: path.appendingPathComponent("SKILL.md").path))
        #expect(FileManager.default.fileExists(atPath: path.appendingPathComponent("references/export-prompt.md").path))
    }

    /// Verifies the actual attachment -> tools -> durable retrieval path used by the skill.
    /// Semantic extraction decisions are made by the model, not simulated by this test.
    @Test
    func attachedMarkdownCanBecomeScopedSearchableMemory() async throws {
        let config = CoreConfig.test
        let service = CoreService(config: config, sharedSkillsRootURLs: [])
        let agentID = "import-owner"
        _ = try await service.createAgent(AgentCreateRequest(id: agentID, displayName: "Import Owner", role: "Assistant"))
        let curated = "# Curated\nKeep existing notes.\n"
        try await service.applyAgentMarkdownFromTool(agentID: agentID, field: .memory, markdown: curated)
        let session = try await service.createAgentSession(agentID: agentID, request: .init(title: "Memory import"))
        let markdown = "# Aurora\n\nUse isolated Swift build caches for Aurora.\n"
        let data = Data(markdown.utf8)
        let sessions = await service.sessionStore
        let attachments = try sessions.persistAttachments(agentID: agentID, sessionID: session.id, uploads: [
            .init(name: "memory-export.md", mimeType: "text/markdown", sizeBytes: data.count, contentBase64: data.base64EncodedString())
        ])
        let attachment = try #require(attachments.first)
        let url = try #require(try sessions.resolveAttachmentFileURL(agentID: agentID, attachment: attachment))
        let read = await service.invokeToolFromRuntime(agentID: agentID, sessionID: session.id, request: .init(
            tool: "files.read", arguments: ["path": .string(url.path)]
        ))
        #expect(read.ok)
        #expect(read.data?.asObject?["content"]?.asString == markdown)
        let saved = await service.invokeToolFromRuntime(agentID: agentID, sessionID: session.id, request: .init(
            tool: "memory.save", arguments: [
                "note": .string("Use isolated Swift build caches for Aurora. Source: memory-export.md, Aurora."),
                "kind": .string("preference"), "class": .string("semantic"),
                "scope_type": .string("agent"), "scope_id": .string(agentID),
                "source_type": .string("memory_import"), "source_id": .string(session.id)
            ]
        ))
        #expect(saved.ok)
        let memoryID = try #require(saved.data?.asObject?["id"]?.asString)
        let reopened = HybridMemoryStore(config: config)
        let hits = await reopened.recall(request: .init(query: "Aurora", limit: 10, scope: .agent(agentID)))
        #expect(hits.contains { $0.ref.id == memoryID })
        let otherHits = await reopened.recall(request: .init(query: "Aurora", limit: 10, scope: .agent("another-agent")))
        #expect(otherHits.isEmpty)
        let records = await reopened.entries(filter: .init(scope: .agent(agentID)))
        #expect(records.first { $0.id == memoryID }?.source?.type == "memory_import")
        let after = try await service.getAgentConfigWithMemory(agentID: agentID)
        #expect(after.documents.memoryMarkdown == curated)
    }
}
