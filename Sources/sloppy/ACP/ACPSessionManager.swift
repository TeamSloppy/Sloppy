import ACP
import ACPModel
import Foundation
import Logging
import Protocols

struct ACPMessageRunResult: Sendable {
    let assistantText: String
    let stopReason: StopReason
    let didResetContext: Bool
}

private struct ACPTrackedToolCall: Sendable {
    var id: String
    var title: String
    var kind: ToolKind?
    var status: ToolStatus
    var content: [ToolCallContent]
    var rawOutput: AnyCodable?

    mutating func apply(update: ToolCallUpdateDetails) {
        if let status = update.status {
            self.status = status
        }
        if let kind = update.kind {
            self.kind = kind
        }
        if let title = update.title, !title.isEmpty {
            self.title = title
        }
        if let content = update.content {
            self.content = content
        }
        if let rawOutput = update.rawOutput {
            self.rawOutput = rawOutput
        }
    }

    func asToolCallEvent(agentID: String, sessionID: String) -> AgentSessionEvent {
        AgentSessionEvent(
            agentId: agentID,
            sessionId: sessionID,
            type: .toolCall,
            toolCall: AgentToolCallEvent(
                tool: title,
                arguments: ACPTrackedToolCall.arguments(from: content, rawOutput: rawOutput),
                reason: kind?.rawValue
            )
        )
    }

    func asToolResultEvent(agentID: String, sessionID: String) -> AgentSessionEvent {
        let success = status == .completed
        let contentText = content.compactMap(\.displayText).joined(separator: "\n")
        let data: JSONValue? = contentText.isEmpty ? nil : .object(["summary": .string(contentText)])
        let error = success
            ? nil
            : ToolErrorPayload(
                code: "acp_tool_failed",
                message: contentText.isEmpty ? "ACP tool call failed." : contentText,
                retryable: false
            )
        return AgentSessionEvent(
            agentId: agentID,
            sessionId: sessionID,
            type: .toolResult,
            toolResult: AgentToolResultEvent(
                tool: title,
                ok: success,
                data: data,
                error: error
            )
        )
    }

    private static func arguments(from content: [ToolCallContent], rawOutput: AnyCodable?) -> [String: JSONValue] {
        var payload: [String: JSONValue] = [:]
        let parts = content.compactMap(\.displayText).joined(separator: "\n")
        if !parts.isEmpty {
            payload["content"] = .string(parts)
        }
        if let rawOutput {
            payload["rawOutput"] = ACPJSONValueEncoder.encode(any: rawOutput.value)
        }
        return payload
    }
}

private enum ACPRunVisibility: Sendable {
    case visible
    case hiddenPrimer
}

private struct ACPCurrentRun: Sendable {
    let agentID: String
    let sloppySessionID: String
    let visibility: ACPRunVisibility
    let onChunk: @Sendable (String) async -> Void
    let onEvent: @Sendable (AgentSessionEvent) async -> Void
    var assistantText: String = ""
    var toolCalls: [String: ACPTrackedToolCall] = [:]
}

private struct ACPManagedSession: Sendable {
    let client: any ACPTransportClient
    let target: CoreConfig.ACP.Target
    let transportFingerprint: String
    let effectiveCwd: String
    let upstreamSessionId: SessionId
    let agentName: String?
    let agentVersion: String?
    let supportsLoadSession: Bool
    let delegate: ACPClientDelegateAdapter
    let notificationTask: Task<Void, Never>
    var currentModeID: String?
    var availableModeIDs: Set<String>
    var needsPrimer: Bool
    var currentRun: ACPCurrentRun?
}

private struct ACPPreparedSession: Sendable {
    let managed: ACPManagedSession
    let didResetContext: Bool
}

private enum ACPJSONValueEncoder {
    static func encode(any value: any Sendable) -> JSONValue {
        switch value {
        case let string as String:
            return .string(string)
        case let int as Int:
            return .number(Double(int))
        case let double as Double:
            return .number(double)
        case let bool as Bool:
            return .bool(bool)
        case let array as [any Sendable]:
            return .array(array.map(encode(any:)))
        case let dict as [String: any Sendable]:
            return .object(dict.mapValues(encode(any:)))
        default:
            return .null
        }
    }
}

