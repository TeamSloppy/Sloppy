import Foundation
import Protocols

public enum WorkerStatus: String, Codable, Sendable {
    case queued
    case running
    case waitingInput
    case completed
    case failed
}

public struct WorkerSnapshot: Codable, Sendable, Equatable {
    public var workerId: String
    public var channelId: String
    public var taskId: String
    public var status: WorkerStatus
    public var mode: WorkerMode
    public var tools: [String]
    public var latestReport: String?
    public var startedAt: Date?

    public init(
        workerId: String,
        channelId: String,
        taskId: String,
        status: WorkerStatus,
        mode: WorkerMode,
        tools: [String],
        latestReport: String?,
        startedAt: Date? = nil
    ) {
        self.workerId = workerId
        self.channelId = channelId
        self.taskId = taskId
        self.status = status
        self.mode = mode
        self.tools = tools
        self.latestReport = latestReport
        self.startedAt = startedAt
    }

    enum CodingKeys: String, CodingKey {
        case workerId
        case channelId
        case taskId
        case status
        case mode
        case tools
        case latestReport
        case startedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workerId = try container.decode(String.self, forKey: .workerId)
        channelId = try container.decode(String.self, forKey: .channelId)
        taskId = try container.decode(String.self, forKey: .taskId)
        status = try container.decode(WorkerStatus.self, forKey: .status)
        mode = try container.decode(WorkerMode.self, forKey: .mode)
        tools = try container.decode([String].self, forKey: .tools)
        latestReport = try container.decodeIfPresent(String.self, forKey: .latestReport)
        startedAt = try Self.decodeDateIfPresent(container: container, forKey: .startedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workerId, forKey: .workerId)
        try container.encode(channelId, forKey: .channelId)
        try container.encode(taskId, forKey: .taskId)
        try container.encode(status, forKey: .status)
        try container.encode(mode, forKey: .mode)
        try container.encode(tools, forKey: .tools)
        try container.encodeIfPresent(latestReport, forKey: .latestReport)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
    }

    private static func decodeDateIfPresent(
        container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Date? {
        if let date = try? container.decodeIfPresent(Date.self, forKey: key) {
            return date
        }

        guard let rawValue = try container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }

        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601Formatter.date(from: rawValue) {
            return date
        }

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        if let date = fallbackFormatter.date(from: rawValue) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Unsupported date value: \(rawValue)"
        )
    }
}

public struct WorkerRouteResult: Sendable, Equatable {
    public var accepted: Bool
    public var completed: Bool
    public var artifactRef: ArtifactRef?

    public init(accepted: Bool, completed: Bool, artifactRef: ArtifactRef?) {
        self.accepted = accepted
        self.completed = completed
        self.artifactRef = artifactRef
    }
}

private struct WorkerState: Sendable {
    var spec: WorkerTaskSpec
    var status: WorkerStatus
    var latestReport: String?
    var routeInbox: [String]
    var artifactId: String?
    var startedAt: Date?
}

