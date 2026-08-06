import Foundation

public enum ChatStreamUpdateKind: String, Codable, Sendable {
    case sessionReady = "session_ready"
    case sessionEvent = "session_event"
    case sessionDelta = "session_delta"
    case heartbeat
    case sessionClosed = "session_closed"
    case sessionError = "session_error"
}

public enum ChatMessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

public enum ChatMessageSegmentKind: String, Codable, Sendable {
    case text
    case thinking
    case attachment
    case toolCall = "tool_call"
    case toolResult = "tool_result"
    case status
    case buildProgress = "build_progress"
}

public struct ChatAttachment: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var mimeType: String
    public var sizeBytes: Int
    public var relativePath: String?

    public init(
        id: String,
        name: String,
        mimeType: String,
        sizeBytes: Int,
        relativePath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.relativePath = relativePath
    }
}

public enum ChatBuildProgressStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case pending
    case inProgress = "in_progress"
    case done
    case blocked
    case skipped
}

public struct ChatBuildProgressItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var status: ChatBuildProgressStatus
    public var definitionOfDone: String
    public var details: String?

    public init(
        id: String,
        title: String,
        status: ChatBuildProgressStatus,
        definitionOfDone: String,
        details: String? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.definitionOfDone = definitionOfDone
        self.details = details
    }
}

public struct ChatBuildProgress: Codable, Sendable, Equatable {
    public var title: String
    public var items: [ChatBuildProgressItem]
    public var createdAt: Date

    public init(
        title: String,
        items: [ChatBuildProgressItem],
        createdAt: Date = Date()
    ) {
        self.title = title
        self.items = items
        self.createdAt = createdAt
    }

    public var currentStepNumber: Int {
        if let index = items.firstIndex(where: { $0.status == .inProgress }) {
            return index + 1
        }
        if let index = items.firstIndex(where: { $0.status == .blocked }) {
            return index + 1
        }
        if let index = items.firstIndex(where: { $0.status == .pending }) {
            return index + 1
        }
        return items.count
    }

    fileprivate var timelineMessage: ChatMessage {
        ChatMessage(
            id: "build-progress-current",
            role: .system,
            segments: [ChatMessageSegment(kind: .buildProgress, buildProgress: self)],
            createdAt: createdAt
        )
    }
}

public struct ChatMessageSegment: Codable, Sendable, Equatable {
    public var kind: ChatMessageSegmentKind
    public var text: String?
    public var title: String?
    public var status: String?
    public var startedAt: Date?
    public var finishedAt: Date?
    public var metadata: [String: String]?
    public var buildProgress: ChatBuildProgress?
    public var attachment: ChatAttachment?

    public init(
        kind: ChatMessageSegmentKind,
        text: String? = nil,
        title: String? = nil,
        status: String? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        metadata: [String: String]? = nil,
        buildProgress: ChatBuildProgress? = nil,
        attachment: ChatAttachment? = nil
    ) {
        self.kind = kind
        self.text = text
        self.title = title
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.metadata = metadata
        self.buildProgress = buildProgress
        self.attachment = attachment
    }
}

public struct ChatMessage: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var role: ChatMessageRole
    public var segments: [ChatMessageSegment]
    public var createdAt: Date

    public var textContent: String {
        segments.filter { $0.kind == .text }.compactMap { $0.text }.joined()
    }

    public init(
        id: String = UUID().uuidString,
        role: ChatMessageRole,
        segments: [ChatMessageSegment],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.segments = segments
        self.createdAt = createdAt
    }
}

public struct ChatPlanInputOption: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var description: String?

    public init(id: String, label: String, description: String? = nil) {
        self.id = id
        self.label = label
        self.description = description
    }
}

public struct ChatPlanInputQuestion: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var header: String?
    public var question: String
    public var options: [ChatPlanInputOption]
    public var allowCustomAnswer: Bool

    public init(
        id: String,
        header: String? = nil,
        question: String,
        options: [ChatPlanInputOption],
        allowCustomAnswer: Bool = true
    ) {
        self.id = id
        self.header = header
        self.question = question
        self.options = options
        self.allowCustomAnswer = allowCustomAnswer
    }

    private enum CodingKeys: String, CodingKey {
        case id, header, question, options, allowCustomAnswer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        header = try container.decodeIfPresent(String.self, forKey: .header)
        question = try container.decode(String.self, forKey: .question)
        options = try container.decode([ChatPlanInputOption].self, forKey: .options)
        allowCustomAnswer = try container.decodeIfPresent(Bool.self, forKey: .allowCustomAnswer) ?? true
    }
}

