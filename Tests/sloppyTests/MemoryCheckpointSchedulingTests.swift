import AnyLanguageModel
import Foundation
import Testing
@testable import PluginSDK
@testable import Protocols
@testable import sloppy

private struct MemoryCheckpointFixedTextModel: LanguageModel {
    typealias UnavailableReason = Never

    func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        guard type == String.self else {
            fatalError("MemoryCheckpointFixedTextModel only supports String responses")
        }
        let text = "Checkpoint inspected."
        return LanguageModelSession.Response(
            content: text as! Content,
            rawContent: GeneratedContent(text),
            transcriptEntries: []
        )
    }

    func streamResponse<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        let stream = AsyncThrowingStream<LanguageModelSession.ResponseStream<Content>.Snapshot, any Error> { continuation in
            Task {
                guard let response = try? await respond(
                    within: session,
                    to: prompt,
                    generating: type,
                    includeSchemaInPrompt: includeSchemaInPrompt,
                    options: options
                ) else {
                    continuation.finish()
                    return
                }
                continuation.yield(.init(content: response.content.asPartiallyGenerated(), rawContent: response.rawContent))
                continuation.finish()
            }
        }
        return LanguageModelSession.ResponseStream(stream: stream)
    }
}

private actor BlockingMemoryCheckpointResponseStore {
    private let blockAtResponse: Int
    private var responseCount = 0
    private var blocked = false
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(blockAtResponse: Int) {
        self.blockAtResponse = blockAtResponse
    }

    func waitIfNeeded() async {
        responseCount += 1
        guard responseCount >= blockAtResponse else { return }
        blocked = true
        if !released {
            await withCheckedContinuation { continuation in
                if released {
                    continuation.resume()
                } else {
                    waiters.append(continuation)
                }
            }
        }
    }

    func hasBlocked() -> Bool {
        blocked
    }

    func release() {
        released = true
        let continuations = waiters
        waiters.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }
}

private struct BlockingMemoryCheckpointResponseModel: LanguageModel {
    typealias UnavailableReason = Never

    let store: BlockingMemoryCheckpointResponseStore

    func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        guard type == String.self else {
            fatalError("BlockingMemoryCheckpointResponseModel only supports String responses")
        }
        await store.waitIfNeeded()
        let text = "Turn completed."
        return LanguageModelSession.Response(
            content: text as! Content,
            rawContent: GeneratedContent(text),
            transcriptEntries: []
        )
    }

    func streamResponse<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        let stream = AsyncThrowingStream<LanguageModelSession.ResponseStream<Content>.Snapshot, any Error> { continuation in
            Task {
                guard let response = try? await respond(
                    within: session,
                    to: prompt,
                    generating: type,
                    includeSchemaInPrompt: includeSchemaInPrompt,
                    options: options
                ) else {
                    continuation.finish()
                    return
                }
                continuation.yield(.init(content: response.content.asPartiallyGenerated(), rawContent: response.rawContent))
                continuation.finish()
            }
        }
        return LanguageModelSession.ResponseStream(stream: stream)
    }
}

private actor BlockingMemoryCheckpointResponseProvider: ModelProvider {
    nonisolated let id: String = "blocking-memory-checkpoint-response"
    nonisolated let supportedModels: [String] = ["mock:test-model"]

    private let store: BlockingMemoryCheckpointResponseStore

    init(blockAtResponse: Int) {
        self.store = BlockingMemoryCheckpointResponseStore(blockAtResponse: blockAtResponse)
    }

    func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        BlockingMemoryCheckpointResponseModel(store: store)
    }

    func hasBlocked() async -> Bool {
        await store.hasBlocked()
    }

    func release() async {
        await store.release()
    }
}

private actor BlockingMemoryCheckpointModelProvider: ModelProvider {
    nonisolated let id: String = "blocking-memory-checkpoint"
    nonisolated let supportedModels: [String] = ["mock:test-model"]

    private var started = false
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        started = true
        if !released {
            await withCheckedContinuation { continuation in
                if released {
                    continuation.resume()
                } else {
                    waiters.append(continuation)
                }
            }
        }
        return MemoryCheckpointFixedTextModel()
    }

    func hasStarted() -> Bool {
        started
    }

    func release() {
        released = true
        let continuations = waiters
        waiters.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }
}

private actor MemoryCheckpointCreationProbe {
    private var finished = false

    func markFinished() {
        finished = true
    }

    func isFinished() -> Bool {
        finished
    }
}

@Test
func createAgentSessionSchedulesNewSessionMemoryCheckpointInBackground() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let provider = BlockingMemoryCheckpointModelProvider()
    await service.overrideModelProviderForTests(provider, defaultModel: "mock:test-model")

    let agentID = "checkpoint-bg-\(UUID().uuidString.lowercased())"
    _ = try await service.createAgent(
        AgentCreateRequest(id: agentID, displayName: "Checkpoint Background", role: "Testing")
    )
    let previous = try await service.createAgentSession(
        agentID: agentID,
        request: AgentSessionCreateRequest(title: "Previous")
    )

    let creationProbe = MemoryCheckpointCreationProbe()
    let creationTask = Task {
        let session = try await service.createAgentSession(
            agentID: agentID,
            request: AgentSessionCreateRequest(
                title: "Next",
                checkpointSessionId: previous.id
            )
        )
        await creationProbe.markFinished()
        return session
    }

    let checkpointStarted = await waitForMemoryCheckpointCondition(timeoutNanoseconds: 5_000_000_000) {
        await provider.hasStarted()
    }
    #expect(checkpointStarted)

    let creationReturnedBeforeCheckpointReleased = await waitForMemoryCheckpointCondition(
        timeoutNanoseconds: 5_000_000_000
    ) {
        await creationProbe.isFinished()
    }
    #expect(creationReturnedBeforeCheckpointReleased)

    await provider.release()
    let next = try await creationTask.value
    #expect(next.id != previous.id)
}

