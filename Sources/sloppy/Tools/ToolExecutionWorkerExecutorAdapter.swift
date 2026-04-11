import AgentRuntime
import Foundation
import Protocols

struct AgentRunnerModelError: Error, LocalizedError {
    let detail: String
    var errorDescription: String? { detail }
}

/// Bridge executor that plugs worker execution into the agent session orchestrator.
/// When the worker spec carries an agentID, execution is delegated to the agent runner closure
/// which creates a dedicated session, posts the task objective, and returns the assistant response.
/// Workers without an agentID fall back to DefaultWorkerExecutor.
final class ToolExecutionWorkerExecutorAdapter: @unchecked Sendable, WorkerExecutor {
    typealias AgentRunner = @Sendable (_ agentID: String, _ taskID: String, _ objective: String, _ workingDirectory: String?, _ selectedModel: String?) async -> String?

    private let fallback: any WorkerExecutor
    private let agentRunner: AgentRunner?

    init(
        toolExecutionService: ToolExecutionService,
        fallback: any WorkerExecutor = DefaultWorkerExecutor(),
        agentRunner: AgentRunner? = nil
    ) {
        _ = toolExecutionService
        self.fallback = fallback
        self.agentRunner = agentRunner
    }

    func execute(workerId: String, spec: WorkerTaskSpec) async throws -> WorkerExecutionResult {
        if let agentID = spec.agentID, let runner = agentRunner {
            let result = await runner(agentID, spec.taskId, spec.objective, spec.workingDirectory, spec.selectedModel)
            if let result, Self.isModelProviderError(result) {
                throw AgentRunnerModelError(detail: result)
            }
            return .completed(summary: result ?? spec.objective)
        }
        return try await fallback.execute(workerId: workerId, spec: spec)
    }

    static func isModelProviderError(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("model provider error:")
    }

    func route(workerId: String, spec: WorkerTaskSpec, message: String) async throws -> WorkerRouteExecutionResult {
        return try await fallback.route(workerId: workerId, spec: spec, message: message)
    }

    func cancel(workerId: String, spec: WorkerTaskSpec) async {
        await fallback.cancel(workerId: workerId, spec: spec)
    }
}