public struct ChatPlanInputRequest: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var mode: String
    public var title: String?
    public var questions: [ChatPlanInputQuestion]
    public var createdAt: Date

    public init(
        id: String,
        mode: String = "plan",
        title: String? = nil,
        questions: [ChatPlanInputQuestion],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.mode = mode
        self.title = title
        self.questions = questions
        self.createdAt = createdAt
    }
}

public enum ChatPlanInputResponseStatus: String, Codable, Sendable, Equatable {
    case answered
    case cancelled
}

public struct ChatPlanInputAnswer: Codable, Sendable, Equatable {
    public var questionId: String
    public var selectedOptionId: String?
    public var customAnswer: String?

    public init(
        questionId: String,
        selectedOptionId: String? = nil,
        customAnswer: String? = nil
    ) {
        self.questionId = questionId
        self.selectedOptionId = selectedOptionId
        self.customAnswer = customAnswer
    }
}

public struct ChatPlanInputAnswerRequest: Codable, Sendable, Equatable {
    public var status: ChatPlanInputResponseStatus
    public var answers: [ChatPlanInputAnswer]
    public var userId: String

    public init(
        status: ChatPlanInputResponseStatus = .answered,
        answers: [ChatPlanInputAnswer],
        userId: String = "apple-client"
    ) {
        self.status = status
        self.answers = answers
        self.userId = userId
    }
}

public struct ChatPlanInputResponse: Codable, Sendable, Equatable {
    public var requestId: String
    public var status: ChatPlanInputResponseStatus
    public var answers: [ChatPlanInputAnswer]
    public var userId: String

    public init(
        requestId: String,
        status: ChatPlanInputResponseStatus,
        answers: [ChatPlanInputAnswer],
        userId: String
    ) {
        self.requestId = requestId
        self.status = status
        self.answers = answers
        self.userId = userId
    }
}

public struct ChatSessionSummary: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var agentId: String
    public var title: String
    public var messageCount: Int
    public var updatedAt: Date
    public var kind: String
    public var projectId: String?
    public var workspaceId: String?

    public init(
        id: String,
        agentId: String,
        title: String,
        messageCount: Int = 0,
        updatedAt: Date = Date(),
        kind: String = "chat",
        projectId: String? = nil,
        workspaceId: String? = nil
    ) {
        self.id = id
        self.agentId = agentId
        self.title = title
        self.messageCount = messageCount
        self.updatedAt = updatedAt
        self.kind = kind
        self.projectId = projectId
        self.workspaceId = workspaceId
    }
}

public enum ChatSessionCatalog {
    public static func merge(_ batches: [[ChatSessionSummary]]) -> [ChatSessionSummary] {
        var sessionsByID: [String: ChatSessionSummary] = [:]

        for session in batches.joined() where session.kind != "heartbeat" {
            guard let existing = sessionsByID[session.id] else {
                sessionsByID[session.id] = session
                continue
            }
            if session.updatedAt > existing.updatedAt {
                sessionsByID[session.id] = session
            }
        }

        return sessionsByID.values.sorted { $0.updatedAt > $1.updatedAt }
    }
}

public struct ChatSessionDetail: Decodable, Sendable {
    public var summary: ChatSessionSummary
    public var events: [ChatEventEnvelope]
    private var directMessages: [ChatMessage]

    public var messages: [ChatMessage] {
        let latestProgressEventID = events.last(where: { $0.buildProgress != nil })?.id
        let eventMessages = events.compactMap { event -> ChatMessage? in
            if event.buildProgress != nil, event.id != latestProgressEventID {
                return nil
            }
            return event.message
        }

        guard !directMessages.isEmpty else {
            return eventMessages
        }
        guard let progressMessage = eventMessages.last(where: { $0.id == "build-progress-current" }) else {
            return directMessages
        }
        return (directMessages.filter { $0.id != progressMessage.id } + [progressMessage])
            .sorted { $0.createdAt < $1.createdAt }
    }

    public var latestRunStatus: ChatRunStatusEvent? {
        events.reversed().compactMap(\.runStatus).first
    }

