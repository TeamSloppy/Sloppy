import Foundation
import Protocols

extension CoreService {
    private enum WatchAccess {
        case allowed, discoveryPending, unavailable
    }

    func manageSessionWatch(
        agentID: String, sessionID: String, arguments: [String: JSONValue], allowedTools: Set<String>?
    ) async -> ToolInvocationResult {
        let tool = SessionWatchTool.toolName
        guard !sessionMessageIsStopping,
              let detail = try? getAgentSession(agentID: agentID, sessionID: sessionID, eventLimit: 1),
              !detail.summary.isWorker, detail.summary.parentSessionId == nil else {
            return toolFailure(tool: tool, code: "watch_unavailable", message: "Job watches require a parent chat.", retryable: false)
        }
        let root = workspaceRootURL
        let storage = SessionWatchStore(root: root)
        do {
            switch arguments["action"]?.asString {
            case "start":
                guard let target = SessionWatchTool.target(arguments),
                      let title = SessionToolQuery.nonempty(arguments["title"]?.asString),
                      let interval = arguments["intervalSeconds"]?.asInt ?? (arguments["intervalSeconds"] == nil ? 60 : nil),
                      (5...3600).contains(interval) else {
                    return toolFailure(tool: tool, code: "invalid_arguments", message: "Provide a job title, one process or a complete MCP status specification, and an interval of 5–3600 seconds.", retryable: false)
                }
                guard await watchAccess(target, agentID: agentID, sessionID: sessionID, allowedTools: allowedTools) == .allowed,
                      workspaceRootURL == root, !sessionMessageIsStopping, !Task.isCancelled else {
                    return toolFailure(tool: tool, code: "watch_target_unavailable", message: "The current session cannot read this target. Use an existing process or an allowed read-only MCP tool.", retryable: false)
                }
                if case .process(let id) = target {
                    guard detail.summary.kind != .longChat else {
                        return toolFailure(tool: tool, code: "watch_target_unavailable",
                            message: "A project chat can watch external jobs through read-only MCP status tools.", retryable: false)
                    }
                    _ = try await toolExecution.processRegistry.status(sessionID: sessionID, processID: id)
                }
                guard workspaceRootURL == root, !sessionMessageIsStopping, !Task.isCancelled else { throw CancellationError() }
                if let existing = try storage.ids().compactMap({ try? storage.load($0) }).first(where: {
                    $0.agentID == agentID && $0.sessionID == sessionID && $0.target == target && $0.outcome == nil
                }) {
                    scheduleSessionWatch(existing, root: root)
                    return toolSuccess(tool: tool, data: watchPayload(existing, scheduled: true))
                }
                let watch = SessionWatch(id: UUID().uuidString, agentID: agentID, sessionID: sessionID,
                    title: String(title.prefix(160)), target: target, intervalSeconds: interval,
                    nextCheck: Date().addingTimeInterval(Double(interval)))
                try storage.save(watch)
                scheduleSessionWatch(watch, root: root)
                return toolSuccess(tool: tool, data: watchPayload(watch, scheduled: true))
            case "status", "cancel":
                guard let id = arguments["watchId"]?.asString, UUID(uuidString: id) != nil,
                      var watch = try? storage.load(id), watch.agentID == agentID, watch.sessionID == sessionID else {
                    return toolFailure(tool: tool, code: "watch_not_found", message: "This watch is not active in the current chat.", retryable: false)
                }
                if arguments["action"]?.asString == "cancel", watch.outcome == nil {
                    watch.outcome = .init(state: .cancelled, detail: "The user stopped monitoring this job.")
                    watch.nextCheck = Date()
                    try storage.save(watch)
                    sessionWatchRunners.removeValue(forKey: id)?.cancel()
                    scheduleSessionWatch(watch, root: root)
                }
                return toolSuccess(tool: tool, data: watchPayload(watch, scheduled: false))
            default:
                return toolFailure(tool: tool, code: "invalid_arguments", message: "Use start, status or cancel.", retryable: false)
            }
        } catch SessionProcessRegistry.RegistryError.processNotFound {
            return toolFailure(tool: tool, code: "watch_target_unavailable", message: "The process was not found in this chat.", retryable: false)
        } catch {
            return toolFailure(tool: tool, code: "watch_storage_failed", message: "The watch could not be saved or read.", retryable: true)
        }
    }

