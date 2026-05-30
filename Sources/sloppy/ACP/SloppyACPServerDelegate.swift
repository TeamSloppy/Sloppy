import ACP
import ACPModel
import Foundation
import Logging
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
    private let logger: Logging.Logger

    init(
        service: CoreService,
        agentID: String,
        defaultCwd: String?,
        logger: Logging.Logger? = nil,
        sendUpdate: @escaping UpdateSender
    ) {
        self.service = service
        self.agentID = agentID
        self.defaultCwd = defaultCwd
        self.logger = logger ?? Logging.Logger(label: "sloppy.acp.server.delegate")
        self.sendUpdate = sendUpdate
    }

    func handleInitialize(_ request: InitializeRequest) async throws -> InitializeResponse {
        logger.info(
            "handle.request.initialize",
            metadata: [
                "request": .string(String(reflecting: request))
            ]
        )
        do {
            _ = try await service.getAgent(id: agentID)
            let response = InitializeResponse(
                protocolVersion: 1,
                agentCapabilities: AgentCapabilities(
                    loadSession: true,
                    promptCapabilities: PromptCapabilities(image: false),
                    sessionCapabilities: SessionCapabilities(
                        list: SessionListCapabilities(),
                    )
                ),
                agentInfo: AgentInfo(
                    name: "sloppy",
                    version: SloppyVersion.current,
                    title: "Sloppy"
                )
            )

            logger.info(
                "handle.response.initialize",
                metadata: [
                    "response": .string(String(reflecting: response))
                ]
            )

            return response
        } catch {
            logger.error(
                "handle.request.initialize",
                metadata: [
                    "request": .string(String(reflecting: request)),
                    "error": .string(error.localizedDescription),
                ]
            )
            throw error
        }
    }

    func handleNewSession(_ request: NewSessionRequest) async throws -> NewSessionResponse {
        logger.info(
            "handle.request.newSession",
            metadata: [
                "request": .string(String(reflecting: request))
            ]
        )

        do {
            try await validateReady()
            let title = titleForSession(cwd: request.cwd)
            let summary = try await service.createAgentSession(
                agentID: agentID,
                request: AgentSessionCreateRequest(title: title)
            )
            try await applyWorkingDirectory(request.cwd, sessionID: summary.id)
            try await sendUpdate(
                SessionId(summary.id),
                .sessionInfoUpdate(
                    SessionInfoUpdate(
                        title: summary.title,
                        updatedAt: isoFormatter.string(from: summary.updatedAt)
                    )
                )
            )
            let response = NewSessionResponse(
                sessionId: SessionId(summary.id),
                modes: nil,
                models: nil
            )

            logger.info(
                "handle.response.newSession",
                metadata: [
                    "response": .string(String(reflecting: response))
                ]
            )

            return response
        } catch {
            logger.error(
                "handle.request.newSession",
                metadata: [
                    "request": .string(String(reflecting: request)),
                    "error": .string(error.localizedDescription),
                ]
            )
            throw error
        }
    }

    func handlePrompt(_ request: SessionPromptRequest) async throws -> SessionPromptResponse {
        logger.info(
            "handle.request.prompt",
            metadata: [
                "request": .string(String(reflecting: request))
            ]
        )
        do {
            try await validateReady()
            let sessionID = request.sessionId.value
            _ = try await service.getAgentSession(agentID: agentID, sessionID: sessionID)

            let content = Self.promptText(from: request.prompt)
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ServerError.invalidPrompt
            }

            let stream = try await service.streamAgentSessionEvents(
                agentID: agentID, sessionID: sessionID)
            let deltaBox = ACPServerDeltaBox()
            let streamTask = Task {
                for await update in stream {
                    if Task.isCancelled {
                        break
                    }
                    await self.forward(
                        update: update,
                        acpSessionID: request.sessionId,
                        deltaBox: deltaBox
                    )
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
                    try await sendUpdate(
                        request.sessionId, .agentMessageChunk(.text(TextContent(text: fallback))))
                }
            }

            logger.info(
                "handle.response.prompt",
                metadata: [
                    "stopReason": .string("end turn"),
                    "sessionId": .string(sessionID),
                ]
            )

            return SessionPromptResponse(stopReason: .endTurn)
        } catch {
            logger.error(
                "handle.request.prompt",
                metadata: [
                    "request": .string(String(reflecting: request)),
                    "error": .string(error.localizedDescription),
                ]
            )
            throw error
        }
    }

    func handleCancel(_ sessionId: SessionId) async throws {
        logger.info(
            "handle.request.cancel",
            metadata: [
                "sessionId": .string(sessionId.value)
            ]
        )
        do {
            _ = try await service.getAgentSession(agentID: agentID, sessionID: sessionId.value)
            _ = try await service.controlAgentSession(
                agentID: agentID,
                sessionID: sessionId.value,
                request: AgentSessionControlRequest(action: .interruptTree, requestedBy: "acp")
            )

            logger.info(
                "handle.response.cancel",
                metadata: [
                    "sessionId": .string(sessionId.value)
                ]
            )
        } catch {
            logger.error(
                "handle.request.cancel",
                metadata: [
                    "sessionId": .string(sessionId.value),
                    "error": .string(error.localizedDescription),
                ]
            )
            throw error
        }
    }

    func handleLoadSession(_ request: LoadSessionRequest) async throws -> LoadSessionResponse {
        logger.info(
            "handle.request.loadSession",
            metadata: [
                "request": .string(String(reflecting: request))
            ]
        )

        do {
            try await validateReady()
            let detail = try await service.getAgentSession(
                agentID: agentID, sessionID: request.sessionId.value)
            if let cwd = request.cwd {
                try await applyWorkingDirectory(cwd, sessionID: detail.summary.id)
            }
            for event in detail.events {
                try await forward(event: event, acpSessionID: request.sessionId)
            }
            let response = LoadSessionResponse(
                sessionId: request.sessionId,
                modes: nil,
                models: nil
            )

            logger.info(
                "handle.response.loadSession",
                metadata: [
                    "response": .string(String(reflecting: response))
                ]
            )

            return response
        } catch {
            logger.error(
                "handle.request.loadSession",
                metadata: [
                    "request": .string(String(reflecting: request)),
                    "error": .string(error.localizedDescription),
                ]
            )
            throw error
        }
    }

    func handleListSessions(_ request: ListSessionsRequest) async throws -> ListSessionsResponse {
        logger.info(
            "handle.request.listSessions",
            metadata: [
                "request": .string(String(reflecting: request))
            ]
        )

        let cursor = Int(request.cursor ?? "0") ?? 0
        let limit = 30

        do {
            try await validateReady()
            let summaries = try await service.listAgentSessions(
                agentID: agentID,
                limit: limit,
                offset: cursor
            )
            let cwd = request.cwd ?? defaultCwd ?? FileManager.default.currentDirectoryPath
            let response = ListSessionsResponse(
                sessions: summaries.map { summary in
                    SessionInfo(
                        sessionId: SessionId(summary.id),
                        cwd: cwd,
                        title: summary.title,
                        updatedAt: isoFormatter.string(from: summary.updatedAt)
                    )
                },
                nextCursor: summaries.count == limit ? String(cursor + limit) : nil
            )

            logger.info(
                "handle.response.listSessions",
                metadata: [
                    "response": .string(String(reflecting: response))
                ]
            )

            return response
        } catch {
            logger.error(
                "handle.request.listSessions",
                metadata: [
                    "error": .string(error.localizedDescription)
                ]
            )
            throw error
        }
    }
}

