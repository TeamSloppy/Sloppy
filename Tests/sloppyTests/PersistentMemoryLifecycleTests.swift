import Foundation
import Testing
@testable import AgentRuntime
@testable import Protocols
@testable import sloppy

@Test
func curatedMemorySurvivesConfigReadsAndNewSessions() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    _ = try await service.createAgent(AgentCreateRequest(id: "memory-owner", displayName: "Memory Owner", role: "Assistant"))
    let curated = "# Memory\n\nThe repository requires isolated build caches.\n"
    try await service.applyAgentMarkdownFromTool(agentID: "memory-owner", field: .memory, markdown: curated)
    let before = try await service.getAgentConfigWithMemory(agentID: "memory-owner")
    #expect(before.documents.memoryMarkdown == curated)
    _ = await service.memoryStore.save(entry: MemoryWriteRequest(
        note: "The shared runtime uses Swift actors", kind: .fact, memoryClass: .semantic,
        scope: .agent("memory-owner")
    ))
    let session = try await service.createAgentSession(agentID: "memory-owner", request: AgentSessionCreateRequest(title: "New task"))
    _ = try await service.postAgentSessionMessage(
        agentID: "memory-owner", sessionID: session.id,
        request: AgentSessionPostMessageRequest(userId: "dashboard", content: "Hello")
    )
    let bootstrap = await service.runtime.channelBootstrapContent(channelId: "agent:memory-owner:session:\(session.id)")
    #expect(bootstrap?.contains("The shared runtime uses Swift actors") == true)
    #expect(bootstrap?.contains("The repository requires isolated build caches.") == true)
    let after = try await service.getAgentConfigWithMemory(agentID: "memory-owner")
    #expect(after.documents.memoryMarkdown == curated)
}

@Test
func memoryCheckpointRetainsRecentCorrectionsAndExcludesThinking() {
    let events = [
        AgentSessionEvent(agentId: "helper", sessionId: "session", type: .message,
            createdAt: Date(timeIntervalSince1970: 1),
            message: AgentSessionMessage(role: .user, segments: [.init(kind: .text, text: String(repeating: "old context ", count: 100))])),
        AgentSessionEvent(agentId: "helper", sessionId: "session", type: .message,
            createdAt: Date(timeIntervalSince1970: 2),
            message: AgentSessionMessage(role: .assistant, segments: [.init(kind: .thinking, text: "Unverified speculation")])),
        AgentSessionEvent(agentId: "helper", sessionId: "session", type: .message,
            createdAt: Date(timeIntervalSince1970: 3),
            message: AgentSessionMessage(role: .user, segments: [.init(kind: .text, text: "Correction: use Swift Testing. 🧠")]))
    ]
    let detail = AgentSessionDetail(summary: AgentSessionSummary(id: "session", agentId: "helper", title: "Task"), events: events)
    let transcript = CoreService.formattedCheckpointTranscript(from: detail, maxUTF16Scalars: 100)
    #expect(transcript.hasSuffix("Correction: use Swift Testing. 🧠"))
    #expect(transcript.unicodeScalars.count <= 100)
    #expect(!CoreService.formattedCheckpointTranscript(from: detail, maxUTF16Scalars: 5000).contains("Unverified speculation"))
    #expect(CoreService.formattedCheckpointTranscript(from: detail, maxUTF16Scalars: 0).isEmpty)
}

@Test
func persistentMemoryIsAvailableAfterReopeningSQLite() async {
    let config = CoreConfig.test
    let writer = HybridMemoryStore(config: config)
    _ = await writer.save(entry: MemoryWriteRequest(
        note: "Use isolated build caches", kind: .fact, memoryClass: .semantic,
        scope: .project("aurora")
    ))
    let reader = HybridMemoryStore(config: config)
    let runtime = RuntimeSystem(memoryStore: reader)
    await runtime.setMemoryProject(channelId: "agent:helper:session:new", projectID: "aurora")
    let context = await runtime.persistentMemoryContext(channelId: "agent:helper:session:new")
    #expect(context.contains("Use isolated build caches"))
}
