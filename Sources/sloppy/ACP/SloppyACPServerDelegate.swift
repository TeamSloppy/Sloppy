import ACP
import ACPModel
import Foundation
import Protocols

final class SloppyACPServerDelegate: AgentDelegate, @unchecked Sendable {
    typealias UpdateSender = @Sendable (SessionId, SessionUpdate) async throws -> Void

    enum ServerError: Error, LocalizedError {
        case disabled
        case missingAgent
        case invalidSession
        case invalidPrompt

        var errorDescription: String? {
            switch self {
            case .disabled:
                return "Sloppy ACP server is disabled in config."
            case .missingAgent:
                return "A Sloppy agent ID is required for ACP server mode."
            case .invalidSession:
                return "ACP session does not map to a Sloppy agent session."
            case .invalidPrompt:
                return "ACP prompt did not contain supported text content."
            }
        }
    }

    private let service: CoreService
    private let agentID: String
    private let defaultCwd: String?
    private let sendUpdate: UpdateSender
    private let isoFormatter = ISO8601DateFormatter()

    init(
        service: CoreService,
        agentID: String,
        defaultCwd: String?,
        sendUpdate: @escaping UpdateSender
    ) {
        self.service = service
        self.agentID = agentID
        self.defaultCwd = defaultCwd
        self.sendUpdate = sendUpdate
    }

    func handleInitialize(_ request: InitializeRequest) async throws -> InitializeResponse {
        _ = request
        return InitializeResponse(
            protocolVersion: 1,
            agentCapabilities: AgentCapabilities(
                loadSession: true,
                promptCapabilities: PromptCapabilities(image: false),
                sessionCapabilities: SessionCapabilities(
                    list: SessionListCapabilities(),
                    resume: SessionResumeCapabilities()
                )
            ),
            agentInfo: AgentInfo(
                name: "sloppy",
                version: SloppyVersion.current,
                title: "Sloppy"
            )
        )
    }

    func handleNewSession(_ request: NewSessionRequest) async throws -> NewSessionResponse {
        try await validateReady()
        let title = titleForSession(cwd: request.cwd)
        let summary = try await service.createAgentSession(
            agentID: agentID,
            request: AgentSessionCreateRequest(title: title)
        )
        try await applyWorkingDirectory(request.cwd, sessionID: summary.id)
        try await sendUpdate(
            SessionId(summary.id),
            .sessionInfoUpdate(SessionInfoUpdate(title: summary.title, updatedAt: isoFormatter.string(from: summary.updatedAt)))
        )
        return NewSessionResponse(
            sessionId: SessionId(summary.id),
            modes: modesInfo(),
            models: nil
        )
    }

    func handlePrompt(_ request: SessionPromptRequest) async throws -> SessionPromptResponse {
        try await validateReady()
        let sessionID = request.sessionId.value
        _ = try await service.getAgentSession(agentID: agentID, sessionID: sessionID)

        let content = Self.promptText(from: request.prompt)
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServerError.invalidPrompt
        }

        let stream = try await service.streamAgentSessionEvents(agentID: agentID, sessionID: sessionID)
        let deltaBox = ACPServerDeltaBox()
        let streamTask = Task {
            for await update in stream {
                if Task.isCancelled {
                    break
                }
                await self.forward(update: update, acpSessionID: request.sessionId, deltaBox: deltaBox)
            }
        }

        let response = try await service.postAgentSessionMessage(
            agentID: agentID,
            sessionID: sessionID,
            request: AgentSessionPostMessageRequest(
                userId: "acp",
                content: content,
                mode: .defaultMode
            )
        )
        streamTask.cancel()

        if !(await deltaBox.didSendDelta) {
            let fallback = Self.assistantText(from: response.appendedEvents)
            if !fallback.isEmpty {
                try await sendUpdate(request.sessionId, .agentMessageChunk(.text(TextContent(text: fallback))))
            }
        }

