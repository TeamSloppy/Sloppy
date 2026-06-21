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
        self.logger = logger ?? .sloppy(label: "sloppy.acp.server.delegate")
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
                    promptCapabilities: PromptCapabilities(image: true),
                    sessionCapabilities: SessionCapabilities(
                        fork: SessionForkCapabilities(),
                        list: SessionListCapabilities(),
                        resume: SessionResumeCapabilities(),
                    )
                ),
                agentInfo: AgentInfo(
                    name: "sloppy",
                    version: SloppyVersion.current,
                    title: "Sloppy"
                ),
                authMethods: []
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

    func handleAuthorization(_ request: AuthorizationRequest) async throws -> AuthorizationResponse {
        logger.info(
            "handle.request.authorization",
            metadata: [
                "request": .string(String(reflecting: request))
            ]
        )
        try await validateReady()
        return AuthorizationResponse()
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
            let project = await projectForSession(cwd: request.cwd)
            let summary = try await service.createAgentSession(
                agentID: agentID,
                request: AgentSessionCreateRequest(title: title, projectId: project?.id)
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
                models: try await modelsInfo()
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

            let prompt = Self.promptPayload(from: request.prompt)
            guard !prompt.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !prompt.attachments.isEmpty else {
                throw ServerError.invalidPrompt
            }

            let stream = try await service.streamAgentSessionEvents(
                agentID: agentID, sessionID: sessionID)
            let deltaTracker = ACPServerDeltaTracker()
            let thinkBlockRouter = ACPServerThinkBlockRouter()
            let toolCallTracker = ACPServerToolCallTracker()
            let streamTask = Task {
                for await update in stream {
                    if Task.isCancelled {
                        break
                    }
                    await self.forward(
                        update: update,
                        acpSessionID: request.sessionId,
                        deltaTracker: deltaTracker,
                        thinkBlockRouter: thinkBlockRouter,
                        toolCallTracker: toolCallTracker
                    )
                }
            }

            let response = try await service.postAgentSessionMessage(
                agentID: agentID,
                sessionID: sessionID,
                request: AgentSessionPostMessageRequest(
                    userId: "acp",
                    content: prompt.content,
                    attachments: prompt.attachments,
                    mode: .defaultMode
                )
            )
            streamTask.cancel()

            if !(await deltaTracker.didSendDelta) {
                let fallback = Self.assistantText(from: response.appendedEvents)
                if !fallback.isEmpty {
                    try await forwardAssistantText(
                        fallback,
                        acpSessionID: request.sessionId,
                        thinkBlockRouter: thinkBlockRouter,
                        flush: true
                    )
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

    func handleSetModel(_ request: SetModelRequest) async throws -> SetModelResponse {
        logger.info(
            "handle.request.setModel",
            metadata: [
                "request": .string(String(reflecting: request))
            ]
        )
        do {
            try await validateReady()
            _ = try await service.getAgentSession(agentID: agentID, sessionID: request.sessionId.value)
            let config = try await service.getAgentConfig(agentID: agentID)
            guard config.runtime.type == .native,
                  Self.modelIDs(from: config.availableModels).contains(request.modelId)
            else {
                return SetModelResponse(success: false)
            }

            _ = try await service.updateAgentConfig(
                agentID: agentID,
                request: AgentConfigUpdateRequest(
                    role: config.role,
                    selectedModel: request.modelId,
                    documents: config.documents,
                    heartbeat: config.heartbeat,
                    channelSessions: config.channelSessions,
                    runtime: config.runtime
                )
            )

            let response = SetModelResponse(success: true)
            logger.info(
                "handle.response.setModel",
                metadata: [
                    "response": .string(String(reflecting: response)),
                    "sessionId": .string(request.sessionId.value),
                    "modelId": .string(request.modelId),
                ]
            )
            return response
        } catch {
            logger.error(
                "handle.request.setModel",
                metadata: [
                    "request": .string(String(reflecting: request)),
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
            let thinkBlockRouter = ACPServerThinkBlockRouter()
            let toolCallTracker = ACPServerToolCallTracker()
            for event in detail.events {
                try await forward(
                    event: event,
                    acpSessionID: request.sessionId,
                    thinkBlockRouter: thinkBlockRouter,
                    toolCallTracker: toolCallTracker
                )
            }
            let response = LoadSessionResponse(
                sessionId: request.sessionId,
                modes: nil,
                models: try await modelsInfo()
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
        let resolved = resolvedWorkingDirectory(requestedCwd)
        guard !resolved.isEmpty else {
            return
        }
        _ = try await service.addAgentSessionDirectory(
            agentID: agentID,
            sessionID: sessionID,
            request: AgentSessionDirectoryRequest(path: resolved)
        )
    }

    private func projectForSession(cwd requestedCwd: String?) async -> ProjectRecord? {
        let resolved = resolvedWorkingDirectory(requestedCwd)
        guard !resolved.isEmpty else {
            return nil
        }
        do {
            return try await service.resolveOrCreateProjectForCurrentDirectory(resolved)
        } catch {
            logger.warning(
                "ACP session project resolution failed",
                metadata: [
                    "cwd": .string(resolved),
                    "error": .string(error.localizedDescription)
                ]
            )
            return nil
        }
    }

    private func resolvedWorkingDirectory(_ requestedCwd: String?) -> String {
        let cwd = requestedCwd?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = cwd?.isEmpty == false ? cwd! : (defaultCwd ?? "")
        return resolved.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func modelsInfo() async throws -> ModelsInfo? {
        let config = try await service.getAgentConfig(agentID: agentID)
        guard config.runtime.type == .native else {
            return nil
        }
        let models = Self.modelInfo(from: config.availableModels)
        guard !models.isEmpty else {
            return nil
        }
        let selected = config.selectedModel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = selected?.isEmpty == false ? selected! : models[0].modelId
        return ModelsInfo(currentModelId: current, availableModels: models)
    }

    private static func modelInfo(from models: [ProviderModelOption]) -> [ModelInfo] {
        models.map { model in
            ModelInfo(
                modelId: model.id,
                name: model.title.isEmpty ? model.id : model.title,
                description: modelDescription(model)
            )
        }
    }

    private static func modelIDs(from models: [ProviderModelOption]) -> Set<String> {
        Set(models.map(\.id))
    }

    private static func modelDescription(_ model: ProviderModelOption) -> String? {
        var parts: [String] = []
        if let context = model.contextWindow?.trimmingCharacters(in: .whitespacesAndNewlines), !context.isEmpty {
            parts.append("Context: \(context)")
        }
        if !model.capabilities.isEmpty {
            parts.append("Capabilities: \(model.capabilities.joined(separator: ", "))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }

    private func forward(
        update: AgentSessionStreamUpdate,
        acpSessionID: SessionId,
        deltaTracker: ACPServerDeltaTracker,
        thinkBlockRouter: ACPServerThinkBlockRouter,
        toolCallTracker: ACPServerToolCallTracker
    ) async {
        do {
            switch update.kind {
            case .sessionDelta:
                guard let message = update.message,
                      let delta = await deltaTracker.consume(fullDraft: message)
                else { return }
                try await forwardAssistantText(delta, acpSessionID: acpSessionID, thinkBlockRouter: thinkBlockRouter)
            case .sessionEvent:
                guard let event = update.event else { return }
                try await forward(
                    event: event,
                    acpSessionID: acpSessionID,
                    deltaTracker: deltaTracker,
                    thinkBlockRouter: thinkBlockRouter,
                    toolCallTracker: toolCallTracker
                )
            case .sessionReady, .heartbeat, .sessionClosed, .sessionError:
                return
            }
        } catch {
            return
        }
    }

    private func forward(
        event: AgentSessionEvent,
        acpSessionID: SessionId,
        deltaTracker: ACPServerDeltaTracker? = nil,
        thinkBlockRouter: ACPServerThinkBlockRouter = ACPServerThinkBlockRouter(),
        toolCallTracker: ACPServerToolCallTracker
    ) async throws {
        switch event.type {
        case .message:
            guard let message = event.message else { return }
            let text = Self.text(from: message)
            guard !text.isEmpty else { return }
            if message.role == .assistant {
                if let deltaTracker, !(await deltaTracker.shouldForwardFinalAssistantMessage()) {
                    try await forwardAssistantText(
                        "",
                        acpSessionID: acpSessionID,
                        thinkBlockRouter: thinkBlockRouter,
                        flush: true
                    )
                    return
                }
                try await forwardAssistantText(
                    text,
                    acpSessionID: acpSessionID,
                    thinkBlockRouter: thinkBlockRouter,
                    flush: true
                )
            } else if message.role == .user {
                try await sendUpdate(
                    acpSessionID, .userMessageChunk(.text(TextContent(text: text))))
            } else if message.role == .system {
                try await sendUpdate(
                    acpSessionID, .agentThoughtChunk(.text(TextContent(text: text))))
            }
        case .runStatus:
            return
        case .toolCall:
            guard let call = event.toolCall else { return }
            let toolCallId = await toolCallTracker.recordCall(tool: call.tool, eventID: event.id)
            try await sendUpdate(
                acpSessionID,
                .toolCall(
                    ToolCallUpdate(
                        toolCallId: toolCallId,
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
            let toolCallId = await toolCallTracker.consumeResult(tool: result.tool, eventID: event.id)
            try await sendUpdate(
                acpSessionID,
                .toolCallUpdate(
                    ToolCallUpdateDetails(
                        toolCallId: toolCallId,
                        status: result.ok ? .completed : .failed,
                        content: [.content(.text(TextContent(text: Self.toolResultText(result))))]
                    )
                )
            )
        default:
            return
        }
    }

    private func forwardAssistantText(
        _ text: String,
        acpSessionID: SessionId,
        thinkBlockRouter: ACPServerThinkBlockRouter,
        flush: Bool = false
    ) async throws {
        let chunks = await thinkBlockRouter.consume(text) + (flush ? await thinkBlockRouter.flush() : [])
        for chunk in chunks {
            let content = ContentBlock.text(TextContent(text: chunk.text))
            switch chunk.kind {
            case .message:
                try await sendUpdate(acpSessionID, .agentMessageChunk(content))
            case .thought:
                try await sendUpdate(acpSessionID, .agentThoughtChunk(content))
            }
        }
    }

    private func titleForSession(cwd: String) -> String {
        let raw = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return "ACP Session"
        }
        return "ACP \(URL(fileURLWithPath: raw).lastPathComponent)"
    }

    private static func promptPayload(from blocks: [ContentBlock]) -> (content: String, attachments: [AgentAttachmentUpload]) {
        var attachments: [AgentAttachmentUpload] = []
        var contentParts: [String] = []
        var previousTextBlock: String?

        for block in blocks {
            switch block {
            case .text(let text):
                appendPromptText(text.text, to: &contentParts, previousTextBlock: &previousTextBlock)
            case .image(let image):
                attachments.append(
                    AgentAttachmentUpload(
                        name: imageName(from: image.uri, fallbackExtension: imageExtension(for: image.mimeType)),
                        mimeType: image.mimeType,
                        sizeBytes: Data(base64Encoded: image.data, options: [.ignoreUnknownCharacters])?.count ?? 0,
                        contentBase64: image.data
                    )
                )
                contentParts.append(image.uri.map { "Image attached: \($0)" } ?? "Image attached.")
            case .resourceLink(let link):
                appendPromptText(link.uri, to: &contentParts, previousTextBlock: &previousTextBlock)
            case .resource(let resource):
                switch resource.resource {
                case .text(let text):
                    appendPromptText(text.text, to: &contentParts, previousTextBlock: &previousTextBlock)
                case .blob(let blob):
                    if let mimeType = blob.mimeType, isImageMimeType(mimeType) {
                        attachments.append(
                            AgentAttachmentUpload(
                                name: imageName(from: blob.uri, fallbackExtension: imageExtension(for: mimeType)),
                                mimeType: mimeType,
                                sizeBytes: Data(base64Encoded: blob.blob, options: [.ignoreUnknownCharacters])?.count ?? 0,
                                contentBase64: blob.blob
                            )
                        )
                    }
                    appendPromptText(blob.uri, to: &contentParts, previousTextBlock: &previousTextBlock)
                }
            case .audio:
                break
            }
        }

        return (contentParts.joined(separator: "\n\n"), attachments)
    }

    private static func appendPromptText(
        _ text: String,
        to contentParts: inout [String],
        previousTextBlock: inout String?
    ) {
        let normalizedText = normalizedPromptTextForOverlap(text)
        guard !normalizedText.isEmpty else {
            return
        }

        if normalizedText.count >= 32,
           let previousTextBlock,
           normalizedPromptTextForOverlap(previousTextBlock).hasSuffix(normalizedText) {
            return
        }

        contentParts.append(text)
        previousTextBlock = text
    }

    private static func normalizedPromptTextForOverlap(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isImageMimeType(_ mimeType: String) -> Bool {
        mimeType.lowercased().hasPrefix("image/")
    }

    private static func imageExtension(for mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "image/jpeg", "image/jpg":
            return "jpg"
        case "image/gif":
            return "gif"
        case "image/webp":
            return "webp"
        case "image/heic":
            return "heic"
        case "image/svg+xml":
            return "svg"
        default:
            return "png"
        }
    }

    private static func imageName(from uri: String?, fallbackExtension: String) -> String {
        guard let uri,
              let components = URLComponents(string: uri),
              let lastPathComponent = components.url?.lastPathComponent,
              !lastPathComponent.isEmpty
        else {
            return "acp-image.\(fallbackExtension)"
        }
        return lastPathComponent
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

actor ACPServerToolCallTracker {
    private var pendingCallIdsByTool: [String: [String]] = [:]

    func recordCall(tool: String, eventID: String) -> String {
        pendingCallIdsByTool[tool, default: []].append(eventID)
        return eventID
    }

    func consumeResult(tool: String, eventID: String) -> String {
        guard var pending = pendingCallIdsByTool[tool], !pending.isEmpty else {
            return eventID
        }
        let callID = pending.removeFirst()
        pendingCallIdsByTool[tool] = pending
        return callID
    }
}

enum ACPServerThinkBlockKind: Sendable, Equatable {
    case message
    case thought
}

struct ACPServerThinkBlockChunk: Sendable, Equatable {
    let kind: ACPServerThinkBlockKind
    let text: String
}

actor ACPServerThinkBlockRouter {
    private static let openTag = "<think>"
    private static let closeTag = "</think>"

    private var buffer = ""
    private var isInsideThinkBlock = false

    func consume(_ text: String) -> [ACPServerThinkBlockChunk] {
        buffer.append(text)

        var chunks: [ACPServerThinkBlockChunk] = []
        while !buffer.isEmpty {
            let tag = isInsideThinkBlock ? Self.closeTag : Self.openTag
            if let range = buffer.range(of: tag) {
                append(
                    String(buffer[..<range.lowerBound]),
                    kind: isInsideThinkBlock ? .thought : .message,
                    to: &chunks
                )
                buffer.removeSubrange(..<range.upperBound)
                isInsideThinkBlock.toggle()
                continue
            }

            let holdCount = Self.trailingPrefixLength(in: buffer, matching: tag)
            let emitEnd = buffer.index(buffer.endIndex, offsetBy: -holdCount)
            append(
                String(buffer[..<emitEnd]),
                kind: isInsideThinkBlock ? .thought : .message,
                to: &chunks
            )
            buffer.removeSubrange(..<emitEnd)
            break
        }

        return chunks
    }

    func flush() -> [ACPServerThinkBlockChunk] {
        defer { buffer = "" }
        guard !buffer.isEmpty else { return [] }
        return [
            ACPServerThinkBlockChunk(
                kind: isInsideThinkBlock ? .thought : .message,
                text: buffer
            )
        ]
    }

    private static func trailingPrefixLength(in text: String, matching tag: String) -> Int {
        let maxCount = min(text.count, tag.count - 1)
        guard maxCount > 0 else { return 0 }

        for count in stride(from: maxCount, through: 1, by: -1) {
            let suffix = text.suffix(count)
            let prefix = tag.prefix(count)
            if suffix == prefix {
                return count
            }
        }
        return 0
    }

    private func append(
        _ text: String,
        kind: ACPServerThinkBlockKind,
        to chunks: inout [ACPServerThinkBlockChunk]
    ) {
        guard !text.isEmpty else { return }
        chunks.append(ACPServerThinkBlockChunk(kind: kind, text: text))
    }
}

actor ACPServerDeltaTracker {
    private(set) var didSendDelta = false
    private var lastDraft = ""

    func consume(fullDraft: String) -> String? {
        let normalized = fullDraft.replacingOccurrences(of: "\r\n", with: "\n")
        let delta: String
        if normalized.hasPrefix(lastDraft) {
            delta = String(normalized.dropFirst(lastDraft.count))
        } else {
            delta = normalized
        }
        lastDraft = normalized

        guard !delta.isEmpty else {
            return nil
        }
        didSendDelta = true
        return delta
    }

    func shouldForwardFinalAssistantMessage() -> Bool {
        !didSendDelta
    }
}
