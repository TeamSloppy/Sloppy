import Foundation
import SloppyRuntime
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

@Test
func memoryCheckpointUsesOnlyAdmittedSemanticInputsInJournalOrder() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("memory-inputs-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = AgentSessionFileStore(agentsRootURL: root)
    let session = try store.createSession(agentID: "agent", request: .init())
    let legacy = AgentSessionEvent(agentId: "agent", sessionId: session.id, type: .message,
        createdAt: Date(timeIntervalSince1970: 100),
        message: .init(role: .user, segments: [.init(kind: .text, text: "Legacy retained fact")]))
    let queuedID = UUID().uuidString
    let queued = AgentSessionPostMessageRequest(userId: "user", content: "Unadmitted queued instruction", clientMessageId: queuedID)
    let queuedContext = try NativeInputCapture.capture(queued, messageID: queuedID, attachments: [], peerOrigin: nil)
    let queuedFingerprint = try NativeInputCapture.fingerprint(queued, peerOrigin: nil)
    let queuedEvent = AgentSessionEvent(version: 3, agentId: "agent", sessionId: session.id, type: .message,
        createdAt: Date(timeIntervalSince1970: 200),
        inputTransitions: [.init(messageId: queuedID, fingerprint: queuedFingerprint, disposition: .queued, context: queuedContext)],
        message: .init(id: queuedID, role: .user, segments: [.init(kind: .text, text: queued.content)], userId: "user"))
    let admittedID = UUID().uuidString
    let source = AgentSessionPostMessageRequest(userId: "user", content: "/build Prepared admitted fact", clientMessageId: admittedID)
    var admitted = source
    admitted.content = "Prepared admitted fact"
    admitted.mode = .build
    let context = try NativeInputCapture.capture(admitted, messageID: admittedID, attachments: [], peerOrigin: nil, sourceRequest: source)
    let fingerprint = try NativeInputCapture.fingerprint(admitted, peerOrigin: nil, sourceRequest: source)
    let admittedEvent = AgentSessionEvent(version: 3, agentId: "agent", sessionId: session.id, type: .message,
        createdAt: Date(timeIntervalSince1970: 50),
        runtimeMetadata: .init(runId: "run", userTurnId: admittedID, inputMessageId: admittedID, requestFingerprint: fingerprint),
        inputTransitions: [.init(messageId: admittedID, fingerprint: fingerprint, disposition: .admitted,
            owner: .init(runId: "run", userTurnId: admittedID, generation: 0), context: context)],
        message: .init(id: admittedID, role: .user, segments: [.init(kind: .text, text: source.content)], userId: "user"))
    let cancellation = AgentSessionEvent(version: 3, agentId: "agent", sessionId: session.id, type: .runStatus,
        inputTransitions: [.init(messageId: queuedID, fingerprint: queuedFingerprint, disposition: .cancelled, delivery: .delivered)])
    _ = try store.appendEvents(agentID: "agent", sessionID: session.id, events: [legacy, queuedEvent, admittedEvent, cancellation])
    let fresh = try AgentSessionFileStore(agentsRootURL: root).loadSession(agentID: "agent", sessionID: session.id)
    let transcript = CoreService.formattedCheckpointTranscript(from: fresh, maxUTF16Scalars: 10_000)
    #expect(!transcript.contains(queued.content))
    #expect(!transcript.contains("/build"))
    let first = try #require(transcript.range(of: "Legacy retained fact"))
    let second = try #require(transcript.range(of: admitted.content))
    #expect(first.lowerBound < second.lowerBound)
}