    public var pendingInputRequest: ChatPlanInputRequest? {
        let answeredRequestIDs = Set(events.compactMap(\.inputResponse?.requestId))
        return events.reversed().compactMap(\.inputRequest).first {
            !answeredRequestIDs.contains($0.id)
        }
    }

    public init(summary: ChatSessionSummary, events: [ChatEventEnvelope] = [], messages: [ChatMessage] = []) {
        self.summary = summary
        self.events = events
        self.directMessages = messages
    }

    private enum CodingKeys: String, CodingKey {
        case summary, events, messages
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decode(ChatSessionSummary.self, forKey: .summary)
        events = try container.decodeIfPresent([ChatEventEnvelope].self, forKey: .events) ?? []
        directMessages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
    }
}

public struct ChatModelOption: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var capabilities: [String]
    public var contextWindow: String?

    public init(
        id: String,
        title: String? = nil,
        capabilities: [String] = [],
        contextWindow: String? = nil
    ) {
        self.id = id
        if let title, !title.isEmpty {
            self.title = title
        } else {
            self.title = id
        }
        self.capabilities = capabilities
        self.contextWindow = contextWindow
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, capabilities, contextWindow
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let decodedTitle = try container.decodeIfPresent(String.self, forKey: .title)
        if let decodedTitle, !decodedTitle.isEmpty {
            title = decodedTitle
        } else {
            title = id
        }
        capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []

        if let context = try? container.decodeIfPresent(String.self, forKey: .contextWindow) {
            contextWindow = context
        } else if let context = try? container.decodeIfPresent(Int.self, forKey: .contextWindow) {
            contextWindow = String(context)
        } else {
            contextWindow = nil
        }
    }

    public var supportsReasoningEffort: Bool {
        capabilities.contains { $0.caseInsensitiveCompare("reasoning") == .orderedSame }
    }
}

public enum ChatReasoningEffort: String, CaseIterable, Codable, Sendable, Equatable, Identifiable {
    case `default`
    case low
    case medium
    case high

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .default: "Default"
        case .low: "Light"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    public var payloadValue: String? {
        self == .default ? nil : rawValue
    }
}

public struct ChatEventEnvelope: Decodable, Sendable {
    public var id: String
    public var type: String
    public var createdAt: Date
    public var message: ChatMessage?
    public var buildProgress: ChatBuildProgress?
    public var runStatus: ChatRunStatusEvent?
    public var inputRequest: ChatPlanInputRequest?
    public var inputResponse: ChatPlanInputResponse?

    private enum CodingKeys: String, CodingKey {
        case id, type, createdAt, message, buildProgress, runStatus, toolCall, toolResult
        case inputRequest, inputResponse, event
    }

    private struct EmbeddedEvent: Decodable {
        var createdAt: Date?
        var message: ChatMessage?
        var buildProgress: ChatBuildProgress?
        var runStatus: ChatRunStatusEvent?
        var toolCall: ChatToolCallPayload?
        var toolResult: ChatToolResultPayload?
        var inputRequest: ChatPlanInputRequest?
        var inputResponse: ChatPlanInputResponse?
    }

    public init(
        id: String,
        type: String,
        createdAt: Date = Date(),
        message: ChatMessage? = nil,
        buildProgress: ChatBuildProgress? = nil,
        runStatus: ChatRunStatusEvent? = nil,
        inputRequest: ChatPlanInputRequest? = nil,
        inputResponse: ChatPlanInputResponse? = nil
    ) {
        self.id = id
        self.type = type
        self.createdAt = createdAt
        self.buildProgress = buildProgress
        self.runStatus = runStatus
        self.inputRequest = inputRequest
        self.inputResponse = inputResponse
        self.message = message ?? buildProgress?.timelineMessage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)