actor ACPSessionManager {
    enum ACPError: Error, LocalizedError {
        case disabled
        case invalidRuntime
        case targetNotFound(String)
        case targetDisabled(String)
        case invalidTarget(String)
        case unsupportedControl(String)
        case launchFailed(String)
        case protocolError(String)

        var errorDescription: String? {
            switch self {
            case .disabled:
                return "ACP is disabled in runtime config."
            case .invalidRuntime:
                return "Agent is not configured for ACP runtime."
            case .targetNotFound(let id):
                return "ACP target '\(id)' was not found."
            case .targetDisabled(let id):
                return "ACP target '\(id)' is disabled."
            case .invalidTarget(let message):
                return message
            case .unsupportedControl(let action):
                return "ACP control '\(action)' is not supported."
            case .launchFailed(let message):
                return message
            case .protocolError(let message):
                return message
            }
        }
    }

    private let logger: Logging.Logger
    private let clientFactory: ACPClientFactory
    private let stateStore: ACPSessionStateStore
    private var config: CoreConfig.ACP
    private var workspaceRootURL: URL
    private var sessions: [String: ACPManagedSession] = [:]
    private var permissionNotificationSink: (@Sendable (String, String, String) async -> Void)?

    init(
        config: CoreConfig.ACP,
        workspaceRootURL: URL,
        agentsRootURL: URL,
        logger: Logging.Logger = Logging.Logger(label: "sloppy.acp"),
        clientFactory: ACPClientFactory = .live
    ) {
        self.config = config
        self.workspaceRootURL = workspaceRootURL
        self.stateStore = ACPSessionStateStore(agentsRootURL: agentsRootURL)
        self.logger = logger
        self.clientFactory = clientFactory
    }

    func updatePermissionNotificationSink(_ sink: (@Sendable (String, String, String) async -> Void)?) {
        permissionNotificationSink = sink
    }

    func updateConfig(_ config: CoreConfig.ACP, workspaceRootURL: URL, agentsRootURL: URL) async {
        let previousTargets = Dictionary(uniqueKeysWithValues: self.config.targets.map { ($0.id, $0) })
        self.config = config
        self.workspaceRootURL = workspaceRootURL
        self.stateStore.updateAgentsRootURL(agentsRootURL)

        for (key, session) in sessions {
            let nextTarget = config.targets.first { $0.id == session.target.id }
            if nextTarget == nil || nextTarget != previousTargets[session.target.id] || nextTarget?.enabled != true {
                await terminateSession(forKey: key)
                sessions.removeValue(forKey: key)
            }
        }
    }

    func shutdown() async {
        for key in sessions.keys {
            await terminateSession(forKey: key)
        }
        sessions.removeAll()
    }

    func validateRuntime(_ runtime: AgentRuntimeConfig) throws {
        guard config.enabled else {
            throw ACPError.disabled
        }
        guard runtime.type == .acp else {
            throw ACPError.invalidRuntime
        }
        _ = try resolveTarget(for: runtime)
    }

    func probeTarget(_ probe: ACPProbeTarget) async throws -> ACPTargetProbeResponse {
        let target = try normalizeTarget(probe)
        return try await probeTarget(target)
    }

    func postMessage(
        agentID: String,
        sloppySessionID: String,
        runtime: AgentRuntimeConfig,
        content: [ContentBlock],
        localSessionHadPriorMessages: Bool,
        primerContent: String?,
        chatMode: AgentChatMode? = nil,
        onChunk: @escaping @Sendable (String) async -> Void,
        onEvent: @escaping @Sendable (AgentSessionEvent) async -> Void
    ) async throws -> ACPMessageRunResult {
        let sessionKey = Self.sessionKey(agentID: agentID, sloppySessionID: sloppySessionID)
        let target = try resolveTarget(for: runtime)
        let effectiveCwd = resolveCwd(runtime: runtime, target: target)
        logger.info(
            "ACP prompt dispatch started",
            metadata: acpMetadata(
                agentID: agentID,
                sloppySessionID: sloppySessionID,
                target: target,
                effectiveCwd: effectiveCwd,
                extra: [
                    "content_blocks": .stringConvertible(content.count),
                    "local_session_had_prior_messages": .stringConvertible(localSessionHadPriorMessages),
                    "chat_mode": .string(chatMode?.rawValue ?? "unspecified")
                ]
            )
        )

        let prepared = try await prepareSession(
            agentID: agentID,
            sloppySessionID: sloppySessionID,
            sessionKey: sessionKey,
            target: target,
            effectiveCwd: effectiveCwd,
            localSessionHadPriorMessages: localSessionHadPriorMessages
        )
        sessions[sessionKey] = prepared.managed

        if prepared.managed.needsPrimer,
           let primerContent,
           !primerContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                try await sendPrimerTurn(
                    agentID: agentID,
                    sloppySessionID: sloppySessionID,
                    sessionKey: sessionKey,
                    primerContent: primerContent
                )
            } catch {
                await terminateSession(forKey: sessionKey)
                sessions.removeValue(forKey: sessionKey)
                try? stateStore.delete(agentID: agentID, sessionID: sloppySessionID)
                logger.warning(
                    "ACP primer turn failed",
                    metadata: acpMetadata(
                        agentID: agentID,
                        sloppySessionID: sloppySessionID,
                        target: target,
                        effectiveCwd: effectiveCwd,
                        extra: ["error": .string(error.localizedDescription)]
                    )
                )
                throw error
            }
        }

        guard var managed = sessions[sessionKey] else {
            throw ACPError.protocolError("ACP session was not created.")
        }

        try await applyChatModeIfSupported(chatMode, to: &managed)

        managed.currentRun = ACPCurrentRun(
            agentID: agentID,
            sloppySessionID: sloppySessionID,
            visibility: .visible,
            onChunk: onChunk,
            onEvent: onEvent
        )
        sessions[sessionKey] = managed

        defer {
            Task {
                self.clearCurrentRun(for: sessionKey)
            }
        }

        let response: SessionPromptResponse
        do {
            response = try await managed.client.sendPrompt(
                sessionId: managed.upstreamSessionId,
                content: content
            )
        } catch {
            logger.warning(
                "ACP prompt failed",
                metadata: acpMetadata(
                    agentID: agentID,
                    sloppySessionID: sloppySessionID,
                    target: target,
                    upstreamSessionId: managed.upstreamSessionId,
                    effectiveCwd: effectiveCwd,
                    extra: ["error": .string(error.localizedDescription)]
                )
            )
            throw ACPError.launchFailed(error.localizedDescription)
        }

        let assistantText = sessions[sessionKey]?.currentRun?.assistantText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        logger.info(
            "ACP prompt completed",
            metadata: acpMetadata(
                agentID: agentID,
                sloppySessionID: sloppySessionID,
                target: target,
                upstreamSessionId: managed.upstreamSessionId,
                effectiveCwd: effectiveCwd,
                extra: [
                    "stop_reason": .string(response.stopReason.rawValue),
                    "assistant_text_characters": .stringConvertible(assistantText.count),
                    "did_reset_context": .stringConvertible(prepared.didResetContext)
                ]
            )
        )
        return ACPMessageRunResult(
            assistantText: assistantText,
            stopReason: response.stopReason,
            didResetContext: prepared.didResetContext
        )
    }

    func controlSession(agentID: String, sloppySessionID: String, action: AgentRunControlAction) async throws {
        let sessionKey = Self.sessionKey(agentID: agentID, sloppySessionID: sloppySessionID)
        guard let managed = sessions[sessionKey] else {
            if action == .interrupt || action == .interruptTree {
                return
            }
            throw ACPError.unsupportedControl(action.rawValue)
        }

        switch action {
        case .interrupt, .interruptTree:
            do {
                try await managed.client.cancelSession(sessionId: managed.upstreamSessionId)
            } catch {
                throw ACPError.launchFailed(error.localizedDescription)
            }
        case .pause, .resume:
            throw ACPError.unsupportedControl(action.rawValue)
        }
    }

    func hasManagedSession(agentID: String, sloppySessionID: String) -> Bool {
        sessions[Self.sessionKey(agentID: agentID, sloppySessionID: sloppySessionID)] != nil
    }

    func removeSession(agentID: String, sloppySessionID: String) async {
        let sessionKey = Self.sessionKey(agentID: agentID, sloppySessionID: sloppySessionID)
        await terminateSession(forKey: sessionKey)
        sessions.removeValue(forKey: sessionKey)
        try? stateStore.delete(agentID: agentID, sessionID: sloppySessionID)
    }

    private func prepareSession(
        agentID: String,
        sloppySessionID: String,
        sessionKey: String,
        target: CoreConfig.ACP.Target,
        effectiveCwd: String,
        localSessionHadPriorMessages: Bool
    ) async throws -> ACPPreparedSession {
        let transportFingerprint = try transportFingerprint(for: target)
        var didResetContext = false

        if let existing = sessions[sessionKey] {
            if existing.target != target || existing.effectiveCwd != effectiveCwd || existing.transportFingerprint != transportFingerprint {
                logger.info(
                    "ACP managed session reset before prompt",
                    metadata: acpMetadata(
                        agentID: agentID,
                        sloppySessionID: sloppySessionID,
                        target: target,
                        upstreamSessionId: existing.upstreamSessionId,
                        effectiveCwd: effectiveCwd,
                        extra: [
                            "previous_target_id": .string(existing.target.id),
                            "previous_cwd": .string(existing.effectiveCwd)
                        ]
                    )
                )
                await terminateSession(forKey: sessionKey)
                sessions.removeValue(forKey: sessionKey)
                didResetContext = true
            } else {
                logger.info(
                    "ACP managed session reused",
                    metadata: acpMetadata(
                        agentID: agentID,
                        sloppySessionID: sloppySessionID,
                        target: target,
                        upstreamSessionId: existing.upstreamSessionId,
                        effectiveCwd: effectiveCwd
                    )
                )
                return ACPPreparedSession(managed: existing, didResetContext: false)
            }
        }

        if let sidecar = try stateStore.load(agentID: agentID, sessionID: sloppySessionID) {
            if sidecar.targetId == target.id,
               sidecar.transportFingerprint == transportFingerprint,
               sidecar.effectiveCwd == effectiveCwd,
               sidecar.supportsLoadSession {
                do {
                    let restored = try await restoreManagedSession(
                        sessionKey: sessionKey,
                        target: target,
                        transportFingerprint: transportFingerprint,
                        effectiveCwd: effectiveCwd,
                        upstreamSessionId: SessionId(sidecar.upstreamSessionId)
                    )
                    try persistState(agentID: agentID, sloppySessionID: sloppySessionID, managed: restored)
                    return ACPPreparedSession(managed: restored, didResetContext: didResetContext)
                } catch {
                    logger.warning(
                        "ACP session restore failed; creating a new upstream session",
                        metadata: [
                            "agent_id": .string(agentID),
                            "session_id": .string(sloppySessionID),
                            "target_id": .string(target.id),
                            "error": .string(error.localizedDescription)
                        ]
                    )
                    didResetContext = true
                }
            } else {
                logger.info(
                    "ACP persisted session state ignored",
                    metadata: acpMetadata(
                        agentID: agentID,
                        sloppySessionID: sloppySessionID,
                        target: target,
                        effectiveCwd: effectiveCwd,
                        extra: [
                            "persisted_target_id": .string(sidecar.targetId),
                            "persisted_cwd": .string(sidecar.effectiveCwd),
                            "persisted_supports_load_session": .stringConvertible(sidecar.supportsLoadSession)
                        ]
                    )
                )
                didResetContext = true
            }
        } else if localSessionHadPriorMessages {
            logger.info(
                "ACP local session has history without persisted upstream state",
                metadata: acpMetadata(
                    agentID: agentID,
                    sloppySessionID: sloppySessionID,
                    target: target,
                    effectiveCwd: effectiveCwd
                )
            )
            didResetContext = true
        }

        let created = try await createManagedSession(
            sessionKey: sessionKey,
            target: target,
            transportFingerprint: transportFingerprint,
            effectiveCwd: effectiveCwd
        )
        try persistState(agentID: agentID, sloppySessionID: sloppySessionID, managed: created)
        return ACPPreparedSession(managed: created, didResetContext: didResetContext)
    }

    private func clearCurrentRun(for sessionKey: String) {
        guard var managed = sessions[sessionKey] else {
            return
        }
        managed.currentRun = nil
        sessions[sessionKey] = managed
    }

    private func sendPrimerTurn(
        agentID: String,
        sloppySessionID: String,
        sessionKey: String,
        primerContent: String
    ) async throws {
        guard var managed = sessions[sessionKey] else {
            throw ACPError.protocolError("ACP session was not created.")
        }

        managed.currentRun = ACPCurrentRun(
            agentID: agentID,
            sloppySessionID: sloppySessionID,
            visibility: .hiddenPrimer,
            onChunk: { _ in },
            onEvent: { _ in }
        )
        sessions[sessionKey] = managed

        defer {
            Task {
                self.clearCurrentRun(for: sessionKey)
            }
        }

        do {
            _ = try await managed.client.sendPrompt(
                sessionId: managed.upstreamSessionId,
                content: [.text(TextContent(text: primerContent))]
            )
        } catch {
            throw ACPError.launchFailed(error.localizedDescription)
        }

        managed = sessions[sessionKey] ?? managed
        managed.needsPrimer = false
        managed.currentRun = nil
        sessions[sessionKey] = managed
        logger.info(
            "ACP primer turn sent",
            metadata: acpMetadata(
                agentID: agentID,
                sloppySessionID: sloppySessionID,
                target: managed.target,
                upstreamSessionId: managed.upstreamSessionId,
                effectiveCwd: managed.effectiveCwd,
                extra: ["primer_characters": .stringConvertible(primerContent.count)]
            )
        )
    }

    private func applyChatModeIfSupported(_ chatMode: AgentChatMode?, to managed: inout ACPManagedSession) async throws {
        guard let chatMode else {
            return
        }

        guard let modeID = Self.acpModeCandidates(for: chatMode).first(where: { managed.availableModeIDs.contains($0) }) else {
            return
        }
        guard managed.currentModeID != modeID else {
            return
        }

        do {
            let response = try await managed.client.setMode(
                sessionId: managed.upstreamSessionId,
                modeId: modeID
            )
            if response.success {
                managed.currentModeID = modeID
                logger.info(
                    "ACP chat mode applied",
                    metadata: acpMetadata(
                        target: managed.target,
                        upstreamSessionId: managed.upstreamSessionId,
                        effectiveCwd: managed.effectiveCwd,
                        extra: ["mode_id": .string(modeID)]
                    )
                )
            }
        } catch {
            throw ACPError.launchFailed(error.localizedDescription)
        }
    }

    private func handleNotification(sessionKey: String, notification: JSONRPCNotification) async {
        guard notification.method == "session/update",
              let payload = decode(notification: notification, as: SessionUpdateNotification.self),
              var managed = sessions[sessionKey],
              payload.sessionId == managed.upstreamSessionId,
              var currentRun = managed.currentRun
        else {
            return
        }

        if currentRun.visibility == .hiddenPrimer {
            logHiddenPrimerUpdate(payload.update)
            managed.currentRun = currentRun
            sessions[sessionKey] = managed
            return
        }

        switch payload.update {
        case .agentMessageChunk(let block):
            let text = flatten(content: block)
            guard !text.isEmpty else { break }
            currentRun.assistantText += text
            await currentRun.onChunk(currentRun.assistantText)
        case .agentThoughtChunk(let block):
            let text = flatten(content: block)
            guard !text.isEmpty else { break }
            await currentRun.onEvent(
                AgentSessionEvent(
                    agentId: currentRun.agentID,
                    sessionId: currentRun.sloppySessionID,
                    type: .message,
                    message: AgentSessionMessage(
                        role: .assistant,
                        segments: [.init(kind: .thinking, text: text)]
                    )
                )
            )
        case .plan(let plan):
            let text = plan.entries
                .map { "[\($0.status)] \($0.content)" }
                .joined(separator: "\n")
            guard !text.isEmpty else { break }
            await currentRun.onEvent(
                AgentSessionEvent(
                    agentId: currentRun.agentID,
                    sessionId: currentRun.sloppySessionID,
                    type: .message,
                    message: AgentSessionMessage(
                        role: .assistant,
                        segments: [.init(kind: .thinking, text: text)]
                    )
                )
            )
        case .toolCall(let toolCall):
            let tracked = ACPTrackedToolCall(
                id: toolCall.toolCallId,
                title: toolCall.title ?? (toolCall.kind?.rawValue ?? "acp_tool"),
                kind: toolCall.kind,
                status: toolCall.status,
                content: toolCall.content,
                rawOutput: toolCall.rawOutput
            )
            currentRun.toolCalls[tracked.id] = tracked
            await currentRun.onEvent(
                tracked.asToolCallEvent(agentID: currentRun.agentID, sessionID: currentRun.sloppySessionID)
            )
            if toolCall.status == .completed || toolCall.status == .failed {
                await currentRun.onEvent(
                    tracked.asToolResultEvent(agentID: currentRun.agentID, sessionID: currentRun.sloppySessionID)
                )
            }
        case .toolCallUpdate(let details):
            guard var tracked = currentRun.toolCalls[details.toolCallId] else { break }
            tracked.apply(update: details)
            currentRun.toolCalls[details.toolCallId] = tracked
            if tracked.status == .completed || tracked.status == .failed {
                await currentRun.onEvent(
                    tracked.asToolResultEvent(agentID: currentRun.agentID, sessionID: currentRun.sloppySessionID)
                )
            }
        case .sessionInfoUpdate(let info):
            if let title = info.title {
                await currentRun.onEvent(
                    AgentSessionEvent(
                        agentId: currentRun.agentID,
                        sessionId: currentRun.sloppySessionID,
                        type: .runStatus,
                        runStatus: AgentRunStatusEvent(
                            stage: .thinking,
                            label: "Session updated",
                            details: "Title: \(title)"
                        )
                    )
                )
            }
        default:
            break
        }

        managed.currentRun = currentRun
        sessions[sessionKey] = managed
    }

    private func handlePermissionDecision(sessionKey: String, summary: String) async {
        guard let managed = sessions[sessionKey], let currentRun = managed.currentRun else {
            logger.info("ACP permission decision: \(summary)")
            return
        }

        if currentRun.visibility == .hiddenPrimer {
            logger.info("ACP hidden primer permission decision: \(summary)")
            return
        }

        await currentRun.onEvent(
            AgentSessionEvent(
                agentId: currentRun.agentID,
                sessionId: currentRun.sloppySessionID,
                type: .runStatus,
                runStatus: AgentRunStatusEvent(
                    stage: .thinking,
                    label: "Permission",
                    details: summary
                )
            )
        )
    }

    private func handlePermissionRequested(sessionKey: String, summary: String) async {
        guard let managed = sessions[sessionKey], let currentRun = managed.currentRun else {
            logger.info("ACP permission requested: \(summary)")
            return
        }

        if currentRun.visibility == .hiddenPrimer {
            logger.info("ACP hidden primer permission requested: \(summary)")
            return
        }

        await permissionNotificationSink?(
            currentRun.agentID,
            currentRun.sloppySessionID,
            summary
        )
        await currentRun.onEvent(
            AgentSessionEvent(
                agentId: currentRun.agentID,
                sessionId: currentRun.sloppySessionID,
                type: .runStatus,
                runStatus: AgentRunStatusEvent(
                    stage: .paused,
                    label: "Tool approval required",
                    details: summary
                )
            )
        )
    }

    private func logHiddenPrimerUpdate(_ update: SessionUpdate) {
        switch update {
        case .agentMessageChunk(let block), .agentThoughtChunk(let block):
            let text = flatten(content: block)
            if !text.isEmpty {
                logger.debug("Dropped ACP primer text update: \(text)")
            }
        case .plan(let plan):
            let text = plan.entries.map(\.content).joined(separator: " | ")
            if !text.isEmpty {
                logger.debug("Dropped ACP primer plan update: \(text)")
            }
        case .toolCall(let toolCall):
            logger.debug("Dropped ACP primer tool call update: \(toolCall.toolCallId)")
        case .toolCallUpdate(let details):
            logger.debug("Dropped ACP primer tool call update: \(details.toolCallId)")
        default:
            break
        }
    }

    private func probeTarget(_ target: CoreConfig.ACP.Target) async throws -> ACPTargetProbeResponse {
        do {
            let initialized = try await makeClientAndInitialize(target: target, effectiveCwd: resolveCwd(runtime: .init(type: .acp, acp: .init(targetId: target.id, cwd: target.cwd)), target: target), sessionKey: "probe::\(target.id)")
            let client = initialized.client
            let capabilities = initialized.initializeResponse.agentCapabilities
            let response = ACPTargetProbeResponse(
                ok: true,
                targetId: target.id,
                targetTitle: target.title,
                agentName: initialized.initializeResponse.agentInfo?.name,
                agentVersion: initialized.initializeResponse.agentInfo?.version,
                supportsSessionList: capabilities.sessionCapabilities?.list != nil,
                supportsLoadSession: capabilities.loadSession == true,
                supportsPromptImage: capabilities.promptCapabilities?.image == true,
                supportsMCPHTTP: capabilities.mcpCapabilities?.http == true,
                supportsMCPSSE: capabilities.mcpCapabilities?.sse == true,
                message: "ACP target is reachable."
            )
            await client.terminate()
            return response
        } catch {
            throw ACPError.launchFailed(error.localizedDescription)
        }
    }

    private func createManagedSession(
        sessionKey: String,
        target: CoreConfig.ACP.Target,
        transportFingerprint: String,
        effectiveCwd: String
    ) async throws -> ACPManagedSession {
        let initialized = try await makeClientAndInitialize(
            target: target,
            effectiveCwd: effectiveCwd,
            sessionKey: sessionKey
        )
        let client = initialized.client
        let notifications = await client.notificationsStream()
        let notificationTask = Task { [weak self] in
            for await notification in notifications {
                await self?.handleNotification(sessionKey: sessionKey, notification: notification)
            }
        }

        do {
            let newSession = try await client.newSession(
                workingDirectory: effectiveCwd,
                timeout: timeoutSeconds(target)
            )
            logger.info(
                "ACP upstream session created",
                metadata: acpMetadata(
                    target: target,
                    upstreamSessionId: newSession.sessionId,
                    effectiveCwd: effectiveCwd,
                    extra: [
                        "current_mode_id": .string(newSession.modes?.currentModeId ?? "unspecified"),
                        "available_modes": .string(Self.availableModeIDs(from: newSession.modes).sorted().joined(separator: ","))
                    ]
                )
            )
            return ACPManagedSession(
                client: client,
                target: target,
                transportFingerprint: transportFingerprint,
                effectiveCwd: effectiveCwd,
                upstreamSessionId: newSession.sessionId,
                agentName: initialized.initializeResponse.agentInfo?.name,
                agentVersion: initialized.initializeResponse.agentInfo?.version,
                supportsLoadSession: initialized.initializeResponse.agentCapabilities.loadSession == true,
                delegate: initialized.delegate,
                notificationTask: notificationTask,
                currentModeID: newSession.modes?.currentModeId,
                availableModeIDs: Self.availableModeIDs(from: newSession.modes),
                needsPrimer: true,
                currentRun: nil
            )
        } catch {
            notificationTask.cancel()
            await client.terminate()
            throw ACPError.launchFailed(error.localizedDescription)
        }
    }

    private func restoreManagedSession(
        sessionKey: String,
        target: CoreConfig.ACP.Target,
        transportFingerprint: String,
        effectiveCwd: String,
        upstreamSessionId: SessionId
    ) async throws -> ACPManagedSession {
        let initialized = try await makeClientAndInitialize(
            target: target,
            effectiveCwd: effectiveCwd,
            sessionKey: sessionKey
        )
        let client = initialized.client
        let notifications = await client.notificationsStream()
        let notificationTask = Task { [weak self] in
            for await notification in notifications {
                await self?.handleNotification(sessionKey: sessionKey, notification: notification)
            }
        }

        do {
            let loaded = try await client.loadSession(sessionId: upstreamSessionId, cwd: effectiveCwd)
            logger.info(
                "ACP upstream session restored",
                metadata: acpMetadata(
                    target: target,
                    upstreamSessionId: loaded.sessionId,
                    effectiveCwd: effectiveCwd,
                    extra: [
                        "requested_upstream_session_id": .string(upstreamSessionId.value),
                        "current_mode_id": .string(loaded.modes?.currentModeId ?? "unspecified"),
                        "available_modes": .string(Self.availableModeIDs(from: loaded.modes).sorted().joined(separator: ","))
                    ]
                )
            )
            return ACPManagedSession(
                client: client,
                target: target,
                transportFingerprint: transportFingerprint,
                effectiveCwd: effectiveCwd,
                upstreamSessionId: loaded.sessionId,
                agentName: initialized.initializeResponse.agentInfo?.name,
                agentVersion: initialized.initializeResponse.agentInfo?.version,
                supportsLoadSession: initialized.initializeResponse.agentCapabilities.loadSession == true,
                delegate: initialized.delegate,
                notificationTask: notificationTask,
                currentModeID: loaded.modes?.currentModeId,
                availableModeIDs: Self.availableModeIDs(from: loaded.modes),
                needsPrimer: false,
                currentRun: nil
            )
        } catch {
            notificationTask.cancel()
            await client.terminate()
            throw ACPError.launchFailed(error.localizedDescription)
        }
    }

    private func makeClientAndInitialize(
        target: CoreConfig.ACP.Target,
        effectiveCwd: String,
        sessionKey: String
    ) async throws -> (client: any ACPTransportClient, delegate: ACPClientDelegateAdapter, initializeResponse: InitializeResponse) {
        let client: any ACPTransportClient
        do {
            client = try clientFactory.build(target)
        } catch {
            throw ACPError.launchFailed(error.localizedDescription)
        }

        let delegate = ACPClientDelegateAdapter(
            permissionMode: target.permissionMode,
            permissionEventSink: { [weak self] summary in
                if summary.hasPrefix("requested: ") {
                    await self?.handlePermissionRequested(
                        sessionKey: sessionKey,
                        summary: String(summary.dropFirst("requested: ".count))
                    )
                } else {
                    await self?.handlePermissionDecision(sessionKey: sessionKey, summary: summary)
                }
            }
        )
        await client.setDelegate(delegate)

        do {
            let response = try await client.connect(
                workingDirectory: effectiveCwd,
                capabilities: ClientCapabilities(
                    fs: FileSystemCapabilities(readTextFile: true, writeTextFile: true),
                    terminal: true
                ),
                clientInfo: ClientInfo(name: "sloppy", title: "Sloppy ACP Gateway", version: "1.0.0"),
                timeout: timeoutSeconds(target)
            )
            logger.info(
                "ACP client initialized",
                metadata: acpMetadata(
                    target: target,
                    effectiveCwd: effectiveCwd,
                    extra: [
                        "agent_name": .string(response.agentInfo?.name ?? "unknown"),
                        "agent_version": .string(response.agentInfo?.version ?? "unknown"),
                        "supports_load_session": .stringConvertible(response.agentCapabilities.loadSession == true),
                        "supports_prompt_image": .stringConvertible(response.agentCapabilities.promptCapabilities?.image == true),
                        "supports_mcp_http": .stringConvertible(response.agentCapabilities.mcpCapabilities?.http == true),
                        "supports_mcp_sse": .stringConvertible(response.agentCapabilities.mcpCapabilities?.sse == true)
                    ]
                )
            )
            return (client, delegate, response)
        } catch {
            await client.terminate()
            throw ACPError.launchFailed(error.localizedDescription)
        }
    }

    private func terminateSession(forKey sessionKey: String) async {
        guard let managed = sessions[sessionKey] else {
            return
        }
        managed.notificationTask.cancel()
        await managed.client.terminate()
    }

    private static func availableModeIDs(from modes: ModesInfo?) -> Set<String> {
        Set((modes?.availableModes ?? []).map(\.id))
    }

    private static func acpModeCandidates(for chatMode: AgentChatMode) -> [String] {
        switch chatMode {
        case .build:
            return ["build", "code"]
        case .ask:
            return ["ask"]
        case .plan:
            return ["plan"]
        case .debug:
            return ["debug"]
        case .auto:
            return ["auto", "build", "code"]
        }
    }

    private func persistState(agentID: String, sloppySessionID: String, managed: ACPManagedSession) throws {
        try stateStore.save(
            ACPPersistedSessionState(
                targetId: managed.target.id,
                transportFingerprint: managed.transportFingerprint,
                effectiveCwd: managed.effectiveCwd,
                upstreamSessionId: managed.upstreamSessionId.value,
                agentName: managed.agentName,
                agentVersion: managed.agentVersion,
                supportsLoadSession: managed.supportsLoadSession
            ),
            agentID: agentID,
            sessionID: sloppySessionID
        )
    }

    private func acpMetadata(
        agentID: String? = nil,
        sloppySessionID: String? = nil,
        target: CoreConfig.ACP.Target? = nil,
        upstreamSessionId: SessionId? = nil,
        effectiveCwd: String? = nil,
        extra: Logging.Logger.Metadata = [:]
    ) -> Logging.Logger.Metadata {
        var metadata = extra
        metadata["component"] = .string("acp")
        if let agentID {
            metadata["agent_id"] = .string(agentID)
        }
        if let sloppySessionID {
            metadata["session_id"] = .string(sloppySessionID)
        }
        if let target {
            metadata["target_id"] = .string(target.id)
            metadata["target_title"] = .string(target.title)
            metadata["transport"] = .string(target.transport.rawValue)
            metadata["permission_mode"] = .string(target.permissionMode.rawValue)
            metadata["timeout_ms"] = .stringConvertible(target.timeoutMs)
        }
        if let upstreamSessionId {
            metadata["upstream_session_id"] = .string(upstreamSessionId.value)
        }
        if let effectiveCwd {
            metadata["cwd"] = .string(effectiveCwd)
        }
        return metadata
    }

    private func resolveTarget(for runtime: AgentRuntimeConfig) throws -> CoreConfig.ACP.Target {
        guard config.enabled else {
            throw ACPError.disabled
        }
        guard runtime.type == .acp else {
            throw ACPError.invalidRuntime
        }
        let targetId = runtime.acp?.targetId.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !targetId.isEmpty else {
            throw ACPError.invalidTarget("ACP target is required.")
        }
        guard let target = config.targets.first(where: { $0.id == targetId }) else {
            throw ACPError.targetNotFound(targetId)
        }
        guard target.enabled else {
            throw ACPError.targetDisabled(targetId)
        }

        switch target.transport {
        case .stdio:
            guard !target.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ACPError.invalidTarget("ACP target '\(targetId)' does not have a command.")
            }
        case .ssh:
            guard !(target.host ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ACPError.invalidTarget("ACP SSH target '\(targetId)' does not have a host.")
            }
            guard !(target.remoteCommand ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ACPError.invalidTarget("ACP SSH target '\(targetId)' does not have a remoteCommand.")
            }
        case .websocket:
            guard !(target.url ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ACPError.invalidTarget("ACP WebSocket target '\(targetId)' does not have a url.")
            }
        }

        return target
    }

    private func resolveCwd(runtime: AgentRuntimeConfig, target: CoreConfig.ACP.Target) -> String {
        let raw = runtime.acp?.cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw, !raw.isEmpty {
            return normalizePath(raw)
        }
        if let raw = target.cwd?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return normalizePath(raw)
        }
        return workspaceRootURL.path
    }

    private func normalizeTarget(_ probe: ACPProbeTarget) throws -> CoreConfig.ACP.Target {
        let id = probe.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = probe.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            throw ACPError.invalidTarget("ACP target id is required.")
        }
        guard !title.isEmpty else {
            throw ACPError.invalidTarget("ACP target title is required.")
        }

        let permissionMode = normalizePermissionMode(probe.permissionMode)
        let transport = probe.transport.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch transport {
        case "stdio":
            let command = (probe.command ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else {
                throw ACPError.invalidTarget("ACP target command is required.")
            }
            return CoreConfig.ACP.Target(
                id: id,
                title: title,
                transport: .stdio,
                command: command,
                arguments: probe.arguments,
                cwd: probe.cwd,
                environment: probe.environment,
                timeoutMs: probe.timeoutMs,
                enabled: probe.enabled,
                permissionMode: permissionMode
            )
        case "ssh":
            let host = probe.host?.trimmingCharacters(in: .whitespacesAndNewlines)
            let remoteCommand = probe.remoteCommand?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let host, !host.isEmpty else {
                throw ACPError.invalidTarget("ACP SSH target host is required.")
            }
            guard let remoteCommand, !remoteCommand.isEmpty else {
                throw ACPError.invalidTarget("ACP SSH target remoteCommand is required.")
            }
            return CoreConfig.ACP.Target(
                id: id,
                title: title,
                transport: .ssh,
                host: host,
                user: probe.user?.trimmingCharacters(in: .whitespacesAndNewlines),
                port: probe.port,
                identityFile: probe.identityFile?.trimmingCharacters(in: .whitespacesAndNewlines),
                strictHostKeyChecking: probe.strictHostKeyChecking,
                remoteCommand: remoteCommand,
                cwd: probe.cwd,
                timeoutMs: probe.timeoutMs,
                enabled: probe.enabled,
                permissionMode: permissionMode
            )
        case "websocket":
            let url = probe.url?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url, !url.isEmpty else {
                throw ACPError.invalidTarget("ACP WebSocket target url is required.")
            }
            return CoreConfig.ACP.Target(
                id: id,
                title: title,
                transport: .websocket,
                url: url,
                headers: probe.headers,
                cwd: probe.cwd,
                timeoutMs: probe.timeoutMs,
                enabled: probe.enabled,
                permissionMode: permissionMode
            )
        default:
            throw ACPError.invalidTarget("Unsupported ACP transport '\(probe.transport)'.")
        }
    }

    private func normalizePermissionMode(_ raw: String) -> CoreConfig.ACP.Target.PermissionMode {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return CoreConfig.ACP.Target.PermissionMode(rawValue: value) ?? .allowOnce
    }

    private func normalizePath(_ rawPath: String) -> String {
        if rawPath == "~" || rawPath.hasPrefix("~/") {
            let home = CoreConfig.resolvedHomeDirectoryPath()
            return rawPath == "~"
                ? home
                : URL(fileURLWithPath: home, isDirectory: true)
                    .appendingPathComponent(String(rawPath.dropFirst(2)), isDirectory: true)
                    .path
        }
        if rawPath.hasPrefix("/") {
            return rawPath
        }
        return workspaceRootURL.appendingPathComponent(rawPath, isDirectory: true).path
    }

    private func decode<T: Decodable>(notification: JSONRPCNotification, as type: T.Type) -> T? {
        guard let params = notification.params else {
            return nil
        }
        guard let data = try? JSONEncoder().encode(params) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func timeoutSeconds(_ target: CoreConfig.ACP.Target) -> TimeInterval {
        TimeInterval(max(1_000, target.timeoutMs)) / 1_000
    }

    private func flatten(content: ContentBlock) -> String {
        switch content {
        case .text(let text):
            return text.text
        case .resource(let resource):
            return resource.resource.text ?? ""
        case .resourceLink(let link):
            return link.uri
        case .image, .audio:
            return ""
        }
    }

    private func transportFingerprint(for target: CoreConfig.ACP.Target) throws -> String {
        struct FingerprintPayload: Encodable {
            let transport: String
            let command: String
            let arguments: [String]
            let host: String?
            let user: String?
            let port: Int?
            let identityFile: String?
            let strictHostKeyChecking: Bool
            let remoteCommand: String?
            let url: String?
            let headers: [String: String]
            let environment: [String: String]
            let timeoutMs: Int
            let permissionMode: String
        }

        let payload = FingerprintPayload(
            transport: target.transport.rawValue,
            command: target.command,
            arguments: target.arguments,
            host: target.host,
            user: target.user,
            port: target.port,
            identityFile: target.identityFile,
            strictHostKeyChecking: target.strictHostKeyChecking,
            remoteCommand: target.remoteCommand,
            url: target.url,
            headers: target.headers,
            environment: target.environment,
            timeoutMs: target.timeoutMs,
            permissionMode: target.permissionMode.rawValue
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        return String(decoding: data, as: UTF8.self)
    }

    static func sessionKey(agentID: String, sloppySessionID: String) -> String {
        "\(agentID)::\(sloppySessionID)"
    }
}

private actor ACPClientDelegateAdapter: ClientDelegate {
    private let fileSystemDelegate = FileSystemDelegate()
    private let terminalDelegate = TerminalDelegate()
    private let permissionMode: CoreConfig.ACP.Target.PermissionMode
    private let permissionEventSink: @Sendable (String) async -> Void

    init(
        permissionMode: CoreConfig.ACP.Target.PermissionMode,
        permissionEventSink: @escaping @Sendable (String) async -> Void
    ) {
        self.permissionMode = permissionMode
        self.permissionEventSink = permissionEventSink
    }

    func handleFileReadRequest(_ path: String, sessionId: String, line: Int?, limit: Int?) async throws -> ReadTextFileResponse {
        try await fileSystemDelegate.handleFileReadRequest(path, sessionId: sessionId, line: line, limit: limit)
    }

    func handleFileWriteRequest(_ path: String, content: String, sessionId: String) async throws -> WriteTextFileResponse {
        try await fileSystemDelegate.handleFileWriteRequest(path, content: content, sessionId: sessionId)
    }

    func handleTerminalCreate(command: String, sessionId: String, args: [String]?, cwd: String?, env: [EnvVariable]?, outputByteLimit: Int?) async throws -> CreateTerminalResponse {
        try await terminalDelegate.handleTerminalCreate(
            command: command,
            sessionId: sessionId,
            args: args,
            cwd: cwd,
            env: env,
            outputByteLimit: outputByteLimit
        )
    }

    func handleTerminalOutput(terminalId: TerminalId, sessionId: String) async throws -> TerminalOutputResponse {
        try await terminalDelegate.handleTerminalOutput(terminalId: terminalId, sessionId: sessionId)
    }

    func handleTerminalWaitForExit(terminalId: TerminalId, sessionId: String) async throws -> WaitForExitResponse {
        try await terminalDelegate.handleTerminalWaitForExit(terminalId: terminalId, sessionId: sessionId)
    }

    func handleTerminalKill(terminalId: TerminalId, sessionId: String) async throws -> KillTerminalResponse {
        try await terminalDelegate.handleTerminalKill(terminalId: terminalId, sessionId: sessionId)
    }

    func handleTerminalRelease(terminalId: TerminalId, sessionId: String) async throws -> ReleaseTerminalResponse {
        try await terminalDelegate.handleTerminalRelease(terminalId: terminalId, sessionId: sessionId)
    }

    func handlePermissionRequest(request: RequestPermissionRequest) async throws -> RequestPermissionResponse {
        let requested = Self.permissionRequestSummary(request)
        await permissionEventSink("requested: \(requested)")

        switch permissionMode {
        case .allowOnce:
            if let optionId = request.options?.first(where: { $0.optionId == PermissionDecision.allowOnce.rawValue })?.optionId {
                await permissionEventSink("\(requested) -> allow_once")
                return RequestPermissionResponse(outcome: PermissionOutcome(optionId: optionId))
            }
            await permissionEventSink("\(requested) -> denied (allow_once unavailable)")
            return RequestPermissionResponse(outcome: PermissionOutcome(cancelled: true))
        case .deny:
            await permissionEventSink("\(requested) -> denied")
            return RequestPermissionResponse(outcome: PermissionOutcome(cancelled: true))
        }
    }

    private static func permissionRequestSummary(_ request: RequestPermissionRequest) -> String {
        let message = request.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !message.isEmpty {
            return message
        }
        if let toolCallId = request.toolCall?.toolCallId {
            return "Permission requested for tool call \(toolCallId)"
        }
        return "Permission requested"
    }
}
