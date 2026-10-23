import Foundation

public enum ChannelAttachmentType: String, Codable, Sendable, Equatable, CaseIterable {
    case image
    case audio
    case voice
    case video
    case document
    case file
    case unknown
}

public struct ChannelAttachment: Codable, Sendable, Equatable {
    public var id: String
    public var type: ChannelAttachmentType
    public var mimeType: String?
    public var filename: String?
    public var sizeBytes: Int?
    public var url: String?
    public var localPath: String?
    public var platformMetadata: [String: String]

    public init(
        id: String,
        type: ChannelAttachmentType = .unknown,
        mimeType: String? = nil,
        filename: String? = nil,
        sizeBytes: Int? = nil,
        url: String? = nil,
        localPath: String? = nil,
        platformMetadata: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.mimeType = mimeType
        self.filename = filename
        self.sizeBytes = sizeBytes
        self.url = url
        self.localPath = localPath
        self.platformMetadata = platformMetadata
    }
}

public extension ChannelAttachment {
    static func inferredType(mimeType: String?, filename: String? = nil, preferred: ChannelAttachmentType? = nil) -> ChannelAttachmentType {
        if let preferred, preferred != .unknown { return preferred }
        let mime = mimeType?.lowercased() ?? ""
        if mime.hasPrefix("image/") { return .image }
        if mime.hasPrefix("video/") { return .video }
        if mime.hasPrefix("audio/") { return .audio }
        if mime == "application/pdf" || mime.hasPrefix("text/") { return .document }
        let ext = filename.map { ($0 as NSString).pathExtension.lowercased() } ?? ""
        if ["jpg", "jpeg", "png", "gif", "webp", "heic"].contains(ext) { return .image }
        if ["mp4", "mov", "webm", "mkv"].contains(ext) { return .video }
        if ["mp3", "wav", "m4a", "ogg", "opus"].contains(ext) { return .audio }
        if ["pdf", "txt", "md", "doc", "docx"].contains(ext) { return .document }
        return .file
    }
}

public struct ChannelMessageRequest: Codable, Sendable {
    public var userId: String
    public var content: String
    public var topicId: String?
    public var model: String?
    public var reasoningEffort: ReasoningEffort?
    public var attachments: [ChannelAttachment]

    public init(
        userId: String,
        content: String,
        topicId: String? = nil,
        model: String? = nil,
        reasoningEffort: ReasoningEffort? = nil,
        attachments: [ChannelAttachment] = []
    ) {
        self.userId = userId
        self.content = content
        self.topicId = topicId
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.attachments = attachments
    }

    enum CodingKeys: String, CodingKey {
        case userId
        case content
        case topicId
        case model
        case reasoningEffort
        case attachments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.userId = try container.decode(String.self, forKey: .userId)
        self.content = try container.decode(String.self, forKey: .content)
        self.topicId = try container.decodeIfPresent(String.self, forKey: .topicId)
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
        self.reasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort)
        self.attachments = try container.decodeIfPresent([ChannelAttachment].self, forKey: .attachments) ?? []
    }
}

public struct ChannelModelResponse: Codable, Sendable {
    public var channelId: String
    public var selectedModel: String?
    public var availableModels: [ProviderModelOption]

    public init(channelId: String, selectedModel: String?, availableModels: [ProviderModelOption]) {
        self.channelId = channelId
        self.selectedModel = selectedModel
        self.availableModels = availableModels
    }
}

public struct ChannelModelUpdateRequest: Codable, Sendable {
    public var model: String

    public init(model: String) {
        self.model = model
    }
}

public struct ChannelControlRequest: Codable, Sendable {
    public var action: AgentRunControlAction
    public var requestedBy: String
    public var reason: String?

    public init(action: AgentRunControlAction, requestedBy: String, reason: String? = nil) {
        self.action = action
        self.requestedBy = requestedBy
        self.reason = reason
    }
}

public struct ChannelControlResponse: Codable, Sendable {
    public var channelId: String
    public var action: AgentRunControlAction
    public var cancelledWorkers: Int
    public var message: String

    public init(channelId: String, action: AgentRunControlAction, cancelledWorkers: Int, message: String) {
        self.channelId = channelId
        self.action = action
        self.cancelledWorkers = cancelledWorkers
        self.message = message
    }
}

public struct ChannelApprovalCodeRequest: Codable, Sendable {
    public var code: String

    public init(code: String) {
        self.code = code
    }
}

public struct ChannelRouteRequest: Codable, Sendable {
    public var message: String

    public init(message: String) {
        self.message = message
    }
}

public struct WorkerCreateRequest: Codable, Sendable {
    public var spec: WorkerTaskSpec

    public init(spec: WorkerTaskSpec) {
        self.spec = spec
    }
}

/// Response for channel runtime event feed with pagination cursor.
public struct ChannelEventsResponse: Codable, Sendable, Equatable {
    public var channelId: String
    public var items: [EventEnvelope]
    public var nextCursor: String?

    public init(channelId: String, items: [EventEnvelope], nextCursor: String? = nil) {
        self.channelId = channelId
        self.items = items
        self.nextCursor = nextCursor
    }
}

public struct ChannelPluginRecord: Codable, Sendable, Equatable {
    /// Delivery mode constants.
    public enum DeliveryMode {
        public static let http = "http"
        public static let inProcess = "in-process"
    }

