import Foundation
import Logging
import PluginSDK

public actor DiscordGatewayPlugin: StreamingGatewayPlugin {
    private struct StreamState: Sendable {
        let discordChannelId: String
        let messageId: String
        var lastRenderedText: String
        var lastUpdatedAt: Date
    }

    public nonisolated let id: String = "discord"
    public nonisolated let channelIds: [String]

    private let config: DiscordPluginConfig
    private let client: any DiscordPlatformClient
    private let logger: Logger
    private var gatewayTask: Task<Void, Never>?
    private var streams: [String: StreamState] = [:]

    public init(
        botToken: String,
        channelDiscordChannelMap: [String: String],
        allowedGuildIds: [String] = [],
        allowedChannelIds: [String] = [],
        allowedUserIds: [String] = [],
        logger: Logger? = nil
    ) {
        self.init(
            botToken: botToken,
            channelDiscordChannelMap: channelDiscordChannelMap,
            allowedGuildIds: allowedGuildIds,
            allowedChannelIds: allowedChannelIds,
            allowedUserIds: allowedUserIds,
            logger: logger,
            client: nil
        )
    }

    init(
        botToken: String,
        channelDiscordChannelMap: [String: String],
        allowedGuildIds: [String] = [],
        allowedChannelIds: [String] = [],
        allowedUserIds: [String] = [],
        logger: Logger? = nil,
        client: (any DiscordPlatformClient)? = nil
    ) {
        self.config = DiscordPluginConfig(
            botToken: botToken,
            channelDiscordChannelMap: channelDiscordChannelMap,
            allowedGuildIds: allowedGuildIds,
            allowedChannelIds: allowedChannelIds,
            allowedUserIds: allowedUserIds
        )
        self.channelIds = Array(channelDiscordChannelMap.keys)
        let resolvedLogger = logger ?? Logger(label: "sloppy.plugin.discord")
        self.logger = resolvedLogger
        self.client = client ?? DiscordHTTPClient(botToken: botToken, logger: resolvedLogger)
    }

    public func start(inboundReceiver: any InboundMessageReceiver) async throws {
        guard gatewayTask == nil else {
            logger.warning("Discord plugin start() called but gateway loop is already running.")
            return
        }

        logger.info(
            "Discord gateway plugin starting. channels=\(channelIds) allowedGuilds=\(config.allowedGuildIds.count) allowedChannels=\(config.allowedChannelIds.count) allowedUsers=\(config.allowedUserIds.count)"
        )
        if channelIds.isEmpty {
            logger.warning("No channel mappings configured for Discord plugin.")
        }

        let loop = DiscordGatewayLoop(
            client: client,
            receiver: inboundReceiver,
            config: config,
            logger: logger
        )
        gatewayTask = Task {
            await loop.run()
        }
    }

    public func stop() async {
        gatewayTask?.cancel()
        gatewayTask = nil
        streams.removeAll()
        logger.info("Discord gateway plugin stopped.")
    }

    public func send(channelId: String, message: String) async throws {
        guard let discordChannelId = config.discordChannelId(forChannelId: channelId) else {
            logger.warning("No Discord channel mapping for channel \(channelId). Message dropped.")
            return
        }

        _ = try await client.sendMessage(
            channelId: discordChannelId,
            content: renderContent(message)
        )
    }

    public func beginStreaming(channelId: String, userId: String) async throws -> GatewayOutboundStreamHandle {
        guard let discordChannelId = config.discordChannelId(forChannelId: channelId) else {
            logger.warning("No Discord channel mapping for channel \(channelId). Stream start dropped.")
            throw DiscordTransportError.invalidResponse(method: "beginStreaming")
        }

        let placeholder = try await client.sendMessage(
            channelId: discordChannelId,
            content: "Thinking..."
        )
        let handle = GatewayOutboundStreamHandle(id: UUID().uuidString)
        streams[handle.id] = StreamState(
            discordChannelId: discordChannelId,
            messageId: placeholder.id,
            lastRenderedText: "",
            lastUpdatedAt: .distantPast
        )
        return handle
    }

    public func updateStreaming(
        handle: GatewayOutboundStreamHandle,
        channelId: String,
        content: String
    ) async throws {
        guard var state = streams[handle.id] else {
            return
        }

        let normalized = renderContent(content.replacingOccurrences(of: "\r\n", with: "\n"))
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              normalized != state.lastRenderedText
        else {
            return
        }

        let now = Date()
        let minInterval: TimeInterval = 1.0
        guard now.timeIntervalSince(state.lastUpdatedAt) >= minInterval else {
            return
        }

        _ = try await client.editMessage(
            channelId: state.discordChannelId,
            messageId: state.messageId,
            content: normalized
        )
        state.lastRenderedText = normalized
        state.lastUpdatedAt = now
        streams[handle.id] = state
    }

    public func endStreaming(
        handle: GatewayOutboundStreamHandle,
        channelId: String,
        userId: String,
        finalContent: String?
    ) async throws {
        guard let state = streams.removeValue(forKey: handle.id) else {
            return
        }

        guard let finalContent,
              !finalContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            try await client.deleteMessage(
                channelId: state.discordChannelId,
                messageId: state.messageId
            )
            return
        }

        let rendered = renderContent(finalContent)
        guard rendered != state.lastRenderedText else {
            return
        }

        _ = try await client.editMessage(
            channelId: state.discordChannelId,
            messageId: state.messageId,
            content: rendered
        )
    }

    private func renderContent(_ value: String) -> String {
        let limit = 2_000
        if value.count <= limit {
            return value
        }
        let endIndex = value.index(value.startIndex, offsetBy: limit - 1)
        return String(value[..<endIndex]) + "…"
    }
}
