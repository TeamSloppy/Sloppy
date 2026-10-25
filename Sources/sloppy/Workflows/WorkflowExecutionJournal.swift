import Foundation
import Protocols

struct WorkflowExecutionState: Codable, Sendable {
    var schemaVersion = 1
    var resumeAfterShutdown: Bool? = nil
    var definition: WorkflowDefinition
    var originalInput: [String: JSONValue]
    var run: WorkflowRun
    var steps: [WorkflowRunStep] = []
    var actions: [WorkflowPendingAction] = []
    var parallel: WorkflowParallelState? = nil

    var runnable: Self {
        guard let parallel, let parent = steps.first(where: { $0.id == parallel.stepID }) else { return self }
        var copy = self
        copy.run.currentNodeIds = [parallel.nodeID]
        copy.run.status = .running
        copy.steps.removeAll { $0.id == parent.id }
        copy.steps.append(parent)
        return copy
    }
}

struct WorkflowParallelState: Codable, Sendable {
    var nodeID: String
    var stepID: String
    var branches: [WorkflowParallelBranch]
    var visitCounts: [String: Int]
}

struct WorkflowParallelBranch: Codable, Sendable {
    var id: String
    var run: WorkflowRun
    var steps: [WorkflowRunStep] = []
    var actions: [WorkflowPendingAction] = []
    var failure: String? = nil
    var failureCode: String? = nil
}

struct WorkflowExecutionFileStore: Sendable {
    let root: URL

    func load(_ id: String) throws -> WorkflowExecutionState? {
        let url = try location(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let state = try JSONDecoder().decode(WorkflowExecutionState.self, from: Data(contentsOf: url))
        guard state.schemaVersion == 1, state.run.id == id,
              state.definition.id == state.run.workflowId,
              state.definition.projectId == state.run.projectId,
              state.definition.version == state.run.workflowVersion else { throw CoreService.WorkflowError.invalidPayload }
        return state
    }

    func save(_ state: WorkflowExecutionState) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: location(state.run.id), options: .atomic)
    }

    func identifiers() throws -> [String] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent }
    }

    private func location(_ id: String) throws -> URL {
        guard !id.isEmpty, id != ".", id != "..", !id.contains("/"), !id.contains("\\") else {
            throw CoreService.WorkflowError.invalidPayload
        }
        return root.appendingPathComponent(id).appendingPathExtension("json")
    }
}