    private func watchPayload(_ watch: SessionWatch, scheduled: Bool) -> JSONValue {
        .object([
            "watchId": .string(watch.id), "title": .string(watch.title), "watchScheduled": .bool(scheduled),
            "status": .string(watch.outcome?.state.rawValue ?? watch.lastStatus ?? "pending"),
            "nextCheckAt": watch.outcome == nil ? .string(ISO8601DateFormatter().string(from: watch.nextCheck)) : .null
        ])
    }

    private func watchAccess(
        _ target: SessionWatch.Target, agentID: String, sessionID: String, allowedTools: Set<String>? = nil
    ) async -> WatchAccess {
        guard let policy = try? await toolsAuthorization.policy(agentID: agentID) else { return .unavailable }
        let scope = allowedTools ?? sessionSubagentToolAllowList[sessionID]
        switch target {
        case .process:
            let allowed = SubagentDelegation.isToolAllowedByPolicy(toolID: "runtime.process", policy: policy)
                && (scope?.contains("runtime.process") ?? true)
            return allowed ? .allowed : .unavailable
        case .mcp(let source):
            guard !ToolCatalog.knownToolIDs.contains(source.tool),
                  SubagentDelegation.isToolAllowedByPolicy(toolID: source.tool, policy: policy),
                  scope?.contains(source.tool) ?? true else { return .unavailable }
            guard let tool = await mcpRegistry.dynamicTool(for: source.tool) else {
                return await mcpRegistry.dynamicDiscoveryIsComplete() ? .unavailable : .discoveryPending
            }
            return tool.readOnlyHint ? .allowed : .unavailable
        }
    }

    func recoverSessionWatchesIfNeeded() {
        guard !sessionWatchRecoveryCompleted, !sessionMessageIsStopping else { return }
        let root = workspaceRootURL
        let storage = SessionWatchStore(root: root)
        do {
            for id in try storage.ids() {
                do { scheduleSessionWatch(try storage.load(id), root: root) }
                catch { logger.warning("session.watch.load_failed", metadata: ["watch_id": .string(id)]) }
            }
            sessionWatchRecoveryCompleted = true
        } catch {
            logger.warning("session.watch.recovery_failed", metadata: ["error": .string(error.localizedDescription)])
        }
    }

    func stopSessionWatchRunners() {
        for task in sessionWatchRunners.values { task.cancel() }
        sessionWatchRunners.removeAll()
        sessionWatchRecoveryCompleted = false
    }

    func hasPendingSessionWatch(sessionID: String) -> Bool {
        let storage = SessionWatchStore(root: workspaceRootURL)
        return (try? storage.ids().contains { id in
            guard let watch = try? storage.load(id) else { return false }
            return watch.sessionID == sessionID
        }) ?? false
    }

    func cancelSessionWatches(sessionID: String) {
        let storage = SessionWatchStore(root: workspaceRootURL)
        do {
            for id in try storage.ids() {
                guard let watch = try? storage.load(id), watch.sessionID == sessionID else { continue }
                try storage.remove(watch)
                sessionWatchRunners.removeValue(forKey: id)?.cancel()
            }
        } catch {
            logger.warning("session.watch.cancel_failed", metadata: ["error": .string(error.localizedDescription)])
        }
    }

