import Foundation
import Protocols

public enum WorkerExecutionResult: Sendable, Equatable {
    case completed(summary: String)
    case waitingForRoute(report: String?)
}

public enum WorkerRouteExecutionResult: Sendable, Equatable {
    case waitingForRoute(report: String?)
    case completed(summary: String)
    case failed(error: String)
}

public protocol WorkerExecutor: Sendable {
    func execute(workerId: String, spec: WorkerTaskSpec) async throws -> WorkerExecutionResult
    func route(workerId: String, spec: WorkerTaskSpec, message: String) async throws -> WorkerRouteExecutionResult
    func cancel(workerId: String, spec: WorkerTaskSpec) async
}

public struct DefaultWorkerExecutor: WorkerExecutor {
    public init() {}

    public func execute(workerId: String, spec: WorkerTaskSpec) async throws -> WorkerExecutionResult {
        switch spec.mode {
        case .fireAndForget:
            let summary = spec.objective.trimmingCharacters(in: .whitespacesAndNewlines)
            if summary.isEmpty == false {
                return .completed(summary: summary)
            }
            return .completed(summary: spec.title)

        case .interactive:
            return .waitingForRoute(report: nil)
        }
    }

    public func route(workerId: String, spec: WorkerTaskSpec, message: String) async throws -> WorkerRouteExecutionResult {
        guard let command = decodeRouteCommand(message) else {
            return .waitingForRoute(report: nil)
        }

        switch command.command {
        case .continue:
            return .waitingForRoute(report: normalized(command.report))
        case .complete:
            if let summary = normalized(command.summary) {
                return .completed(summary: summary)
            }
            return .failed(error: "Structured worker completion requires `summary`.")
        case .fail:
            if let error = normalized(command.error) {
                return .failed(error: error)
            }
            return .failed(error: "Structured worker failure requires `error`.")
        }
    }

    public func cancel(workerId: String, spec: WorkerTaskSpec) async {}

    private func decodeRouteCommand(_ message: String) -> WorkerRouteCommand? {
        guard let data = message.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(WorkerRouteCommand.self, from: data)
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