// The atomic file is authoritative. SQLite is updated only after the checkpoint succeeds.
actor WorkflowExecutionJournal {
    var state: WorkflowExecutionState
    private let files: WorkflowExecutionFileStore
    private let store: any PersistenceStore
    private(set) var failed = false
    private(set) var suspended = false
    private var parallelInputRevision = 0
    private var parallelInputWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    init(state: WorkflowExecutionState, files: WorkflowExecutionFileStore, store: any PersistenceStore) {
        self.state = state
        self.files = files
        self.store = store
    }

    var persistence: WorkflowRunner.Persistence {
        .init(saveRun: { try await self.save(run: $0) },
              saveStep: { try await self.save(step: $0) },
              saveAction: { try await self.save(action: $0) })
    }

    func snapshot() -> WorkflowExecutionState { state }

    func parallelInputVersion() -> Int { parallelInputRevision }

    func signalParallelInput() {
        parallelInputRevision += 1
        let waiters = parallelInputWaiters.values
        parallelInputWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    func waitForParallelInput(after revision: Int) async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled || suspended || revision != parallelInputRevision { continuation.resume() }
                else { parallelInputWaiters[id] = continuation }
            }
        } onCancel: { Task { await self.cancelParallelWaiter(id) } }
    }

    private func cancelParallelWaiter(_ id: UUID) { parallelInputWaiters.removeValue(forKey: id)?.resume() }

    func persistParallelChange(step: WorkflowRunStep? = nil, action: WorkflowPendingAction? = nil) async throws {
        try commit()
        await store.saveWorkflowRun(state.run)
        if let step, let current = state.steps.first(where: { $0.id == step.id }) { await store.saveWorkflowRunStep(current) }
        if let action, let current = state.actions.first(where: { $0.id == action.id }) { await store.saveWorkflowPendingAction(current) }
    }

    func flush() async throws {
        try commit()
        await store.saveWorkflowRun(state.run)
        for id in state.steps.map(\.id) {
            if let current = state.steps.first(where: { $0.id == id }) { await store.saveWorkflowRunStep(current) }
        }
        for id in state.actions.map(\.id) {
            if let current = state.actions.first(where: { $0.id == id }) { await store.saveWorkflowPendingAction(current) }
        }
    }

    func resolve(actionID: String, output: [String: JSONValue]) async throws {
        guard let index = state.actions.firstIndex(where: { $0.id == actionID && $0.resolvedAt == nil }),
              let stepIndex = state.steps.lastIndex(where: { $0.nodeId == state.actions[index].nodeId && $0.status == .waiting })
        else { throw CoreService.WorkflowError.actionNotFound }
        state.actions[index].resolvedAt = Date()
        state.steps[stepIndex].status = .succeeded
        state.steps[stepIndex].output = output
        state.steps[stepIndex].finishedAt = Date()
        if var parallel = state.parallel {
            for index in parallel.branches.indices {
                if let actionIndex = parallel.branches[index].actions.firstIndex(where: { $0.id == actionID }) {
                    parallel.branches[index].actions[actionIndex].resolvedAt = state.actions.first { $0.id == actionID }?.resolvedAt
                    if let attempt = parallel.branches[index].steps.firstIndex(where: { $0.id == state.steps[stepIndex].id }) {
                        var step = state.steps[stepIndex]
                        step.runId = parallel.branches[index].run.id
                        parallel.branches[index].steps[attempt] = step
                    }
                    parallel.branches[index].run.status = .running
                }
            }
            state.parallel = parallel
        }
        state.run.status = .running
        try await flush()
    }

    func recordAgentResult(stepID: String, result: ToolInvocationResult) async throws {
        guard let index = state.steps.firstIndex(where: { $0.id == stepID }) else { throw CoreService.WorkflowError.invalidPayload }
        let waiting = WorkflowAgentOutcome.isWaiting(result)
        state.steps[index].output = result.data?.asObject ?? [:]
        if result.ok {
            state.steps[index].output["status"] = .string("succeeded")
            state.steps[index].output["tool"] = .string(result.tool)
        }
        state.steps[index].status = result.ok ? .succeeded : waiting ? .waiting : .failed
        state.steps[index].error = result.ok || waiting ? nil : result.error?.message
        state.steps[index].finishedAt = waiting ? nil : Date()
        state.run.status = result.ok ? .running : waiting ? .waitingForAgent : .failed
        if !result.ok && !waiting { state.run.finishedAt = Date() }
        try await flush()
    }

    private func save(run: WorkflowRun) async throws {
        state.run = run
        try commit()
        await store.saveWorkflowRun(run)
    }

    private func save(step: WorkflowRunStep) async throws {
        if let index = state.steps.firstIndex(where: { $0.id == step.id }) { state.steps[index] = step }
        else { state.steps.append(step) }
        if state.parallel?.stepID == step.id, step.status == .succeeded || step.status == .failed {
            state.parallel = nil
            state.steps.removeAll { $0.id == step.id }
            state.steps.append(step)
        }
        try commit()
        await store.saveWorkflowRunStep(step)
    }

    private func save(action: WorkflowPendingAction) async throws {
        if let index = state.actions.firstIndex(where: { $0.id == action.id }) { state.actions[index] = action }
        else { state.actions.append(action) }
        try commit()
        await store.saveWorkflowPendingAction(action)
    }

    func suspend() throws {
        defer { suspended = true; signalParallelInput() }
        state.resumeAfterShutdown = true
        try commit()
    }

    private func commit() throws {
        guard !suspended else { throw CancellationError() }
        guard !failed else { throw CoreService.WorkflowError.storageFailure }
        do { try files.save(state) }
        catch { failed = true; throw error }
    }
}

enum WorkflowAgentOutcome {
    static func isWaiting(_ result: ToolInvocationResult) -> Bool {
        let output = result.data?.asObject
        let outcome = output?["agentOutcome"]?.asString.flatMap(ExecutionState.init(rawValue:))
        if let outcome { return outcome == .waitingInput || outcome == .waitingApproval }
        let stage = output?["agentStage"]?.asString.flatMap(AgentRunStage.init(rawValue:))
        return stage == .thinking || stage == .searching || stage == .responding || stage == .paused
    }
}