    public var id: String
    public var type: String
    /// HTTP base URL for out-of-process plugins. Empty for in-process plugins.
    public var baseUrl: String
    public var channelIds: [String]
    public var config: [String: String]
    public var enabled: Bool
    /// `"http"` (default) or `"in-process"`. Determines how sloppy delivers messages.
    public var deliveryMode: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        type: String,
        baseUrl: String,
        channelIds: [String] = [],
        config: [String: String] = [:],
        enabled: Bool = true,
        deliveryMode: String = DeliveryMode.http,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.baseUrl = baseUrl
        self.channelIds = channelIds
        self.config = config
        self.enabled = enabled
        self.deliveryMode = deliveryMode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// One slash command for channel bots; mirrors ``ChannelCommandHandler.commands`` (Telegram/Discord).
public struct ChannelSlashCommandItem: Codable, Sendable, Equatable {
    public var name: String
    public var description: String
    public var argument: String?

    public init(name: String, description: String, argument: String? = nil) {
        self.name = name
        self.description = description
        self.argument = argument
    }
}

public struct ChannelSlashCommandsResponse: Codable, Sendable, Equatable {
    public var commands: [ChannelSlashCommandItem]

    public init(commands: [ChannelSlashCommandItem]) {
        self.commands = commands
    }
}

public struct ChannelPluginCreateRequest: Codable, Sendable {
    public var id: String?
    public var type: String
    public var baseUrl: String
    public var channelIds: [String]?
    public var config: [String: String]?
    public var enabled: Bool?

    public init(
        id: String? = nil,
        type: String,
        baseUrl: String,
        channelIds: [String]? = nil,
        config: [String: String]? = nil,
        enabled: Bool? = nil
    ) {
        self.id = id
        self.type = type
        self.baseUrl = baseUrl
        self.channelIds = channelIds
        self.config = config
        self.enabled = enabled
    }
}

public struct ChannelPluginUpdateRequest: Codable, Sendable {
    public var type: String?
    public var baseUrl: String?
    public var channelIds: [String]?
    public var config: [String: String]?
    public var enabled: Bool?

    public init(
        type: String? = nil,
        baseUrl: String? = nil,
        channelIds: [String]? = nil,
        config: [String: String]? = nil,
        enabled: Bool? = nil
    ) {
        self.type = type
        self.baseUrl = baseUrl
        self.channelIds = channelIds
        self.config = config
        self.enabled = enabled
    }
}

public struct ChannelPluginInstallRequest: Codable, Sendable {
    public var sourceUrl: String
    public var ref: String?
    public var force: Bool?
    public var enabled: Bool?
    public var localDirectory: Bool?

    enum CodingKeys: String, CodingKey {
        case sourceUrl
        case sourceURL
        case source
        case ref
        case force
        case enabled
        case localDirectory
    }

    public init(
        sourceUrl: String,
        ref: String? = nil,
        force: Bool? = nil,
        enabled: Bool? = nil,
        localDirectory: Bool? = nil
    ) {
        self.sourceUrl = sourceUrl
        self.ref = ref
        self.force = force
        self.enabled = enabled
        self.localDirectory = localDirectory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceUrl = try container.decodeStringFromAliases([.sourceUrl, .sourceURL, .source])
        ref = try container.decodeIfPresent(String.self, forKey: .ref)
        force = try container.decodeIfPresent(Bool.self, forKey: .force)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
        localDirectory = try container.decodeIfPresent(Bool.self, forKey: .localDirectory)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceUrl, forKey: .sourceUrl)
        try container.encodeIfPresent(ref, forKey: .ref)
        try container.encodeIfPresent(force, forKey: .force)
        try container.encodeIfPresent(enabled, forKey: .enabled)
        try container.encodeIfPresent(localDirectory, forKey: .localDirectory)
    }
}

private extension KeyedDecodingContainer where Key == ChannelPluginInstallRequest.CodingKeys {
    func decodeStringFromAliases(_ keys: [Key]) throws -> String {
        for key in keys where contains(key) {
            return try decode(String.self, forKey: key)
        }
        throw DecodingError.keyNotFound(
            keys[0],
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Missing required key '\(keys[0].stringValue)'."
            )
        )
    }
}

public struct ChannelPluginInstallResponse: Codable, Sendable {
    public var plugin: ChannelPluginRecord
    public var sourcePath: String
    public var binaryPath: String
    public var rebuilt: Bool

    public init(
        plugin: ChannelPluginRecord,
        sourcePath: String,
        binaryPath: String,
        rebuilt: Bool
    ) {
        self.plugin = plugin
        self.sourcePath = sourcePath
        self.binaryPath = binaryPath
        self.rebuilt = rebuilt
    }
}

public struct ChannelPluginDeliverRequest: Codable, Sendable {
    public var channelId: String
    public var userId: String
    public var content: String

    public init(channelId: String, userId: String, content: String) {
        self.channelId = channelId
        self.userId = userId
        self.content = content
    }
}

public struct ChannelPluginStreamStartRequest: Codable, Sendable {
    public var channelId: String
    public var userId: String

    public init(channelId: String, userId: String) {
        self.channelId = channelId
        self.userId = userId
    }
}

public struct ChannelPluginStreamStartResponse: Codable, Sendable {
    public var ok: Bool
    public var streamId: String?

    public init(ok: Bool, streamId: String? = nil) {
        self.ok = ok
        self.streamId = streamId
    }
}

public struct ChannelPluginStreamChunkRequest: Codable, Sendable {
    public var streamId: String
    public var channelId: String
    public var content: String

    public init(streamId: String, channelId: String, content: String) {
        self.streamId = streamId
        self.channelId = channelId
        self.content = content
    }
}

public struct ChannelPluginStreamEndRequest: Codable, Sendable {
    public var streamId: String
    public var channelId: String
    public var userId: String
    public var content: String?

    public init(streamId: String, channelId: String, userId: String, content: String? = nil) {
        self.streamId = streamId
        self.channelId = channelId
        self.userId = userId
        self.content = content
    }
}