        // REST session history stores chat messages on the event itself:
        // { "type": "message", "message": { ... } }
        // Some streamed/debug payloads wrap the same value under `event.message`.
        // Support both so opening an existing session can hydrate the transcript.
        let embeddedEvent = try container.decodeIfPresent(EmbeddedEvent.self, forKey: .event)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
            ?? embeddedEvent?.createdAt
            ?? Date()
        buildProgress = try container.decodeIfPresent(ChatBuildProgress.self, forKey: .buildProgress)
            ?? embeddedEvent?.buildProgress
        runStatus = try container.decodeIfPresent(ChatRunStatusEvent.self, forKey: .runStatus)
            ?? embeddedEvent?.runStatus
        inputRequest = try container.decodeIfPresent(ChatPlanInputRequest.self, forKey: .inputRequest)
            ?? embeddedEvent?.inputRequest
        inputResponse = try container.decodeIfPresent(ChatPlanInputResponse.self, forKey: .inputResponse)
            ?? embeddedEvent?.inputResponse
        let toolCall = try container.decodeIfPresent(ChatToolCallPayload.self, forKey: .toolCall)
            ?? embeddedEvent?.toolCall
        let toolResult = try container.decodeIfPresent(ChatToolResultPayload.self, forKey: .toolResult)
            ?? embeddedEvent?.toolResult
        message = try container.decodeIfPresent(ChatMessage.self, forKey: .message)
            ?? embeddedEvent?.message
            ?? buildProgress?.timelineMessage
            ?? toolCall?.timelineMessage(id: id, createdAt: createdAt)
            ?? toolResult?.timelineMessage(id: id, createdAt: createdAt)
    }
}

public enum ChatStreamEventType: String, Codable, Sendable {
    case message
    case runStatus = "run_status"
    case inputRequest = "input_request"
    case buildProgress = "build_progress"
    case toolCall = "tool_call"
    case toolResult = "tool_result"
}

public enum ChatRunStage: String, Codable, Sendable {
    case thinking
    case searching
    case responding
    case paused
    case done
    case interrupted

    public var isWorking: Bool {
        switch self {
        case .thinking, .searching, .responding:
            true
        case .paused, .done, .interrupted:
            false
        }
    }
}

public struct ChatRunStatusEvent: Codable, Sendable, Equatable {
    public var stage: ChatRunStage
    public var label: String
    public var details: String?
    public var expandedText: String?
    public var createdAt: Date?

    public init(
        stage: ChatRunStage,
        label: String,
        details: String? = nil,
        expandedText: String? = nil,
        createdAt: Date? = nil
    ) {
        self.stage = stage
        self.label = label
        self.details = details
        self.expandedText = expandedText
        self.createdAt = createdAt
    }
}

public struct ChatStreamEvent: Decodable, Sendable, Equatable {
    public var id: String
    public var type: ChatStreamEventType
    public var message: ChatMessage?
    public var runStatus: ChatRunStatusEvent?
    public var buildProgress: ChatBuildProgress?
    public var inputRequest: ChatPlanInputRequest?
    public var inputResponse: ChatPlanInputResponse?

    public init(
        id: String,
        type: ChatStreamEventType,
        message: ChatMessage? = nil,
        runStatus: ChatRunStatusEvent? = nil,
        buildProgress: ChatBuildProgress? = nil,
        inputRequest: ChatPlanInputRequest? = nil,
        inputResponse: ChatPlanInputResponse? = nil
    ) {
        self.id = id
        self.type = type
        self.message = message
        self.runStatus = runStatus
        self.buildProgress = buildProgress
        self.inputRequest = inputRequest
        self.inputResponse = inputResponse
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, createdAt, message, runStatus, buildProgress, toolCall, toolResult
        case inputRequest, inputResponse
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(ChatStreamEventType.self, forKey: .type)
        runStatus = try container.decodeIfPresent(ChatRunStatusEvent.self, forKey: .runStatus)
        buildProgress = try container.decodeIfPresent(ChatBuildProgress.self, forKey: .buildProgress)
        inputRequest = try container.decodeIfPresent(ChatPlanInputRequest.self, forKey: .inputRequest)
        inputResponse = try container.decodeIfPresent(ChatPlanInputResponse.self, forKey: .inputResponse)

        let createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        let toolCall = try container.decodeIfPresent(ChatToolCallPayload.self, forKey: .toolCall)
        let toolResult = try container.decodeIfPresent(ChatToolResultPayload.self, forKey: .toolResult)
        message = try container.decodeIfPresent(ChatMessage.self, forKey: .message)
            ?? buildProgress?.timelineMessage
            ?? toolCall?.timelineMessage(id: id, createdAt: createdAt)
            ?? toolResult?.timelineMessage(id: id, createdAt: createdAt)
    }
}

private struct ChatToolCallPayload: Decodable, Sendable {
    var tool: String
    var arguments: [String: ChatJSONValue]
    var reason: String?