extension SloppyACPServerDelegate {
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
        let resolved =
            cwd?.isEmpty == false ? cwd! : (defaultCwd ?? "")
        guard !resolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        _ = try await service.addAgentSessionDirectory(
            agentID: agentID,
            sessionID: sessionID,
            request: AgentSessionDirectoryRequest(path: resolved)
        )
    }

    private func forward(
        update: AgentSessionStreamUpdate,
        acpSessionID: SessionId,
        deltaBox: ACPServerDeltaBox
    ) async {
        do {
            switch update.kind {
            case .sessionDelta:
                guard let message = update.message, !message.isEmpty else { return }
                await deltaBox.markDeltaSent()
                try await sendUpdate(
                    acpSessionID, .agentMessageChunk(.text(TextContent(text: message))))
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
                try await sendUpdate(
                    acpSessionID, .agentMessageChunk(.text(TextContent(text: text))))
            } else if message.role == .user {
                try await sendUpdate(
                    acpSessionID, .userMessageChunk(.text(TextContent(text: text))))
            } else if message.role == .system {
                try await sendUpdate(
                    acpSessionID, .agentThoughtChunk(.text(TextContent(text: text))))
            }
        case .runStatus:
            guard let status = event.runStatus else { return }
            let parts = [status.label, status.details, status.expandedText].compactMap { $0 }.filter
            { !$0.isEmpty }
            guard !parts.isEmpty else { return }
            try await sendUpdate(
                acpSessionID,
                .agentThoughtChunk(.text(TextContent(text: parts.joined(separator: "\n")))))
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
                        content: [
                            .content(
                                .text(TextContent(text: Self.toolArgumentsText(call.arguments))))
                        ]
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
        if lowered.contains("grep") || lowered.contains("search") || lowered.contains("list") {
            return .search
        }
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