    private func scheduleSessionWatch(_ watch: SessionWatch, root: URL, earliestDelay: TimeInterval = 0) {
        guard workspaceRootURL == root, !sessionMessageIsStopping, sessionWatchRunners[watch.id] == nil else { return }
        let id = watch.id
        let delay = max(earliestDelay, watch.nextCheck.timeIntervalSinceNow)
        sessionWatchRunners[id] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            await self?.advanceSessionWatch(id, root: root)
        }
    }

    private func advanceSessionWatch(_ id: String, root: URL) async {
        guard workspaceRootURL == root, !sessionMessageIsStopping, !Task.isCancelled else { return }
        let storage = SessionWatchStore(root: root)
        guard var watch = try? storage.load(id) else {
            sessionWatchRunners.removeValue(forKey: id)
            return
        }
        if watch.outcome == nil {
            let observation = await observeSessionWatch(watch, root: root)
            guard workspaceRootURL == root, !sessionMessageIsStopping, !Task.isCancelled else { return }
            watch.apply(observation, now: Date())
        }
        sessionWatchRunners.removeValue(forKey: id)
        do {
            try storage.save(watch)
            if let outcome = watch.outcome {
                if activeSessionMessageRuns.contains(watch.sessionID) || longChatTurnRunners.contains(watch.sessionID) {
                    scheduleSessionWatch(watch, root: root, earliestDelay: 1)
                    return
                }
                try publishSessionWatchOutcome(watch, outcome: outcome)
                try storage.remove(watch)
            } else {
                scheduleSessionWatch(watch, root: root)
            }
        } catch {
            logger.warning("session.watch.checkpoint_failed", metadata: ["watch_id": .string(id), "error": .string(error.localizedDescription)])
            scheduleSessionWatch(watch, root: root, earliestDelay: 60)
        }
    }

    private func observeSessionWatch(_ watch: SessionWatch, root: URL) async -> SessionWatch.Observation {
        guard (try? getAgentSession(agentID: watch.agentID, sessionID: watch.sessionID, eventLimit: 1)) != nil else {
            return .finished(.init(state: .unavailable, detail: "The chat is no longer available."))
        }
        let access = await watchAccess(watch.target, agentID: watch.agentID, sessionID: watch.sessionID)
        guard workspaceRootURL == root, !sessionMessageIsStopping, !Task.isCancelled else { return .retry }
        if access == .discoveryPending { return .retry }
        guard access == .allowed else {
            return .finished(.init(state: .unavailable, detail: "The status source is no longer available or authorized."))
        }
        switch watch.target {
        case .process(let id):
            let registry = toolExecution.processRegistry
            guard let result = try? await registry.status(sessionID: watch.sessionID, processID: id),
                  let data = result.asObject else {
                return .finished(.init(state: .unavailable, detail: "The local process result is unavailable. Core cannot recover an in-memory process handle after restart."))
            }
            guard let exitCode = data["exitCode"]?.asInt else { return .pending("running") }
            let completion = try? await registry.wait(sessionID: watch.sessionID, processID: id, timeoutMs: 5_000)
            let output = completion?.asObject?["outputTail"]?.asString ?? ""
            let detail = "Exit code: \(exitCode)." + (exitCode == 0 || output.isEmpty ? "" : "\n\(output.suffix(1400))")
            return .finished(.init(state: exitCode == 0 ? .succeeded : .failed, detail: detail))
        case .mcp(let source):
            let result = await invokeToolFromRuntime(agentID: watch.agentID, sessionID: watch.sessionID,
                request: .init(tool: source.tool, arguments: source.arguments), recordSessionEvents: false,
                backgroundStatusCheck: true)
            guard result.ok, let data = result.data else {
                if result.error?.retryable == true { return .retry }
                let explanation = result.error?.message ?? "The status tool returned no result."
                return .finished(.init(state: .unavailable, detail: String(explanation.prefix(1400))))
            }
            return source.evaluate(data)
        }
    }

    private func publishSessionWatchOutcome(_ watch: SessionWatch, outcome: SessionWatch.Outcome) throws {
        let detail: AgentSessionDetail
        do {
            detail = try getAgentSession(agentID: watch.agentID, sessionID: watch.sessionID)
        } catch AgentSessionError.sessionNotFound {
            return
        } catch AgentSessionError.agentNotFound {
            return
        }
        let eventID = "job-watch-" + watch.id
        guard !detail.events.contains(where: { $0.id == eventID }) else { return }
        let messageEvent = AgentSessionEvent(id: eventID, agentId: watch.agentID, sessionId: watch.sessionID, type: .message,
            message: .init(id: eventID, role: .assistant,
                segments: [.init(kind: .text, text: "\(outcome.label) — \(watch.title)\n\n\(outcome.detail)")]))
        var events = [messageEvent]
        if detail.events.reversed().compactMap(\.runStatus).first?.id == watch.id {
            events.append(.init(agentId: watch.agentID, sessionId: watch.sessionID, type: .runStatus,
                runStatus: .init(stage: outcome.state == .succeeded ? .done : .interrupted, label: outcome.label, details: watch.title)))
        }
        let summary = try sessionStore.appendEvents(agentID: watch.agentID, sessionID: watch.sessionID, events: events)
        publishLiveSessionEvents(agentID: watch.agentID, sessionID: watch.sessionID, summary: summary, events: events)
    }
}