public actor WorkerRuntime {
    private let eventBus: EventBus
    private var executor: any WorkerExecutor
    private var workers: [String: WorkerState] = [:]
    private var artifacts: [String: String] = [:]

    public init(eventBus: EventBus, executor: any WorkerExecutor = DefaultWorkerExecutor()) {
        self.eventBus = eventBus
        self.executor = executor
    }

    /// Replaces execution backend for subsequent worker operations.
    public func updateExecutor(_ executor: any WorkerExecutor) {
        self.executor = executor
    }

    /// Creates worker state and optionally starts execution.
    public func spawn(spec: WorkerTaskSpec, autoStart: Bool = true) async -> String {
        let workerId = UUID().uuidString
        workers[workerId] = WorkerState(spec: spec, status: .queued, latestReport: nil, routeInbox: [], artifactId: nil)

        await publish(
            channelId: spec.channelId,
            taskId: spec.taskId,
            workerId: workerId,
            messageType: .workerSpawned,
            payload: [
                "mode": .string(spec.mode.rawValue),
                "title": .string(spec.title)
            ]
        )

        if autoStart {
            Task {
                await self.execute(workerId: workerId)
            }
        }

        return workerId
    }

    /// Executes worker logic according to configured mode.
    public func execute(workerId: String) async {
        guard var state = workers[workerId] else { return }
        state.status = .running
        if state.startedAt == nil {
            state.startedAt = Date()
        }
        workers[workerId] = state

        await publish(
            channelId: state.spec.channelId,
            taskId: state.spec.taskId,
            workerId: workerId,
            messageType: .workerProgress,
            payload: ["progress": .string("worker_started")]
        )

        let executor = self.executor

        do {
            let result = try await executor.execute(workerId: workerId, spec: state.spec)
            switch result {
            case .completed(let summary):
                _ = await completeNow(workerId: workerId, summary: summary)

            case .waitingForRoute(let report):
                state.status = .waitingInput
                state.latestReport = report
                workers[workerId] = state
                await publish(
                    channelId: state.spec.channelId,
                    taskId: state.spec.taskId,
                    workerId: workerId,
                    messageType: .workerProgress,
                    payload: ["progress": .string("waiting_for_route")]
                )
            }
        } catch {
            let prefix = state.spec.mode == .fireAndForget
                ? "Fire-and-forget execution failed"
                : "Worker execution failed"
            await fail(workerId: workerId, error: "\(prefix): \(error.localizedDescription)")
        }
    }

    /// Routes interactive message into worker execution loop.
    public func route(workerId: String, message: String) async -> WorkerRouteResult {
        guard var state = workers[workerId] else {
            return WorkerRouteResult(accepted: false, completed: false, artifactRef: nil)
        }

        guard state.spec.mode == .interactive, state.status == .waitingInput || state.status == .running else {
            return WorkerRouteResult(accepted: false, completed: false, artifactRef: nil)
        }

        state.routeInbox.append(message)
        state.status = .running
        state.latestReport = "routed: \(message)"
        workers[workerId] = state

        await publish(
            channelId: state.spec.channelId,
            taskId: state.spec.taskId,
            workerId: workerId,
            messageType: .workerProgress,
            payload: ["progress": .string("received_route")]
        )

        let executor = self.executor
        do {
            let result = try await executor.route(workerId: workerId, spec: state.spec, message: message)
            switch result {
            case .waitingForRoute(let report):
                guard var latestState = workers[workerId] else {
                    return WorkerRouteResult(accepted: true, completed: false, artifactRef: nil)
                }
                latestState.status = .waitingInput
                latestState.latestReport = report ?? latestState.latestReport
                workers[workerId] = latestState
                return WorkerRouteResult(accepted: true, completed: false, artifactRef: nil)

            case .completed(let summary):
                let artifact = await completeNow(workerId: workerId, summary: summary)
                return WorkerRouteResult(accepted: true, completed: true, artifactRef: artifact)

            case .failed(let error):
                await fail(workerId: workerId, error: error)
                return WorkerRouteResult(accepted: true, completed: true, artifactRef: nil)
            }
        } catch {
            await fail(
                workerId: workerId,
                error: "Interactive route failed: \(error.localizedDescription)"
            )
            return WorkerRouteResult(accepted: true, completed: true, artifactRef: nil)
        }
    }

    /// Cancels active worker execution.
    @discardableResult
    public func cancel(workerId: String) async -> Bool {
        guard let state = workers[workerId] else {
            return false
        }
        guard state.status != .completed, state.status != .failed else {
            return false
        }

        let executor = self.executor
        await executor.cancel(workerId: workerId, spec: state.spec)
        await fail(workerId: workerId, error: "Worker cancelled")
        return true
    }

    /// Completes worker immediately with summary artifact.
    public func completeNow(workerId: String, summary: String) async -> ArtifactRef? {
        guard var state = workers[workerId] else { return nil }

        state.status = .completed
        state.latestReport = summary
        let artifactId = UUID().uuidString
        state.artifactId = artifactId
        workers[workerId] = state

        artifacts[artifactId] = summary
        let ref = ArtifactRef(id: artifactId, kind: "text", preview: String(summary.prefix(120)))

        await publish(
            channelId: state.spec.channelId,
            taskId: state.spec.taskId,
            workerId: workerId,
            messageType: .workerCompleted,
            payload: [
                "summary": .string(summary),
                "artifactId": .string(artifactId)
            ]
        )

        return ref
    }

    /// Marks worker as failed and emits failure event.
    public func fail(workerId: String, error: String) async {
        guard var state = workers[workerId] else { return }
        state.status = .failed
        state.latestReport = error
        workers[workerId] = state

        await publish(
            channelId: state.spec.channelId,
            taskId: state.spec.taskId,
            workerId: workerId,
            messageType: .workerFailed,
            payload: ["error": .string(error)]
        )
    }

    /// Returns snapshot for a specific worker.
    public func snapshot(workerId: String) -> WorkerSnapshot? {
        guard let state = workers[workerId] else { return nil }
        return WorkerSnapshot(
            workerId: workerId,
            channelId: state.spec.channelId,
            taskId: state.spec.taskId,
            status: state.status,
            mode: state.spec.mode,
            tools: state.spec.tools,
            latestReport: state.latestReport,
            startedAt: state.startedAt
        )
    }

    /// Returns snapshots for all workers.
    public func snapshots() -> [WorkerSnapshot] {
        workers.map { workerId, state in
            WorkerSnapshot(
                workerId: workerId,
                channelId: state.spec.channelId,
                taskId: state.spec.taskId,
                status: state.status,
                mode: state.spec.mode,
                tools: state.spec.tools,
                latestReport: state.latestReport,
                startedAt: state.startedAt
            )
        }
    }

    /// Returns stored artifact content by identifier.
    public func artifactContent(id: String) -> String? {
        artifacts[id]
    }

    /// Clears worker and artifact maps before recovery replay.
    public func resetForRecovery() {
        workers.removeAll()
        artifacts.removeAll()
    }

    /// Restores artifact payload from persistence.
    public func restoreArtifact(id: String, content: String) {
        artifacts[id] = content
    }

    /// Restores worker state from persistence without emitting lifecycle events.
    public func restoreWorker(
        workerId: String,
        spec: WorkerTaskSpec,
        status: WorkerStatus,
        latestReport: String?,
        artifactId: String?
    ) {
        workers[workerId] = WorkerState(
            spec: spec,
            status: status,
            latestReport: latestReport,
            routeInbox: [],
            artifactId: artifactId,
            startedAt: nil
        )
    }

    /// Mutates restored worker state during replay.
    public func updateRecoveredWorker(
        workerId: String,
        status: WorkerStatus,
        latestReport: String?,
        artifactId: String?
    ) -> Bool {
        guard var state = workers[workerId] else {
            return false
        }
        state.status = status
        state.latestReport = latestReport ?? state.latestReport
        if let artifactId {
            state.artifactId = artifactId
        }
        workers[workerId] = state
        return true
    }

    /// Returns true when worker exists in restored state.
    public func hasWorker(workerId: String) -> Bool {
        workers[workerId] != nil
    }

    /// Returns true when any worker is associated with task identifier.
    public func hasTask(taskId: String) -> Bool {
        workers.values.contains(where: { $0.spec.taskId == taskId })
    }

    private func publish(
        channelId: String,
        taskId: String,
        workerId: String,
        messageType: MessageType,
        payload: [String: JSONValue]
    ) async {
        let envelope = EventEnvelope(
            messageType: messageType,
            channelId: channelId,
            taskId: taskId,
            workerId: workerId,
            payload: .object(payload)
        )
        await eventBus.publish(envelope)
    }
}