@Test
func userTurnThresholdSchedulesMemoryCheckpointInBackground() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let provider = BlockingMemoryCheckpointResponseProvider(
        blockAtResponse: CoreService.agentMemoryCheckpointUserTurnThreshold + 1
    )
    await service.overrideModelProviderForTests(provider, defaultModel: "mock:test-model")

    let agentID = "checkpoint-turn-\(UUID().uuidString.lowercased())"
    _ = try await service.createAgent(
        AgentCreateRequest(id: agentID, displayName: "Checkpoint Turn", role: "Testing")
    )
    let session = try await service.createAgentSession(
        agentID: agentID,
        request: AgentSessionCreateRequest(title: "Threshold")
    )

    for index in 1..<CoreService.agentMemoryCheckpointUserTurnThreshold {
        _ = try await service.postAgentSessionMessage(
            agentID: agentID,
            sessionID: session.id,
            request: AgentSessionPostMessageRequest(userId: "dashboard", content: "turn \(index)")
        )
    }

    let postProbe = MemoryCheckpointCreationProbe()
    let thresholdPost = Task {
        let response = try await service.postAgentSessionMessage(
            agentID: agentID,
            sessionID: session.id,
            request: AgentSessionPostMessageRequest(
                userId: "dashboard",
                content: "turn \(CoreService.agentMemoryCheckpointUserTurnThreshold)"
            )
        )
        await postProbe.markFinished()
        return response
    }

    let checkpointBlocked = await waitForMemoryCheckpointCondition(timeoutNanoseconds: 5_000_000_000) {
        await provider.hasBlocked()
    }
    #expect(checkpointBlocked)

    let postReturnedBeforeCheckpointReleased = await waitForMemoryCheckpointCondition(
        timeoutNanoseconds: 5_000_000_000
    ) {
        await postProbe.isFinished()
    }
    #expect(postReturnedBeforeCheckpointReleased)

    await provider.release()
    let response = try await thresholdPost.value
    #expect(response.appendedEvents.last?.runStatus?.stage == .done)
}

@Test
func requestedMemoryCheckpointPersistsLifecycleEvents() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    await service.overrideModelProviderForTests(
        BlockingMemoryCheckpointResponseProvider(blockAtResponse: 99),
        defaultModel: "mock:test-model"
    )

    let agentID = "checkpoint-events-\(UUID().uuidString.lowercased())"
    _ = try await service.createAgent(
        AgentCreateRequest(id: agentID, displayName: "Checkpoint Events", role: "Testing")
    )
    let session = try await service.createAgentSession(
        agentID: agentID,
        request: AgentSessionCreateRequest(title: "Lifecycle")
    )

    _ = try await service.requestAgentMemoryCheckpoint(
        agentID: agentID,
        sessionID: session.id,
        reason: "tui_compact_command"
    )

    let detail = try await service.getAgentSession(agentID: agentID, sessionID: session.id)
    let checkpointEvents = detail.events.compactMap(\.memoryCheckpoint)

    #expect(checkpointEvents.map(\.status) == [.started, .succeeded])
    #expect(checkpointEvents.map(\.reason) == ["tui_compact_command", "tui_compact_command"])
    #expect(checkpointEvents.last?.message == "Compact success.")
}

@Test
func workerCompletedForExplicitlyDoneProjectTaskSchedulesMemoryCheckpoint() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let provider = BlockingMemoryCheckpointModelProvider()
    await service.overrideModelProviderForTests(provider, defaultModel: "mock:test-model")

    let agentID = "checkpoint-worker-\(UUID().uuidString.lowercased())"
    _ = try await service.createAgent(
        AgentCreateRequest(id: agentID, displayName: "Checkpoint Worker", role: "Testing")
    )
    let session = try await service.createAgentSession(
        agentID: agentID,
        request: AgentSessionCreateRequest(title: "Worker", projectId: "checkpoint-worker-project")
    )
    let project = try await service.createProject(
        ProjectCreateRequest(id: "checkpoint-worker-project", name: "Checkpoint Worker Project")
    ).project
    let updated = try await service.createProjectTask(
        projectID: project.id,
        request: ProjectTaskCreateRequest(
            title: "Remember worker completion",
            status: ProjectTaskStatus.done.rawValue
        )
    )
    let task = try #require(updated.tasks.first)

    await service.handleVisorEvent(
        EventEnvelope(
            messageType: .workerCompleted,
            channelId: "agent:\(agentID):session:\(session.id)",
            taskId: task.id,
            workerId: "worker-1",
            payload: .object([:])
        )
    )

    let checkpointStarted = await waitForMemoryCheckpointCondition(timeoutNanoseconds: 5_000_000_000) {
        await provider.hasStarted()
    }
    #expect(checkpointStarted)

    await provider.release()
}

private func waitForMemoryCheckpointCondition(
    timeoutNanoseconds: UInt64,
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return await condition()
}
