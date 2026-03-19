import AnyLanguageModel
import Foundation
import Logging
import PluginSDK
import Protocols

public struct RecoveryChannelState: Sendable, Equatable {
    public var id: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct RecoveryTaskState: Sendable, Equatable {
    public var id: String
    public var channelId: String
    public var status: String
    public var title: String
    public var objective: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        channelId: String,
        status: String,
        title: String,
        objective: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.channelId = channelId
        self.status = status
        self.title = title
        self.objective = objective
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct RecoveryArtifactState: Sendable, Equatable {
    public var id: String
    public var content: String
    public var createdAt: Date

    public init(id: String, content: String, createdAt: Date) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
    }
}

public enum RuntimeResponseObservation: Sendable {
    case thinking(String)
    case toolCall(ToolInvocationRequest)
    case toolResult(ToolInvocationResult)
}

public struct BranchExecutionResult: Sendable, Equatable {
    public var branchId: String
    public var workerId: String
    public var conclusion: BranchConclusion

    public init(branchId: String, workerId: String, conclusion: BranchConclusion) {
        self.branchId = branchId
        self.workerId = workerId
        self.conclusion = conclusion
    }
}

public actor RuntimeSystem {
    public nonisolated let eventBus: EventBus

    private let memoryStore: any MemoryStore
    private let channels: ChannelRuntime
    private let workers: WorkerRuntime
    private let branches: BranchRuntime
    private let compactor: Compactor
    private let visor: Visor
    private let logger: Logger
    private var modelProvider: (any ModelProvider)?
    private var defaultModel: String?

    public init(
        modelProvider: (any ModelProvider)? = nil,
        defaultModel: String? = nil,
        workerExecutor: (any WorkerExecutor)? = nil,
        memoryStore: (any MemoryStore)? = nil,
        visorCompletionProvider: (@Sendable (String, Int) async -> String?)? = nil,
        visorStreamingProvider: (@Sendable (String, Int) -> AsyncStream<String>)? = nil,
        visorBulletinMaxWords: Int = 300
    ) {
        let bus = EventBus()
        let memory = memoryStore ?? InMemoryMemoryStore()
        self.eventBus = bus
        self.memoryStore = memory
        self.channels = ChannelRuntime(eventBus: bus)
        self.workers = WorkerRuntime(
            eventBus: bus,
            executor: workerExecutor ?? DefaultWorkerExecutor()
        )
        self.branches = BranchRuntime(eventBus: bus, memoryStore: memory)
        self.compactor = Compactor(eventBus: bus)
        self.visor = Visor(
            eventBus: bus,
            memoryStore: memory,
            completionProvider: visorCompletionProvider,
            streamingProvider: visorStreamingProvider,
            bulletinMaxWords: visorBulletinMaxWords
        )
        self.logger = Logger(label: "sloppy.runtime.model")
        self.modelProvider = modelProvider
        self.defaultModel = defaultModel ?? modelProvider?.supportedModels.first
    }

    /// Hot-swaps worker executor backend for subsequent worker operations.
    public func updateWorkerExecutor(_ executor: any WorkerExecutor) async {
        await workers.updateExecutor(executor)
    }

    /// Hot-swaps model provider and default model for subsequent direct responses.
    public func updateModelProvider(modelProvider: (any ModelProvider)?, defaultModel: String?) {
        self.modelProvider = modelProvider

        guard let modelProvider else {
            self.defaultModel = nil
            return
        }

        let normalizedDefault = defaultModel?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedDefault, !normalizedDefault.isEmpty, modelProvider.supportedModels.contains(normalizedDefault) {
            self.defaultModel = normalizedDefault
            return
        }

        self.defaultModel = modelProvider.supportedModels.first
    }

    /// Posts channel message and executes route-specific orchestration flow.
    public func postMessage(
        channelId: String,
        request: ChannelMessageRequest,
        onResponseChunk: (@Sendable (String) async -> Bool)? = nil,
        toolInvoker: (@Sendable (ToolInvocationRequest) async -> ToolInvocationResult)? = nil,
        observationHandler: (@Sendable (RuntimeResponseObservation) async -> Void)? = nil
    ) async -> ChannelRouteDecision {
        let ingest = await channels.ingest(channelId: channelId, request: request)

        switch ingest.decision.action {
        case .respond:
            await respondInline(
                channelId: channelId,
                userMessage: request.content,
                model: request.model,
                reasoningEffort: request.reasoningEffort,
                onResponseChunk: onResponseChunk,
                toolInvoker: toolInvoker,
                observationHandler: observationHandler
            )

        case .spawnBranch:
            _ = await executeBranch(
                channelId: channelId,
                prompt: request.content
            )

        case .spawnWorker:
            let spec = WorkerTaskSpec(
                taskId: UUID().uuidString,
                channelId: channelId,
                title: "Channel worker",
                objective: request.content,
                tools: ["shell", "file", "exec", "browser"],
                mode: .interactive
            )
            let workerId = await workers.spawn(spec: spec, autoStart: true)
            await channels.attachWorker(channelId: channelId, workerId: workerId)
        }

        if let job = await compactor.evaluate(channelId: channelId, utilization: ingest.contextUtilization) {
            await compactor.apply(job: job, workers: workers)
            await channels.appendSystemMessage(channelId: channelId, content: "Compactor scheduled \(job.level.rawValue) policy")
        }

        return ingest.decision
    }

    public func executeBranch(
        channelId: String,
        prompt: String,
        title: String = "Branch analysis"
    ) async -> BranchExecutionResult? {
        let branchId = await branches.spawn(channelId: channelId, prompt: prompt)
        let spec = WorkerTaskSpec(
            taskId: "branch-\(branchId)",
            channelId: channelId,
            title: title,
            objective: prompt,
            tools: ["shell", "file", "exec"],
            mode: .fireAndForget
        )
        let workerId = await workers.spawn(spec: spec, autoStart: false)
        await branches.attachWorker(branchId: branchId, workerId: workerId)
        await channels.attachWorker(channelId: channelId, workerId: workerId)

        let artifact = await workers.completeNow(workerId: workerId, summary: "Branch worker completed objective")
        await channels.detachWorker(channelId: channelId, workerId: workerId)

        guard let conclusion = await branches.conclude(
            branchId: branchId,
            summary: "Branch finished with focused conclusion",
            artifactRefs: artifact.map { [$0] } ?? [],
            tokenUsage: TokenUsage(prompt: 300, completion: 120)
        ) else {
            return nil
        }

        await channels.applyBranchConclusion(channelId: channelId, conclusion: conclusion)
        return BranchExecutionResult(
            branchId: branchId,
            workerId: workerId,
            conclusion: conclusion
        )
    }

    /// Uses configured model provider for direct responses or falls back to static response.
    private func respondInline(
        channelId: String,
        userMessage: String,
        model: String?,
        reasoningEffort: ReasoningEffort?,
        onResponseChunk: (@Sendable (String) async -> Bool)?,
        toolInvoker: (@Sendable (ToolInvocationRequest) async -> ToolInvocationResult)?,
        observationHandler: (@Sendable (RuntimeResponseObservation) async -> Void)?
    ) async {
        let normalizedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeModel = (normalizedModel?.isEmpty == false ? normalizedModel : nil) ?? defaultModel

        guard let modelProvider, let activeModel else {
            let fallback = "Responded inline"
            if let observationHandler {
                await observationHandler(.thinking("Using fallback inline response because no model provider is configured."))
            }
            if let onResponseChunk {
                _ = await onResponseChunk(fallback)
            }
            await channels.appendSystemMessage(channelId: channelId, content: fallback)
            return
        }

        do {
            let contextualPrompt = await buildContextualPrompt(
                channelId: channelId,
                fallbackUserMessage: userMessage
            )
            let promptChars = contextualPrompt.description.count

            let languageModel = try await modelProvider.createLanguageModel(for: activeModel)
            let session: LanguageModelSession
            if let instructions = modelProvider.systemInstructions {
                session = LanguageModelSession(model: languageModel, tools: modelProvider.tools, instructions: instructions)
            } else {
                session = LanguageModelSession(model: languageModel, tools: modelProvider.tools)
            }

            if let invoker = toolInvoker {
                let observingHandler: @Sendable (ToolInvocationRequest) async -> ToolInvocationResult = { request in
                    if let observationHandler {
                        await observationHandler(.toolCall(request))
                    }
                    let result = await invoker(request)
                    if let observationHandler {
                        await observationHandler(.toolResult(result))
                    }
                    return result
                }
                session.toolExecutionDelegate = SloppyToolExecutionDelegate(toolCallHandler: observingHandler)
            }

            let options = modelProvider.generationOptions(for: activeModel, maxTokens: 1024, reasoningEffort: reasoningEffort)
            var latest = ""
            var streamChunks = 0
            let streamStartedAt = Date()
            let streamMode = toolInvoker != nil ? "native_tool_stream" : "respond_stream"

            logger.info(
                "Model stream started",
                metadata: modelCallMetadata(
                    channelId: channelId,
                    model: activeModel,
                    reasoningEffort: reasoningEffort,
                    promptChars: promptChars,
                    mode: streamMode
                )
            )

            let responseStream = session.streamResponse(to: contextualPrompt, options: options)
            do {
                for try await snapshot in responseStream {
                    streamChunks += 1
                    latest = snapshot.content
                    if let onResponseChunk {
                        let shouldContinue = await onResponseChunk(latest)
                        if !shouldContinue {
                            logger.info(
                                "Model stream cancelled by response consumer",
                                metadata: modelCallMetadata(
                                    channelId: channelId,
                                    model: activeModel,
                                    reasoningEffort: reasoningEffort,
                                    promptChars: promptChars,
                                    mode: streamMode,
                                    durationMs: elapsedMilliseconds(since: streamStartedAt),
                                    outputChars: latest.count,
                                    streamChunks: streamChunks
                                )
                            )
                            if !latest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                await channels.appendSystemMessage(channelId: channelId, content: latest)
                            }
                            return
                        }
                    }
                }
            } catch {
                logger.warning(
                    "Model stream failed",
                    metadata: modelCallMetadata(
                        channelId: channelId,
                        model: activeModel,
                        reasoningEffort: reasoningEffort,
                        promptChars: promptChars,
                        mode: streamMode,
                        durationMs: elapsedMilliseconds(since: streamStartedAt),
                        outputChars: latest.count,
                        streamChunks: streamChunks,
                        error: String(describing: error)
                    )
                )
                throw error
            }

            logger.info(
                "Model stream finished",
                metadata: modelCallMetadata(
                    channelId: channelId,
                    model: activeModel,
                    reasoningEffort: reasoningEffort,
                    promptChars: promptChars,
                    mode: streamMode,
                    durationMs: elapsedMilliseconds(since: streamStartedAt),
                    outputChars: latest.count,
                    streamChunks: streamChunks
                )
            )

            if let observationHandler {
                let reasoningText = modelProvider.reasoningCapture(for: activeModel)?.consume() ?? ""
                if !reasoningText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    await observationHandler(.thinking(reasoningText))
                }
            }

            if latest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let completionStartedAt = Date()
                logger.info(
                    "Model completion started",
                    metadata: modelCallMetadata(
                        channelId: channelId,
                        model: activeModel,
                        reasoningEffort: reasoningEffort,
                        promptChars: promptChars,
                        mode: "respond_complete"
                    )
                )
                do {
                    let response = try await session.respond(to: contextualPrompt, options: options)
                    latest = response.content
                } catch {
                    logger.warning(
                        "Model completion failed",
                        metadata: modelCallMetadata(
                            channelId: channelId,
                            model: activeModel,
                            reasoningEffort: reasoningEffort,
                            promptChars: promptChars,
                            mode: "respond_complete",
                            durationMs: elapsedMilliseconds(since: completionStartedAt),
                            error: String(describing: error)
                        )
                    )
                    throw error
                }
                logger.info(
                    "Model completion finished",
                    metadata: modelCallMetadata(
                        channelId: channelId,
                        model: activeModel,
                        reasoningEffort: reasoningEffort,
                        promptChars: promptChars,
                        mode: "respond_complete",
                        durationMs: elapsedMilliseconds(since: completionStartedAt),
                        outputChars: latest.count
                    )
                )
                if let onResponseChunk {
                    _ = await onResponseChunk(latest)
                }
            }