    private enum CodingKeys: String, CodingKey {
        case tool, arguments, reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tool = try container.decode(String.self, forKey: .tool)
        arguments = try container.decodeIfPresent([String: ChatJSONValue].self, forKey: .arguments) ?? [:]
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
    }

    func timelineMessage(id: String, createdAt: Date) -> ChatMessage {
        ChatMessage(
            id: id,
            role: .system,
            segments: [
                ChatMessageSegment(
                    kind: .toolCall,
                    text: reason,
                    title: tool,
                    status: "started",
                    metadata: arguments.isEmpty ? nil : arguments.mapValues(\.displayText)
                )
            ],
            createdAt: createdAt
        )
    }
}

private struct ChatToolResultPayload: Decodable, Sendable {
    var tool: String
    var ok: Bool
    var data: ChatJSONValue?
    var error: ChatToolErrorPayload?
    var durationMs: Int?

    func timelineMessage(id: String, createdAt: Date) -> ChatMessage {
        var metadata: [String: String] = [:]
        if let code = error?.code {
            metadata["error"] = code
        }
        if let hint = error?.hint, !hint.isEmpty {
            metadata["hint"] = hint
        }

        return ChatMessage(
            id: id,
            role: .system,
            segments: [
                ChatMessageSegment(
                    kind: .toolResult,
                    text: data?.displayText ?? error?.message,
                    title: tool,
                    status: ok ? "done" : "failed",
                    startedAt: durationMs.map { createdAt.addingTimeInterval(-Double($0) / 1_000) },
                    finishedAt: createdAt,
                    metadata: metadata.isEmpty ? nil : metadata
                )
            ],
            createdAt: createdAt
        )
    }
}

private struct ChatToolErrorPayload: Decodable, Sendable {
    var code: String
    var message: String
    var retryable: Bool
    var hint: String?
}

private indirect enum ChatJSONValue: Decodable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([ChatJSONValue])
    case object([String: ChatJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ChatJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: ChatJSONValue].self))
        }
    }

    var displayText: String {
        switch self {
        case .null:
            return "null"
        case .bool(let value):
            return value ? "true" : "false"
        case .number(let value):
            return value.rounded() == value ? String(format: "%.0f", value) : String(value)
        case .string(let value):
            return value
        case .array(let values):
            return "[\(values.map(\.displayText).joined(separator: ", "))]"
        case .object(let values):
            let fields = values.keys.sorted().map { "\($0): \(values[$0]?.displayText ?? "null")" }
            return "{\(fields.joined(separator: ", "))}"
        }
    }
}

// Mirrors the server's AgentSessionStreamUpdate wire format.
// The server puts the full event object under "event", which itself may contain a "message".
public struct ChatStreamUpdate: Sendable {
    public var kind: ChatStreamUpdateKind
    public var cursor: Int
    public var summary: ChatSessionSummary?
    public var streamEvent: ChatStreamEvent?
    public var message: ChatMessage?
    public var messageText: String?
    public var errorText: String?
    public var createdAt: Date

    public init(
        kind: ChatStreamUpdateKind,
        cursor: Int,
        summary: ChatSessionSummary? = nil,
        streamEvent: ChatStreamEvent? = nil,
        message: ChatMessage? = nil,
        messageText: String? = nil,
        errorText: String? = nil,
        createdAt: Date = Date()
    ) {
        self.kind = kind
        self.cursor = cursor
        self.summary = summary
        self.streamEvent = streamEvent
        self.message = message
        self.messageText = messageText
        self.errorText = errorText
        self.createdAt = createdAt
    }
}

extension ChatStreamUpdate: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind, cursor, summary, event, message, delta, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(ChatStreamUpdateKind.self, forKey: .kind)
        cursor = try container.decodeIfPresent(Int.self, forKey: .cursor) ?? 0
        summary = try container.decodeIfPresent(ChatSessionSummary.self, forKey: .summary)
        createdAt = (try? container.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        let text = try container.decodeIfPresent(String.self, forKey: .message)
            ?? container.decodeIfPresent(String.self, forKey: .delta)
        messageText = kind == .sessionDelta ? text : nil
        errorText = kind == .sessionError || kind == .sessionClosed ? text : nil
        streamEvent = try container.decodeIfPresent(ChatStreamEvent.self, forKey: .event)
        message = streamEvent?.message ?? streamEvent?.buildProgress?.timelineMessage
    }
}
