import AgentRuntime
import Foundation
import Protocols

/// Bridge executor that allows Core to plug worker execution into ToolExecutionService.
/// Current implementation preserves existing behavior via DefaultWorkerExecutor fallback.
final class ToolExecutionWorkerExecutorAdapter: @unchecked Sendable, WorkerExecutor {
    private let toolExecutionService: ToolExecutionService
    private let fallback: any WorkerExecutor

    init(
        toolExecutionService: ToolExecutionService,
        fallback: any WorkerExecutor = DefaultWorkerExecutor()
    ) {
        self.toolExecutionService = toolExecutionService
        self.fallback = fallback
    }

    func execute(workerId: String, spec: WorkerTaskSpec) async throws -> WorkerExecutionResult {
        _ = toolExecutionService
        return try await fallback.execute(workerId: workerId, spec: spec)
    }

    func route(workerId: String, spec: WorkerTaskSpec, message: String) async throws -> WorkerRouteExecutionResult {
        return try await fallback.route(workerId: workerId, spec: spec, message: message)
    }

    func cancel(workerId: String, spec: WorkerTaskSpec) async {
        await fallback.cancel(workerId: workerId, spec: spec)
    }
}