        return SessionPromptResponse(stopReason: .endTurn)
    }

    func handleCancel(_ sessionId: SessionId) async throws {
        _ = try await service.getAgentSession(agentID: agentID, sessionID: sessionId.value)
        _ = try await service.controlAgentSession(
            agentID: agentID,
            sessionID: sessionId.value,
            request: AgentSessionControlRequest(action: .interruptTree, requestedBy: "acp")
        )
    }

    func handleLoadSession(_ request: LoadSessionRequest) async throws -> LoadSessionResponse {
        try await validateReady()
        let detail = try await service.getAgentSession(agentID: agentID, sessionID: request.sessionId.value)
        if let cwd = request.cwd {
            try await applyWorkingDirectory(cwd, sessionID: detail.summary.id)
        }
        return LoadSessionResponse(
            sessionId: request.sessionId,
            modes: modesInfo(),
            models: nil
        )
    }

    func handleListSessions(_ request: ListSessionsRequest) async throws -> ListSessionsResponse {
        try await validateReady()
        let summaries = try await service.listAgentSessions(agentID: agentID, limit: 100, offset: 0)
        let cwd = request.cwd ?? defaultCwd ?? FileManager.default.currentDirectoryPath
        return ListSessionsResponse(
            sessions: summaries.map { summary in
                SessionInfo(
                    sessionId: SessionId(summary.id),
                    cwd: cwd,
                    title: summary.title,
                    updatedAt: isoFormatter.string(from: summary.updatedAt)
                )
            },
            nextCursor: nil
        )
    }

    private func validateReady() async throws {
        let config = await service.getConfig()
        guard config.acp.server.enabled else {
            throw ServerError.disabled
        }
        guard !agentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServerError.missingAgent
        }
        _ = try await service.getAgent(id: agentID)
    }

    private func applyWorkingDirectory(_ requestedCwd: String?, sessionID: String) async throws {
        let cwd = requestedCwd?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = cwd?.isEmpty == false ? cwd! : (defaultCwd ?? "")
        guard !resolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        _ = try await service.addAgentSessionDirectory(
            agentID: agentID,
            sessionID: sessionID,
            request: AgentSessionDirectoryRequest(path: resolved)
        )
    }

    private func forward(update: AgentSessionStreamUpdate, acpSessionID: SessionId, deltaBox: ACPServerDeltaBox) async {
        do {
            switch update.kind {
            case .sessionDelta:
                guard let message = update.message, !message.isEmpty else { return }
                await deltaBox.markDeltaSent()
                try await sendUpdate(acpSessionID, .agentMessageChunk(.text(TextContent(text: message))))
            case .sessionEvent:
                guard let event = update.event else { return }
                try await forward(event: event, acpSessionID: acpSessionID)
            case .sessionReady, .heartbeat, .sessionClosed, .sessionError:
                return
            }
        } catch {
            return
        }
    }

    private func forward(event: AgentSessionEvent, acpSessionID: SessionId) async throws {
        switch event.type {
        case .message:
            guard let message = event.message else { return }
            let text = Self.text(from: message)
            guard !text.isEmpty else { return }
            if message.role == .assistant {
                try await sendUpdate(acpSessionID, .agentMessageChunk(.text(TextContent(text: text))))
            } else if message.role == .system {
                try await sendUpdate(acpSessionID, .agentThoughtChunk(.text(TextContent(text: text))))
            }
        case .runStatus:
            guard let status = event.runStatus else { return }
            let parts = [status.label, status.details, status.expandedText].compactMap { $0 }.filter { !$0.isEmpty }
            guard !parts.isEmpty else { return }
            try await sendUpdate(acpSessionID, .agentThoughtChunk(.text(TextContent(text: parts.joined(separator: "\n")))))
        case .toolCall:
            guard let call = event.toolCall else { return }
            try await sendUpdate(
                acpSessionID,
                .toolCall(
                    ToolCallUpdate(
                        toolCallId: call.tool,
                        status: .inProgress,
                        title: call.tool,
                        kind: Self.toolKind(for: call.tool),
                        content: [.content(.text(TextContent(text: Self.toolArgumentsText(call.arguments))))]
                    )
                )
            )
        case .toolResult:
            guard let result = event.toolResult else { return }
            try await sendUpdate(
                acpSessionID,
                .toolCallUpdate(
                    ToolCallUpdateDetails(
                        toolCallId: result.tool,
                        status: result.ok ? .completed : .failed,
                        content: [.content(.text(TextContent(text: Self.toolResultText(result))))]
                    )
                )
            )
        default:
            return
        }
    }

    private func titleForSession(cwd: String) -> String {
        let raw = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return "ACP Session"
        }
        return "ACP \(URL(fileURLWithPath: raw).lastPathComponent)"
    }

    private func modesInfo() -> ModesInfo {
        ModesInfo(
            currentModeId: "build",
            availableModes: [
                ModeInfo(id: "build", name: "Build"),
                ModeInfo(id: "ask", name: "Ask"),
                ModeInfo(id: "plan", name: "Plan"),
                ModeInfo(id: "debug", name: "Debug")
            ]
        )
    }

    private static func promptText(from blocks: [ContentBlock]) -> String {
        blocks.compactMap { block in
            switch block {
            case .text(let text):
                return text.text
            case .resourceLink(let link):
                return link.uri
            case .resource(let resource):
                switch resource.resource {
                case .text(let text):
                    return text.text
                case .blob(let blob):
                    return blob.uri
                }
            case .image, .audio:
                return nil
            }
        }
        .joined(separator: "\n\n")
    }

    private static func assistantText(from events: [AgentSessionEvent]) -> String {
        events
            .compactMap { event -> String? in
                guard event.type == .message,
                      event.message?.role == .assistant,
                      let message = event.message
                else { return nil }
                return text(from: message)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func text(from message: AgentSessionMessage) -> String {
        message.segments.compactMap(\.text).joined(separator: "\n")
    }

    private static func toolKind(for tool: String) -> ToolKind {
        let lowered = tool.lowercased()
        if lowered.contains("read") { return .read }
        if lowered.contains("write") || lowered.contains("edit") { return .edit }
        if lowered.contains("grep") || lowered.contains("search") || lowered.contains("list") { return .search }
        if lowered.contains("exec") || lowered.contains("terminal") { return .execute }
        return .other
    }

    private static func toolArgumentsText(_ arguments: [String: JSONValue]) -> String {
        guard let data = try? JSONEncoder().encode(arguments),
              let text = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return text
    }

    private static func toolResultText(_ result: AgentToolResultEvent) -> String {
        if let error = result.error {
            return error.message
        }
        guard let data = result.data,
              let encoded = try? JSONEncoder().encode(data),
              let text = String(data: encoded, encoding: .utf8)
        else {
            return result.ok ? "Done." : "Failed."
        }
        return text
    }
}

private actor ACPServerDeltaBox {
    private(set) var didSendDelta = false

    func markDeltaSent() {
        didSendDelta = true
    }
}
