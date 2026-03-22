import Foundation
import ChannelPluginSupport
import Logging
import PluginSDK

/// In-process GatewayPlugin that bridges Telegram to Sloppy channels.
/// Uses long-polling to receive messages and InboundMessageReceiver to forward them to Sloppy.
public actor TelegramGatewayPlugin: StreamingGatewayPlugin {
    private struct StreamState: Sendable {
        let chatId: Int64
        let messageId: Int64
        var lastRenderedText: String
        var lastUpdatedAt: Date
    }

    public nonisolated let id: String = "telegram"
    public nonisolated let channelIds: [String]

    private let config: TelegramPluginConfig
    private let bot: TelegramBotAPI
    private let logger: Logger
    private var pollerTask: Task<Void, Never>?
    private var streams: [String: StreamState] = [:]
    /// Tracks the most recent inbound chatId per channelId for catch-all bindings (chatId == 0).
    private var activeChatIds: [String: Int64] = [:]

    public init(
        botToken: String,
        channelChatMap: [String: Int64],
        allowedUserIds: [Int64] = [],
        allowedChatIds: [Int64] = [],
        logger: Logger? = nil
    ) {
        self.config = TelegramPluginConfig(
            botToken: botToken,
            channelChatMap: channelChatMap,
            allowedUserIds: allowedUserIds,
            allowedChatIds: allowedChatIds
        )
        self.channelIds = Array(channelChatMap.keys)
        let resolvedLogger = logger ?? Logger(label: "sloppy.plugin.telegram")
        self.logger = resolvedLogger
        self.bot = TelegramBotAPI(botToken: botToken, logger: resolvedLogger)
    }

    func setActiveChatId(channelId: String, chatId: Int64) {
        activeChatIds[channelId] = chatId
    }

    public func start(inboundReceiver: any InboundMessageReceiver) async throws {
        guard pollerTask == nil else {
            logger.warning("Telegram plugin start() called but poller is already running.")
            return
        }
        let tokenPrefix = String(config.botToken.prefix(10))
        logger.info("Telegram gateway plugin starting. token=\(tokenPrefix)... channels=\(channelIds) allowedUsers=\(config.allowedUserIds.count)")
        if channelIds.isEmpty {
            logger.warning("No channel-chat mappings configured. Bot will receive messages but cannot route them to Sloppy channels.")
        }
        let botCommands = ChannelCommandHandler.commands.map {
            ["command": $0.name, "description": $0.description]
        }
        do {
            try await bot.setMyCommands(botCommands)
            logger.info("Telegram bot commands registered: \(botCommands.map { $0["command"] ?? "" })")
        } catch {
            logger.warning("Failed to register Telegram bot commands: \(error)")
        }

        let poller = TelegramPoller(
            bot: bot,
            receiver: inboundReceiver,
            config: config,
            logger: logger,
            onMessageRouted: { [self] channelId, chatId in
                await self.setActiveChatId(channelId: channelId, chatId: chatId)
            }
        )
        pollerTask = Task { await poller.run() }
    }

    public func stop() async {
        pollerTask?.cancel()
        pollerTask = nil
        streams.removeAll()
        logger.info("Telegram gateway plugin stopped.")
    }

    /// Returns the effective Telegram chatId for outbound messages.
    /// For catch-all bindings (configured chatId == 0) uses the last known active chatId.
    private func resolvedChatId(forChannelId channelId: String) -> Int64? {
        guard let configured = config.chatId(forChannelId: channelId) else { return nil }
        return configured == 0 ? activeChatIds[channelId] : configured
    }

    public func send(channelId: String, message: String) async throws {
        guard let chatId = resolvedChatId(forChannelId: channelId) else {
            logger.warning("No Telegram chat target for channel \(channelId). Message dropped.")
            return
        }
        _ = try await bot.sendMessage(chatId: chatId, text: message)
    }

    public func beginStreaming(channelId: String, userId: String) async throws -> GatewayOutboundStreamHandle {
        guard let chatId = resolvedChatId(forChannelId: channelId) else {
            logger.warning("No Telegram chat target for channel \(channelId). Stream start dropped.")
            throw TelegramAPIError.invalidResponse(method: "beginStreaming")
        }

        let placeholder = try await bot.sendMessage(chatId: chatId, text: "Thinking...")
        let handle = GatewayOutboundStreamHandle(id: UUID().uuidString)
        streams[handle.id] = StreamState(
            chatId: chatId,
            messageId: placeholder.messageId,
            lastRenderedText: "",
            lastUpdatedAt: .distantPast
        )
        return handle
    }

    public func updateStreaming(handle: GatewayOutboundStreamHandle, channelId: String, content: String) async throws {
        guard var state = streams[handle.id] else {
            return
        }

        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
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

        _ = try await bot.editMessageText(chatId: state.chatId, messageId: state.messageId, text: normalized)
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

        guard let finalContent = finalContent?.trimmingCharacters(in: .whitespacesAndNewlines),
              !finalContent.isEmpty
        else {
            try await bot.deleteMessage(chatId: state.chatId, messageId: state.messageId)
            return
        }

        guard finalContent != state.lastRenderedText else {
            return
        }

        _ = try await bot.editMessageText(chatId: state.chatId, messageId: state.messageId, text: finalContent)
    }
}
