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
            : ToolErrorPayload(code: "acp_tool_failed", message: contentText.isEmpty ? "ACP tool call failed." : contentText, retryable: false)
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

private struct ACPCurrentRun: Sendable {
    let agentID: String
    let sloppySessionID: String
    let onChunk: @Sendable (String) async -> Void
    let onEvent: @Sendable (AgentSessionEvent) async -> Void
    var assistantText: String = ""
    var toolCalls: [String: ACPTrackedToolCall] = [:]
}

private struct ACPManagedSession {
    let client: Client
    let target: CoreConfig.ACP.Target
    let effectiveCwd: String
    let upstreamSessionId: SessionId
    let delegate: ACPClientDelegateAdapter
    let notificationTask: Task<Void, Never>
    var currentRun: ACPCurrentRun?
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

    private let logger: Logger
    private var config: CoreConfig.ACP
    private var workspaceRootURL: URL
    private var sessions: [String: ACPManagedSession] = [:]

    init(config: CoreConfig.ACP, workspaceRootURL: URL, logger: Logger = Logger(label: "sloppy.acp")) {
        self.config = config
        self.workspaceRootURL = workspaceRootURL
        self.logger = logger
    }

    func updateConfig(_ config: CoreConfig.ACP, workspaceRootURL: URL) async {
        let previousTargets = Dictionary(uniqueKeysWithValues: self.config.targets.map { ($0.id, $0) })
        self.config = config
        self.workspaceRootURL = workspaceRootURL

        for (key, session) in sessions {
            let nextTarget = config.targets.first { $0.id == session.target.id }
            if nextTarget == nil || nextTarget != previousTargets[session.target.id] || nextTarget?.enabled != true {
                await terminateSession(forKey: key)
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
        onChunk: @escaping @Sendable (String) async -> Void,
        onEvent: @escaping @Sendable (AgentSessionEvent) async -> Void
    ) async throws -> ACPMessageRunResult {
        let sessionKey = Self.sessionKey(agentID: agentID, sloppySessionID: sloppySessionID)
        let target = try resolveTarget(for: runtime)
        let effectiveCwd = resolveCwd(runtime: runtime, target: target)

        let hadState = sessions[sessionKey] != nil
        let needsReset = try await resetSessionIfNeeded(sessionKey: sessionKey, target: target, effectiveCwd: effectiveCwd)
        let didResetContext = (!hadState && localSessionHadPriorMessages) || needsReset

        if sessions[sessionKey] == nil {
            let managed = try await createManagedSession(
                sessionKey: sessionKey,
                target: target,
                effectiveCwd: effectiveCwd
            )
            sessions[sessionKey] = managed
        }

        guard var managed = sessions[sessionKey] else {
            throw ACPError.protocolError("ACP session was not created.")
        }

        managed.currentRun = ACPCurrentRun(
            agentID: agentID,
            sloppySessionID: sloppySessionID,
            onChunk: onChunk,
            onEvent: onEvent
        )
        sessions[sessionKey] = managed

        defer {
            Task {
                await self.clearCurrentRun(for: sessionKey)
            }
        }

        let response: SessionPromptResponse
        do {
            response = try await managed.client.sendPrompt(
                sessionId: managed.upstreamSessionId,
                content: content
            )
        } catch {
            throw ACPError.launchFailed(error.localizedDescription)
        }

        let assistantText = sessions[sessionKey]?.currentRun?.assistantText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ACPMessageRunResult(
            assistantText: assistantText,
            stopReason: response.stopReason,
            didResetContext: didResetContext
        )
    }

    func controlSession(agentID: String, sloppySessionID: String, action: AgentRunControlAction) async throws {
        let sessionKey = Self.sessionKey(agentID: agentID, sloppySessionID: sloppySessionID)
        guard let managed = sessions[sessionKey] else {
            if action == .interrupt {
                return
            }
            throw ACPError.unsupportedControl(action.rawValue)
        }

        switch action {
        case .interrupt:
            do {
                try await managed.client.cancelSession(sessionId: managed.upstreamSessionId)
            } catch {
                throw ACPError.launchFailed(error.localizedDescription)
            }
        case .pause, .resume:
            throw ACPError.unsupportedControl(action.rawValue)
        }
    }

    func removeSession(agentID: String, sloppySessionID: String) async {
        let sessionKey = Self.sessionKey(agentID: agentID, sloppySessionID: sloppySessionID)
        await terminateSession(forKey: sessionKey)
        sessions.removeValue(forKey: sessionKey)
    }

    private func clearCurrentRun(for sessionKey: String) {
        guard var managed = sessions[sessionKey] else {
            return
        }
        managed.currentRun = nil
        sessions[sessionKey] = managed
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
            await currentRun.onEvent(tracked.asToolCallEvent(agentID: currentRun.agentID, sessionID: currentRun.sloppySessionID))
            if toolCall.status == .completed || toolCall.status == .failed {
                await currentRun.onEvent(tracked.asToolResultEvent(agentID: currentRun.agentID, sessionID: currentRun.sloppySessionID))
            }
        case .toolCallUpdate(let details):
            guard var tracked = currentRun.toolCalls[details.toolCallId] else { break }
            tracked.apply(update: details)
            currentRun.toolCalls[details.toolCallId] = tracked
            if tracked.status == .completed || tracked.status == .failed {
                await currentRun.onEvent(tracked.asToolResultEvent(agentID: currentRun.agentID, sessionID: currentRun.sloppySessionID))
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

    private func probeTarget(_ target: CoreConfig.ACP.Target) async throws -> ACPTargetProbeResponse {
        let client: Client
        do {
            let created = try await makeClientAndInitialize(target: target, effectiveCwd: resolveCwd(runtime: .init(type: .acp, acp: .init(targetId: target.id, cwd: target.cwd)), target: target))
            client = created.client
            let capabilities = created.initializeResponse.agentCapabilities
            let response = ACPTargetProbeResponse(
                ok: true,
                targetId: target.id,
                targetTitle: target.title,
                agentName: created.initializeResponse.agentInfo?.name,
                agentVersion: created.initializeResponse.agentInfo?.version,
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
        effectiveCwd: String
    ) async throws -> ACPManagedSession {
        let initialized = try await makeClientAndInitialize(target: target, effectiveCwd: effectiveCwd)
        let client = initialized.client
        let newSession: NewSessionResponse
        do {
            newSession = try await client.newSession(workingDirectory: effectiveCwd, timeout: timeoutSeconds(target))
        } catch {
            await client.terminate()
            throw ACPError.launchFailed(error.localizedDescription)
        }

        let notifications = await client.notifications
        let notificationTask = Task { [weak self] in
            for await notification in notifications {
                await self?.handleNotification(sessionKey: sessionKey, notification: notification)
            }
        }

        return ACPManagedSession(
            client: client,
            target: target,
            effectiveCwd: effectiveCwd,
            upstreamSessionId: newSession.sessionId,
            delegate: initialized.delegate,
            notificationTask: notificationTask,
            currentRun: nil
        )
    }

    private func makeClientAndInitialize(
        target: CoreConfig.ACP.Target,
        effectiveCwd: String
    ) async throws -> (client: Client, delegate: ACPClientDelegateAdapter, initializeResponse: InitializeResponse) {
        let client = Client()
        let delegate = ACPClientDelegateAdapter()
        await client.setDelegate(delegate)

        do {
            try await client.launch(
                agentPath: target.command,
                arguments: target.arguments,
                workingDirectory: effectiveCwd,
                environment: target.environment
            )
            let response = try await client.initialize(
                capabilities: ClientCapabilities(
                    fs: FileSystemCapabilities(readTextFile: true, writeTextFile: true),
                    terminal: true
                ),
                clientInfo: ClientInfo(name: "sloppy", title: "Sloppy ACP Gateway", version: "1.0.0"),
                timeout: timeoutSeconds(target)
            )
            return (client, delegate, response)
        } catch {
            await client.terminate()
            throw ACPError.launchFailed(error.localizedDescription)
        }
    }

    private func resetSessionIfNeeded(
        sessionKey: String,
        target: CoreConfig.ACP.Target,
        effectiveCwd: String
    ) async throws -> Bool {
        guard let managed = sessions[sessionKey] else {
            return false
        }
        guard managed.target == target, managed.effectiveCwd == effectiveCwd else {
            await terminateSession(forKey: sessionKey)
            sessions.removeValue(forKey: sessionKey)
            return true
        }
        return false
    }

    private func terminateSession(forKey sessionKey: String) async {
        guard let managed = sessions[sessionKey] else {
            return
        }
        managed.notificationTask.cancel()
        await managed.client.terminate()
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
        guard !target.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ACPError.invalidTarget("ACP target '\(targetId)' does not have a command.")
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
        let command = probe.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            throw ACPError.invalidTarget("ACP target id is required.")
        }
        guard !title.isEmpty else {
            throw ACPError.invalidTarget("ACP target title is required.")
        }
        guard probe.transport.lowercased() == "stdio" else {
            throw ACPError.invalidTarget("Only stdio ACP targets are supported.")
        }
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
            enabled: probe.enabled
        )
    }

    private func normalizePath(_ rawPath: String) -> String {
        if rawPath == "~" || rawPath.hasPrefix("~/") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
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
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        guard let data = try? encoder.encode(params) else {
            return nil
        }
        return try? decoder.decode(type, from: data)
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

    static func sessionKey(agentID: String, sloppySessionID: String) -> String {
        "\(agentID)::\(sloppySessionID)"
    }
}

private actor ACPClientDelegateAdapter: ClientDelegate {
    private let fileSystemDelegate = FileSystemDelegate()
    private let terminalDelegate = TerminalDelegate()

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
        if let optionId = request.options?.first(where: { $0.optionId == PermissionDecision.allowOnce.rawValue })?.optionId
            ?? request.options?.first(where: { $0.optionId == PermissionDecision.allowAlways.rawValue })?.optionId
            ?? request.options?.first?.optionId {
            return RequestPermissionResponse(outcome: PermissionOutcome(optionId: optionId))
        }
        return RequestPermissionResponse(outcome: PermissionOutcome(cancelled: true))
    }
}