            await channels.appendSystemMessage(channelId: channelId, content: latest)
        } catch {
            let text = "Model provider error: \(error)"
            if let onResponseChunk {
                _ = await onResponseChunk(text)
            }
            await channels.appendSystemMessage(
                channelId: channelId,
                content: text
            )
        }
    }

    private func elapsedMilliseconds(since start: Date) -> Int {
        let elapsed = Date().timeIntervalSince(start)
        return Int((elapsed * 1000).rounded())
    }

    private func modelCallMetadata(
        channelId: String,
        model: String,
        reasoningEffort: ReasoningEffort?,
        promptChars: Int,
        mode: String,
        toolStep: Int? = nil,
        durationMs: Int? = nil,
        outputChars: Int? = nil,
        streamChunks: Int? = nil,
        toolId: String? = nil,
        toolResultOK: Bool? = nil,
        error: String? = nil
    ) -> Logger.Metadata {
        var metadata: Logger.Metadata = [
            "channel_id": .string(channelId),
            "model": .string(model),
            "reasoning_effort": .string(reasoningEffort?.rawValue ?? "none"),
            "prompt_chars": .stringConvertible(promptChars),
            "mode": .string(mode)
        ]

        if let toolStep {
            metadata["tool_step"] = .stringConvertible(toolStep)
        }
        if let durationMs {
            metadata["duration_ms"] = .stringConvertible(durationMs)
        }
        if let outputChars {
            metadata["output_chars"] = .stringConvertible(outputChars)
        }
        if let streamChunks {
            metadata["stream_chunks"] = .stringConvertible(streamChunks)
        }
        if let toolId {
            metadata["tool_id"] = .string(toolId)
        }
        if let toolResultOK {
            metadata["tool_ok"] = .string(toolResultOK ? "true" : "false")
        }
        if let error {
            metadata["error"] = .string(error)
        }

        return metadata
    }

    private func buildContextualPrompt(channelId: String, fallbackUserMessage: String) async -> Prompt {
        guard let snapshot = await channels.snapshot(channelId: channelId), !snapshot.messages.isEmpty else {
            return Prompt(fallbackUserMessage)
        }

        let bulletinDigest = await visor.latestBulletinDigest()
        let contextMessages = snapshot.messages.suffix(80)

        return Prompt {
            "[channel_context_v1]"
            "Use the conversation context below to answer the latest user request."
            ""

            if let digest = bulletinDigest {
                "## Memory Context"
                digest
                ""
            }

            for message in contextMessages {
                if message.userId == "system" {
                    "[system]"
                } else if message.userId == "agent" || message.userId == "assistant" {
                    "[assistant]"
                } else {
                    "[user]"
                }
                message.content
                ""
            }
        }
    }

    /// Routes interactive payload to worker bound to the channel.
    public func routeMessage(channelId: String, workerId: String, message: String) async -> Bool {
        let result = await workers.route(workerId: workerId, message: message)
        guard result.accepted else {
            return false
        }

        if result.completed {
            await channels.detachWorker(channelId: channelId, workerId: workerId)
            if let artifact = result.artifactRef {
                await channels.appendSystemMessage(
                    channelId: channelId,
                    content: "Worker \(workerId) completed with artifact \(artifact.id)"
                )
            }
        }

        return true
    }

    /// Performs one-shot completion with currently configured model provider.
    /// Returns nil when no provider/model is configured or completion fails.
    public func complete(prompt: some PromptRepresentable, maxTokens: Int = 1024) async -> String? {
        guard let modelProvider, let defaultModel else {
            return nil
        }
        guard let languageModel = try? await modelProvider.createLanguageModel(for: defaultModel) else {
            return nil
        }
        let session: LanguageModelSession
        if let instructions = modelProvider.systemInstructions {
            session = LanguageModelSession(model: languageModel, tools: modelProvider.tools, instructions: instructions)
        } else {
            session = LanguageModelSession(model: languageModel, tools: modelProvider.tools)
        }
        let options = modelProvider.generationOptions(for: defaultModel, maxTokens: maxTokens, reasoningEffort: nil)
        return try? await session.respond(to: prompt.promptRepresentation, options: options).content
    }

    /// Creates worker and attaches it to channel tracking.
    public func createWorker(spec: WorkerTaskSpec) async -> String {
        let workerId = await workers.spawn(spec: spec, autoStart: true)
        await channels.attachWorker(channelId: spec.channelId, workerId: workerId)
        return workerId
    }

    /// Rebuilds in-memory runtime state from persisted channels/tasks/events/artifacts.
    public func recover(
        channels channelStates: [RecoveryChannelState],
        tasks taskStates: [RecoveryTaskState],
        events: [EventEnvelope],
        artifacts: [RecoveryArtifactState]
    ) async {
        await channels.resetForRecovery()
        await workers.resetForRecovery()

        for channel in channelStates.sorted(by: { $0.createdAt < $1.createdAt }) {
            await channels.ensureChannel(channelId: channel.id)
        }

        for artifact in artifacts.sorted(by: { $0.createdAt < $1.createdAt }) {
            await workers.restoreArtifact(id: artifact.id, content: artifact.content)
        }

        let tasksByID = Dictionary(uniqueKeysWithValues: taskStates.map { ($0.id, $0) })
        let orderedEvents = events.sorted { left, right in
            if left.ts == right.ts {
                return left.messageId < right.messageId
            }
            return left.ts < right.ts
        }

        for event in orderedEvents {
            await replayRecoveredEvent(event, tasksByID: tasksByID)
        }

        let eventCountsByChannel = Dictionary(grouping: orderedEvents, by: { $0.channelId })
        for (channelID, eventsForChannel) in eventCountsByChannel where !eventsForChannel.isEmpty {
            if let snapshot = await channels.snapshot(channelId: channelID), snapshot.messages.isEmpty {
                await channels.appendSystemMessage(
                    channelId: channelID,
                    content: "Recovered \(eventsForChannel.count) persisted events."
                )
            }
        }

        for task in taskStates {
            let hasTask = await workers.hasTask(taskId: task.id)
            if hasTask {
                continue
            }
            let spec = WorkerTaskSpec(
                taskId: task.id,
                channelId: task.channelId,
                title: task.title,
                objective: task.objective,
                tools: [],
                mode: .interactive
            )
            let workerID = "recovered-\(task.id)"
            await workers.restoreWorker(
                workerId: workerID,
                spec: spec,
                status: workerStatus(from: task.status),
                latestReport: nil,
                artifactId: nil
            )
            if workerStatus(from: task.status) == .queued ||
                workerStatus(from: task.status) == .running ||
                workerStatus(from: task.status) == .waitingInput {
                await channels.attachWorker(channelId: task.channelId, workerId: workerID)
            }
        }
    }

    private func replayRecoveredEvent(
        _ event: EventEnvelope,
        tasksByID: [String: RecoveryTaskState]
    ) async {
        await channels.ensureChannel(channelId: event.channelId)

        switch event.messageType {
        case .channelMessageReceived:
            guard let userId = event.payload.objectValue["userId"]?.stringValue,
                  let message = event.payload.objectValue["message"]?.stringValue
            else {
                return
            }
            await channels.restoreMessage(
                channelId: event.channelId,
                message: ChannelMessageEntry(
                    id: event.messageId,
                    userId: userId,
                    content: message,
                    createdAt: event.ts
                )
            )

        case .channelRouteDecided:
            guard let decision = try? JSONValueCoder.decode(ChannelRouteDecision.self, from: event.payload) else {
                return
            }
            await channels.restoreDecision(channelId: event.channelId, decision: decision)

        case .branchConclusion:
            guard let conclusion = try? JSONValueCoder.decode(BranchConclusion.self, from: event.payload) else {
                return
            }
            await channels.applyBranchConclusion(channelId: event.channelId, conclusion: conclusion)

        case .workerSpawned:
            guard let workerID = event.workerId,
                  let taskID = event.taskId
            else {
                return
            }
            let spec = recoveredWorkerSpec(
                event: event,
                workerId: workerID,
                taskId: taskID,
                tasksByID: tasksByID
            )
            await workers.restoreWorker(
                workerId: workerID,
                spec: spec,
                status: .queued,
                latestReport: nil,
                artifactId: nil
            )
            await channels.attachWorker(channelId: event.channelId, workerId: workerID)

        case .workerProgress:
            guard let workerID = event.workerId,
                  let taskID = event.taskId
            else {
                return
            }
            let progress = event.payload.objectValue["progress"]?.stringValue
            let status: WorkerStatus = (progress == "waiting_for_route") ? .waitingInput : .running
            let updated = await workers.updateRecoveredWorker(
                workerId: workerID,
                status: status,
                latestReport: progress,
                artifactId: nil
            )
            if !updated {
                let spec = recoveredWorkerSpec(
                    event: event,
                    workerId: workerID,
                    taskId: taskID,
                    tasksByID: tasksByID
                )
                await workers.restoreWorker(
                    workerId: workerID,
                    spec: spec,
                    status: status,
                    latestReport: progress,
                    artifactId: nil
                )
            }
            await channels.attachWorker(channelId: event.channelId, workerId: workerID)

        case .workerCompleted:
            guard let workerID = event.workerId,
                  let taskID = event.taskId
            else {
                return
            }
            let summary = event.payload.objectValue["summary"]?.stringValue
            let artifactID = event.payload.objectValue["artifactId"]?.stringValue
            let updated = await workers.updateRecoveredWorker(
                workerId: workerID,
                status: .completed,
                latestReport: summary,
                artifactId: artifactID
            )
            if !updated {
                let spec = recoveredWorkerSpec(
                    event: event,
                    workerId: workerID,
                    taskId: taskID,
                    tasksByID: tasksByID
                )
                await workers.restoreWorker(
                    workerId: workerID,
                    spec: spec,
                    status: .completed,
                    latestReport: summary,
                    artifactId: artifactID
                )
            }
            await channels.detachWorker(channelId: event.channelId, workerId: workerID)

        case .workerFailed:
            guard let workerID = event.workerId,
                  let taskID = event.taskId
            else {
                return
            }
            let error = event.payload.objectValue["error"]?.stringValue
            let updated = await workers.updateRecoveredWorker(
                workerId: workerID,
                status: .failed,
                latestReport: error,
                artifactId: nil
            )
            if !updated {
                let spec = recoveredWorkerSpec(
                    event: event,
                    workerId: workerID,
                    taskId: taskID,
                    tasksByID: tasksByID
                )
                await workers.restoreWorker(
                    workerId: workerID,
                    spec: spec,
                    status: .failed,
                    latestReport: error,
                    artifactId: nil
                )
            }
            await channels.detachWorker(channelId: event.channelId, workerId: workerID)

        default:
            break
        }
    }

    private func recoveredWorkerSpec(
        event: EventEnvelope,
        workerId: String,
        taskId: String,
        tasksByID: [String: RecoveryTaskState]
    ) -> WorkerTaskSpec {
        let taskState = tasksByID[taskId]
        let modeText = event.payload.objectValue["mode"]?.stringValue
        let mode = modeText.flatMap(WorkerMode.init(rawValue:)) ?? .interactive
        let title = event.payload.objectValue["title"]?.stringValue ?? taskState?.title ?? "Recovered worker \(workerId)"
        let objective = taskState?.objective ?? event.payload.objectValue["objective"]?.stringValue ?? ""

        return WorkerTaskSpec(
            taskId: taskId,
            channelId: event.channelId,
            title: title,
            objective: objective,
            tools: [],
            mode: mode
        )
    }

    private func workerStatus(from raw: String) -> WorkerStatus {
        switch raw.lowercased() {
        case "queued", "ready", "pending_approval", "backlog":
            .queued
        case "running", "in_progress":
            .running
        case "waiting_input", "waitinginput":
            .waitingInput
        case "completed", "done":
            .completed
        case "failed":
            .failed
        default:
            .queued
        }
    }

    /// Returns channel snapshot by identifier.
    public func channelState(channelId: String) async -> ChannelSnapshot? {
        await channels.snapshot(channelId: channelId)
    }

    /// Appends one synthetic system message into channel context.
    public func appendSystemMessage(channelId: String, content: String) async {
        await channels.appendSystemMessage(channelId: channelId, content: content)
    }

    /// Returns artifact content by identifier.
    public func artifactContent(id: String) async -> String? {
        await workers.artifactContent(id: id)
    }

    /// Generates visor bulletin. The digest is injected into LLM prompts at call time via buildContextualPrompt.
    public func generateVisorBulletin(taskSummary: String? = nil) async -> MemoryBulletin {
        let channelSnapshots = await channels.snapshots()
        let workerSnapshots = await workers.snapshots()
        return await visor.generateBulletin(
            channels: channelSnapshots,
            workers: workerSnapshots,
            taskSummary: taskSummary
        )
    }

    /// Returns collected bulletins.
    public func bulletins() async -> [MemoryBulletin] {
        await visor.listBulletins()
    }

    /// Returns current worker snapshots.
    public func workerSnapshots() async -> [WorkerSnapshot] {
        await workers.snapshots()
    }

    /// Returns active branch snapshots.
    public func activeBranchSnapshots() async -> [BranchSnapshot] {
        await branches.activeBranches()
    }

    /// Starts the Visor supervision tick loop with config-driven parameters.
    public func startVisorSupervision(
        tickIntervalSeconds: Int,
        workerTimeoutSeconds: Int,
        branchTimeoutSeconds: Int,
        maintenanceIntervalSeconds: Int,
        decayRatePerDay: Double,
        pruneImportanceThreshold: Double,
        pruneMinAgeDays: Int,
        channelDegradedFailureCount: Int = 3,
        channelDegradedWindowSeconds: Int = 600,
        idleThresholdSeconds: Int = 1800,
        mergeEnabled: Bool = false,
        mergeSimilarityThreshold: Double = 0.80,
        mergeMaxPerRun: Int = 10
    ) async {
        await visor.startSupervision(
            tickInterval: .seconds(max(1, tickIntervalSeconds)),
            workerTimeoutSeconds: workerTimeoutSeconds,
            branchTimeoutSeconds: branchTimeoutSeconds,
            maintenanceIntervalSeconds: maintenanceIntervalSeconds,
            decayRatePerDay: decayRatePerDay,
            pruneImportanceThreshold: pruneImportanceThreshold,
            pruneMinAgeDays: pruneMinAgeDays,
            channelDegradedFailureCount: channelDegradedFailureCount,
            channelDegradedWindowSeconds: channelDegradedWindowSeconds,
            idleThresholdSeconds: idleThresholdSeconds,
            mergeEnabled: mergeEnabled,
            mergeSimilarityThreshold: mergeSimilarityThreshold,
            mergeMaxPerRun: mergeMaxPerRun,
            snapshotProvider: { [weak self] in
                guard let self else { return ([], []) }
                return await (self.channels.snapshots(), self.workers.snapshots())
            },
            branchProvider: { [weak self] in
                guard let self else { return [] }
                return await self.branches.activeBranches()
            },
            branchForceTimeout: { [weak self] branchId in
                await self?.branches.forceTimeout(branchId: branchId)
            }
        )
    }

    /// Stops the Visor supervision tick loop.
    public func stopVisorSupervision() async {
        await visor.stopSupervision()
    }

    /// Returns true after Visor has completed its first supervision tick.
    public func isVisorReady() async -> Bool {
        await visor.isReady
    }

    /// Asks Visor a question and returns an LLM-synthesized answer from current context.
    public func askVisor(question: String) async -> String {
        let channels = await channels.snapshots()
        let workers = await workers.snapshots()
        return await visor.answer(question: question, channels: channels, workers: workers)
    }

    /// Asks Visor a question and streams the answer as text delta chunks.
    public func streamVisorAnswer(question: String) async -> AsyncStream<String> {
        let channels = await channels.snapshots()
        let workers = await workers.snapshots()
        return await visor.streamAnswer(question: question, channels: channels, workers: workers)
    }

    /// Cancels all active workers on a channel and emits abort event.
    public func abortChannel(channelId: String) async -> Int {
        guard let snapshot = await channels.snapshot(channelId: channelId) else {
            return 0
        }
        var cancelled = 0
        for workerId in snapshot.activeWorkerIds {
            let ok = await workers.cancel(workerId: workerId)
            if ok {
                await channels.detachWorker(channelId: channelId, workerId: workerId)
                cancelled += 1
            }
        }
        if cancelled > 0 {
            await channels.appendSystemMessage(
                channelId: channelId,
                content: "Channel processing aborted. \(cancelled) worker(s) cancelled."
            )
        }
        return cancelled
    }

    /// Returns memory entries tracked by runtime memory store.
    public func memoryEntries() async -> [MemoryEntry] {
        await memoryStore.entries()
    }
}

private extension JSONValue {
    var objectValue: [String: JSONValue] {
        if case .object(let object) = self {
            return object
        }
        return [:]
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }
}
