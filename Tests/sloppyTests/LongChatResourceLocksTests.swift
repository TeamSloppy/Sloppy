import AnyLanguageModel
import Foundation
import PluginSDK
import Protocols
import Testing
@testable import sloppy

@Suite("Long chat file-scoped concurrency")
struct LongChatResourceLocksTests {
    @Test func explicitFilesAvoidAutomaticCheckoutLockButCoarseRequestsKeepIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let scoped = try LongChatResourceLocks.canonicalKeys(
            ["path:Sources/One.swift", "path:Tests/OneTests.swift"], projectID: "p", repositoryPath: root.path)
        #expect(scoped.count == 2 && scoped.allSatisfy { $0.hasPrefix("path:") })
        let coarse = try LongChatResourceLocks.canonicalKeys([], projectID: "p", repositoryPath: root.path)
        let legacyRoot = try LongChatResourceLocks.canonicalKeys([], projectID: "p", repositoryPath: root.path + "/Sources/..")
        #expect(legacyRoot == coarse)
        #expect(coarse.contains("project:p"))
        #expect(LongChatResourceLocks.conflicts(scoped, with: Set(coarse)))
        let explicit = try LongChatResourceLocks.canonicalKeys(
            ["path:Sources/One.swift", "project:p"], projectID: "p", repositoryPath: root.path)
        let other = try LongChatResourceLocks.canonicalKeys(["path:Sources/Other.swift"], projectID: "p", repositoryPath: root.path)
        #expect(LongChatResourceLocks.conflicts(other, with: Set(explicit)))
    }

    @Test func scopesRespectAncestorsAndSegmentBoundaries() {
        #expect(LongChatResourceLocks.conflicts(["path:/repo/Sources/View.swift"], with: ["path:/repo/Sources"]))
        #expect(LongChatResourceLocks.conflicts(["path:/repo/Sources"], with: ["path:/repo/Sources/View.swift"]))
        #expect(!LongChatResourceLocks.conflicts(["path:/repo/SourcesOther/View.swift"], with: ["path:/repo/Sources"]))
        #expect(!LongChatResourceLocks.conflicts(["path:/repo/A.swift"], with: ["path:/repo/B.swift"]))
        #expect(LongChatResourceLocks.conflicts(["path:/repo/A.swift"], with: ["workspace:/repo"]))
        #expect(LongChatResourceLocks.conflicts(["workspace:/repo"], with: ["path:/repo/A.swift"]))
        #expect(LongChatResourceLocks.conflicts(["path:/repo/A.swift"], with: ["workspace:/"]))
        #expect(LongChatResourceLocks.conflicts(["path:/repo/Sources/A.swift"], with: ["path:/repo/sources/a.swift"]))
        #expect(LongChatResourceLocks.conflicts(["ticket:123"], with: ["ticket:123"]))
    }

    @Test func scopesCanonicalizeAliasesAndRejectCheckoutEscapes() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = parent.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Alias"), withDestinationURL: root.appendingPathComponent("Sources"))
        let direct = try LongChatResourceLocks.canonicalKeys(["path:Sources/New.swift"], projectID: "p", repositoryPath: root.path)
        let alias = try LongChatResourceLocks.canonicalKeys(["path:Alias/./New.swift"], projectID: "p", repositoryPath: root.path)
        #expect(direct == alias)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Outside"), withDestinationURL: parent)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Dangling"), withDestinationURL: parent.appendingPathComponent("missing"))
        for path in ["../escape.swift", "Outside/escape.swift", "Outside/../escape.swift", "Dangling/new.swift", ""] {
            #expect(throws: LongChatDelegationDecoder.ValidationError.self) {
                try LongChatResourceLocks.canonicalKeys(["path:" + path], projectID: "p", repositoryPath: root.path)
            }
        }
        #expect(throws: LongChatDelegationDecoder.ValidationError.self) {
            try LongChatResourceLocks.canonicalKeys(["path:Sources/A.swift"], projectID: nil, repositoryPath: nil)
        }
    }

    @Test func globalLocksHoldOverlapsUntilExecutionStopsAndSurviveReload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LongChatFileStore(root: root)
        try store.transaction { state in
            state.conversations = ["first", "second"].map { .init(agentId: "a", userId: "u", sessionId: $0, assignments: []) }
        }
        let first = try store.delegate(sessionId: "first", sourceMessageId: "one", request: request([
            task("source", scopes: ["path:/repo/Sources"]),
        ]))
        try store.updateTask(sessionId: "first", taskId: first.tasks[0].id) { $0.attempts[0].status = .running }
        _ = try store.delegate(sessionId: "second", sourceMessageId: "two", request: request([
            task("overlap", scopes: ["path:/repo/Sources/A.swift"]),
            task("independent", scopes: ["path:/repo/Tests/A.swift"]),
            task("third", scopes: ["path:/repo/Docs"]),
            task("fourth", scopes: ["path:/repo/Assets"]),
            task("fifth", scopes: ["path:/repo/More"]),
        ]))
        #expect(try store.runnableTasks(sessionId: "second").map(\.task.key) == ["independent", "third", "fourth"])
        try store.updateTask(sessionId: "first", taskId: first.tasks[0].id) {
            $0.attempts[0].status = .cancelled
            $0.attempts[0].executionStopped = false
        }
        let restored = try LongChatFileStore(root: root)
        #expect(try restored.runnableTasks(sessionId: "second").map(\.task.key) == ["independent", "third", "fourth"])
        try restored.updateTask(sessionId: "first", taskId: first.tasks[0].id) { $0.attempts[0].executionStopped = true }
        #expect(try restored.runnableTasks(sessionId: "second").map(\.task.key) == ["overlap", "independent", "third"])
    }

    @Test func dependencyStillWaitsDespiteDisjointFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LongChatFileStore(root: root)
        try store.transaction { $0.conversations = [.init(agentId: "a", userId: "u", sessionId: "s", assignments: [])] }
        var dependent = task("integration", scopes: ["path:/repo/Integration.swift"])
        dependent.dependsOn = ["implementation"]
        let assignment = try store.delegate(sessionId: "s", sourceMessageId: "one", request: request([
            task("implementation", scopes: ["path:/repo/Feature.swift"]), dependent,
        ]))
        #expect(try store.runnableTasks(sessionId: "s").map(\.task.key) == ["implementation"])
        try store.updateTask(sessionId: "s", taskId: assignment.tasks[0].id) { $0.attempts[0].status = .completed }
        #expect(try store.runnableTasks(sessionId: "s").map(\.task.key) == ["integration"])
    }

    @Test func threeSameProjectWorkersReachTheModelBeforeAnyFinishes() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let gate = ParallelWorkerGate()
        defer { Task { await gate.release(); await service.stop() } }
        await service.waitForStartup()
        _ = try await service.createAgent(.init(id: "parallel-agent", displayName: "Parallel", role: "Test"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await service.createProject(.init(id: "parallel-project", name: "Parallel", repoPath: root.path))
        let chat = try await service.openLongChat(agentID: "parallel-agent", userID: "local", projectID: "parallel-project")
        await service.installParallelWorkerTestProvider(gate)
        let assignment = try await service.delegateLongChat(agentID: "parallel-agent", sessionID: chat.id, sourceID: "source",
            request: request((0..<4).map { index in
                .init(key: "job-\(index)", title: "Job \(index)", objective: "PARALLEL_FIXTURE_\(index)",
                    resourceKeys: ["path:Sources/Feature\(index).swift"], readOnly: false)
            }))
        for _ in 0..<100 {
            if await gate.started >= 3 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(await gate.started == 3)
        let state = try await service.getLongChat(agentID: "parallel-agent", sessionID: chat.id)
        let tasks = try #require(state.assignments.first { $0.id == assignment.id }?.tasks)
        #expect(tasks.filter { $0.status == .running }.count == 3)
        #expect(tasks.filter { $0.status == .queued }.count == 1)
        #expect(Set(tasks.compactMap { $0.attempts.last?.sessionId }).count == 3)
        #expect(tasks.allSatisfy { $0.projectId == "parallel-project" && $0.resourceKeys.allSatisfy { $0.hasPrefix("path:") } })
        try await service.cancelLongChatTasks(agentID: "parallel-agent", sessionID: chat.id)
        await gate.release()
        await service.stop()
    }

    private func task(_ key: String, scopes: [String]) -> LongChatTaskRequest {
        .init(key: key, title: key, objective: "Edit declared source scope", resourceKeys: scopes, readOnly: false)
    }

    private func request(_ tasks: [LongChatTaskRequest]) -> LongChatDelegationRequest {
        .init(requestKey: "parallel", title: "Parallel changes", acceptanceCriteria: "Verify all tasks", tasks: tasks)
    }
}

fileprivate actor ParallelWorkerGate {
    private(set) var started = 0
    private var released = false
    func enter() async throws {
        started += 1
        while !released {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    func release() { released = true }
}

private struct ParallelWorkerModel: LanguageModel {
    typealias UnavailableReason = Never
    let gate: ParallelWorkerGate
    func respond<Content>(within session: LanguageModelSession, to prompt: Prompt, generating type: Content.Type,
        includeSchemaInPrompt: Bool, options: GenerationOptions) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        if prompt.description.contains("PARALLEL_FIXTURE_") { try await gate.enter() }
        let text = "Fixture finished."
        return .init(content: text as! Content, rawContent: GeneratedContent(text), transcriptEntries: [])
    }
    func streamResponse<Content>(within session: LanguageModelSession, to prompt: Prompt, generating type: Content.Type,
        includeSchemaInPrompt: Bool, options: GenerationOptions) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        let stream = AsyncThrowingStream<LanguageModelSession.ResponseStream<Content>.Snapshot, any Error> { continuation in
            let task = Task {
                do {
                    let response = try await respond(within: session, to: prompt, generating: type, includeSchemaInPrompt: includeSchemaInPrompt, options: options)
                    continuation.yield(.init(content: response.content.asPartiallyGenerated(), rawContent: response.rawContent))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return .init(stream: stream)
    }
}

private struct ParallelWorkerProvider: ModelProvider {
    let id = "parallel-worker-fixture"
    let supportedModels = ["mock:test-model"]
    let gate: ParallelWorkerGate
    func createLanguageModel(for modelName: String) async throws -> any LanguageModel { ParallelWorkerModel(gate: gate) }
}

extension CoreService {
    fileprivate func installParallelWorkerTestProvider(_ gate: ParallelWorkerGate) async {
        let provider = ParallelWorkerProvider(gate: gate)
        modelProvider = provider
        await runtime.updateModelProvider(modelProvider: provider, defaultModel: "mock:test-model")
    }
}
