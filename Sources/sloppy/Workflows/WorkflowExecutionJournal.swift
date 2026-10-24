import Foundation
import Protocols

struct WorkflowExecutionState: Codable, Sendable {
    var schemaVersion = 1
    var definition: WorkflowDefinition
    var originalInput: [String: JSONValue]
    var run: WorkflowRun
    var steps: [WorkflowRunStep] = []
    var actions: [WorkflowPendingAction] = []
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

    func list() throws -> [WorkflowExecutionState] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.compactMap { try load($0.deletingPathExtension().lastPathComponent) }
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
    private var state: WorkflowExecutionState
    private let files: WorkflowExecutionFileStore
    private let store: any PersistenceStore
    private(set) var failed = false

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

    func flush() async throws {
        try commit()
        await store.saveWorkflowRun(state.run)
        for step in state.steps { await store.saveWorkflowRunStep(step) }
        for action in state.actions { await store.saveWorkflowPendingAction(action) }
    }

    func resolve(actionID: String, output: [String: JSONValue]) async throws {
        guard let index = state.actions.firstIndex(where: { $0.id == actionID && $0.resolvedAt == nil }),
              let stepIndex = state.steps.lastIndex(where: { $0.nodeId == state.actions[index].nodeId && $0.status == .waiting })
        else { throw CoreService.WorkflowError.actionNotFound }
        state.actions[index].resolvedAt = Date()
        state.steps[stepIndex].status = .succeeded
        state.steps[stepIndex].output = output
        state.steps[stepIndex].finishedAt = Date()
        state.run.status = .running
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
        try commit()
        await store.saveWorkflowRunStep(step)
    }

    private func save(action: WorkflowPendingAction) async throws {
        if let index = state.actions.firstIndex(where: { $0.id == action.id }) { state.actions[index] = action }
        else { state.actions.append(action) }
        try commit()
        await store.saveWorkflowPendingAction(action)
    }

    private func commit() throws {
        guard !failed else { throw CoreService.WorkflowError.storageFailure }
        do { try files.save(state) }
        catch { failed = true; throw error }
    }
}
