import Foundation
import ChannelPluginSupport
import Logging
import PluginSDK
import Protocols

/// In-process GatewayPlugin that bridges Telegram to Sloppy channels.
/// Uses long-polling to receive messages and InboundMessageReceiver to forward them to Sloppy.
actor TelegramPlanInputSessionStore {
    struct Session: Sendable {
        let bindingChannelId: String
        let request: PlanInputRequest
    }

    private var sessions: [Int64: Session] = [:]

    func set(messageId: Int64, session: Session) {
        sessions[messageId] = session
    }

    func get(messageId: Int64) -> Session? {
        sessions[messageId]
    }

    func remove(messageId: Int64) {
        sessions[messageId] = nil
    }
}

public actor TelegramGatewayPlugin: StreamingGatewayPlugin, ToolApprovalGatewayPlugin, PlanInputGatewayPlugin, TelegramWidgetGateway {
    static let thinkingDraftHTML = "<tg-thinking>Thinking...</tg-thinking>"

    private struct StreamState: Sendable {
        enum Mode: Sendable {
            case richDraft(draftId: Int64)
            case editableMessage(messageId: Int64)
        }

        let chatId: Int64
        /// Telegram forum topic thread; nil for non-forum chats.
        let messageThreadId: Int?
        var mode: Mode
        var lastRenderedText: String
        var lastUpdatedAt: Date
    }

    private struct ApprovalMessageState: Sendable {
        let chatId: Int64
        let messageId: Int64
        let messageThreadId: Int?
        var lastRenderedText: String
        var lastUpdatedAt: Date
    }

    public nonisolated let id: String = "telegram"
    public nonisolated let channelIds: [String]

    private let config: TelegramPluginConfig
    private let bot: TelegramBotAPI
    private let logger: Logger
    private let modelPickerBridge: (any TelegramModelPickerBridge)?
    private let toolApprovalBridge: (any ToolApprovalBridge)?
    private let widgetSessions = TelegramWidgetSessionStore()
    private let planInputSessions = TelegramPlanInputSessionStore()
    private var pollerTask: Task<Void, Never>?
    private var streams: [String: StreamState] = [:]
    private var approvalMessages: [String: ApprovalMessageState] = [:]
    /// Tracks the most recent inbound chatId per channelId for catch-all bindings (chatId == 0).
    private var activeChatIds: [String: Int64] = [:]

    public init(
        botToken: String,
        channelChatMap: [String: Int64],
        topicChannelMap: [String: String] = [:],
        allowedUserIds: [Int64] = [],
        allowedChatIds: [Int64] = [],
        logger: Logger? = nil,
        modelPickerBridge: (any TelegramModelPickerBridge)? = nil,
        toolApprovalBridge: (any ToolApprovalBridge)? = nil
    ) {
        self.config = TelegramPluginConfig(
            botToken: botToken,
            channelChatMap: channelChatMap,
            topicChannelMap: topicChannelMap,
            allowedUserIds: allowedUserIds,
            allowedChatIds: allowedChatIds
        )
        self.channelIds = Array(Set(channelChatMap.keys).union(topicChannelMap.values))
        let resolvedLogger = logger ?? Logger(label: "sloppy.plugin.telegram")
        self.logger = resolvedLogger
        self.bot = TelegramBotAPI(botToken: botToken, logger: resolvedLogger)
        self.modelPickerBridge = modelPickerBridge
        self.toolApprovalBridge = toolApprovalBridge
    }

    // Internal transport injection for isolated gateway integration tests.
    init(config: TelegramPluginConfig, bot: TelegramBotAPI) {
        self.config = config
        self.channelIds = Array(Set(config.channelChatMap.keys).union(config.topicChannelMap.values))
        self.logger = Logger(label: "sloppy.plugin.telegram")
        self.bot = bot
        self.modelPickerBridge = nil
        self.toolApprovalBridge = nil
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
        var botCommands = ChannelCommandHandler.commands(for: .telegram).compactMap { command -> [String: String]? in
            guard command.name.range(of: #"^[a-z0-9_]{1,32}$"#, options: .regularExpression) != nil else {
                return nil
            }
            return ["command": command.name, "description": command.description]
        }
        let skillRows = await inboundReceiver.skillSlashMenuEntriesUnion(forChannelIDs: channelIds)
        for row in skillRows {
            botCommands.append(["command": row.name, "description": row.description])
        }
        if botCommands.count > 100 {
            botCommands = Array(botCommands.prefix(100))
            logger.warning("Telegram bot command list capped at 100 (including skills).")
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
            },
            modelPickerBridge: modelPickerBridge,
            toolApprovalBridge: toolApprovalBridge,
            widgetSessions: widgetSessions,
            planInputSessions: planInputSessions
        )
        pollerTask = Task { await poller.run() }
    }

    public func stop() async {
        pollerTask?.cancel()
        pollerTask = nil
        await widgetSessions.clear()
        streams.removeAll()
        approvalMessages.removeAll()
        logger.info("Telegram gateway plugin stopped.")
    }

    /// Returns the effective Telegram chatId for outbound messages.
    /// For catch-all bindings (configured chatId == 0) uses the last known active chatId.
    /// `channelId` may be topic-scoped (see ``ChannelGatewayScope``); config keys use the binding id only.
    private func resolvedChatId(forChannelId channelId: String) -> Int64? {
        let bindingId = ChannelGatewayScope.parse(channelId).baseChannelId
        guard let configured = config.chatId(forChannelId: bindingId) else { return nil }
        return configured == 0 ? activeChatIds[bindingId] : configured
    }

    private func messageThreadId(fromTopicId topicId: String?) -> Int? {
        guard let topicId, !topicId.isEmpty else { return nil }
        return Int(topicId)
    }

    private func effectiveMessageThreadId(channelId: String, topicId: String?) -> Int? {
        if let n = messageThreadId(fromTopicId: topicId) { return n }
        return ChannelGatewayScope.parse(channelId).topicKey.flatMap { Int($0) }
    }

    public func send(channelId: String, message: String, topicId: String?) async throws {
        guard let chatId = resolvedChatId(forChannelId: channelId) else {
            logger.warning("No Telegram chat target for channel \(channelId). Message dropped.")
            return
        }
        let threadId = effectiveMessageThreadId(channelId: channelId, topicId: topicId)
        for (index, chunk) in TelegramMessageSplitter.split(message, maxCharacters: TelegramMessageSplitter.richMaxCharacters).enumerated() {
            try await sendRichMessageWithFallback(
                chatId: chatId,
                markdown: chunk,
                messageThreadId: threadId,
                showTyping: index == 0
            )
        }
    }

    public func sendWidget(owner: TelegramWidgetOwner, request: TelegramWidgetRequest) async throws -> String {
        let binding = ChannelGatewayScope.parse(owner.channelID).baseChannelId
        // A catch-all's last-active-chat is not an authenticated destination. Fail closed.
        guard let chatID = config.chatId(forChannelId: binding), chatID != 0,
              config.allowedChatIds.isEmpty || config.allowedChatIds.contains(chatID),
              config.isAllowed(userId: owner.userID) else { throw TelegramWidgetError.forbidden }
        try TelegramWidgetValidation.validate(html: request.html, caption: request.caption, chatData: request.chatData)
        guard request.actions.count <= 32, Set(request.actions).count == request.actions.count,
              request.actions.allSatisfy({ (1...64).contains($0.utf8.count) && !$0.contains("\0") })
        else { throw TelegramWidgetError.invalidPayload }
        let threadID = effectiveMessageThreadId(channelId: owner.channelID, topicId: nil)
        if chatID < 0 {
            _ = try await bot.sendMessage(chatId: chatID, text: request.caption, messageThreadId: threadID)
            return "text_fallback"
        }
        guard chatID == owner.userID else { throw TelegramWidgetError.forbidden }
        do {
            let message = try await bot.sendWidget(chatId: chatID, html: request.html, caption: request.caption,
                chatData: request.chatData, allowQueries: !request.actions.isEmpty, messageThreadId: threadID)
            return await widgetSessions.register(owner: owner, chatID: chatID, messageID: message.messageId, actions: request.actions)
        } catch TelegramAPIError.httpError(let status, let body) where status == 404 && Self.isUnknownWidgetMethod(body) {
            _ = try await bot.sendMessage(chatId: chatID, text: request.caption, messageThreadId: threadID)
            return "text_fallback"
        }
    }

    static func isUnknownWidgetMethod(_ body: String) -> Bool {
        // Exact Telegram protocol error, not arbitrary network/authentication failures.
        guard let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any] else { return false }
        return object["description"] as? String == "Not Found"
    }

    public func updateWidget(owner: TelegramWidgetOwner, handle: String, chatData: String) async throws {
        guard let entry = await widgetSessions.entry(handle: handle, owner: owner) else { throw TelegramWidgetError.unknownHandle }
        try await bot.editMessageWidgetData(chatId: entry.chatID, messageId: entry.messageID, chatData: chatData)
    }

    public func presentPlanInputRequest(
        channelId: String,
        userId _: String,
        request: PlanInputRequest,
        topicId: String?
    ) async throws {
        guard let chatId = resolvedChatId(forChannelId: channelId) else {
            logger.warning("No Telegram chat target for plan input \(request.id).")
            return
        }
        let threadId = effectiveMessageThreadId(channelId: channelId, topicId: topicId)
        let sent = try await bot.sendMessage(
            chatId: chatId,
            text: Self.planInputText(request),
            messageThreadId: threadId,
            replyMarkup: Self.planInputKeyboard(messageId: 0, request: request),
            showTyping: false
        )
        let keyboard = Self.planInputKeyboard(messageId: sent.messageId, request: request)
        _ = try await bot.editMessageText(
            chatId: chatId,
            messageId: sent.messageId,
            text: Self.planInputText(request),
            messageThreadId: threadId,
            replyMarkup: keyboard
        )
        await planInputSessions.set(
            messageId: sent.messageId,
            session: .init(bindingChannelId: ChannelGatewayScope.parse(channelId).baseChannelId, request: request)
        )
    }

    public func presentToolApproval(_ approval: ToolApprovalRecord) async throws {
        guard let channelId = approval.channelId,
              let chatId = resolvedChatId(forChannelId: channelId)
        else {
            logger.warning("No Telegram chat target for tool approval \(approval.id).")
            return
        }

        let threadId = effectiveMessageThreadId(channelId: channelId, topicId: approval.topicId)
        let sent = try await bot.sendMessage(
            chatId: chatId,
            text: TelegramToolApproval.pendingText(approval),
            messageThreadId: threadId,
            replyMarkup: TelegramToolApproval.keyboard(id: approval.id),
            showTyping: false
        )
        approvalMessages[approval.id] = ApprovalMessageState(
            chatId: chatId,
            messageId: sent.messageId,
            messageThreadId: threadId,
            lastRenderedText: TelegramToolApproval.pendingText(approval),
            lastUpdatedAt: Date()
        )
    }

    public func updateToolApproval(_ approval: ToolApprovalRecord) async throws {
        guard let state = approvalMessages.removeValue(forKey: approval.id) else {
            return
        }
        _ = try await bot.editMessageText(
            chatId: state.chatId,
            messageId: state.messageId,
            text: TelegramToolApproval.resolvedText(approval),
            messageThreadId: state.messageThreadId,
            replyMarkup: []
        )
    }

    public func beginStreaming(channelId: String, userId: String, topicId: String?) async throws -> GatewayOutboundStreamHandle {
        guard let chatId = resolvedChatId(forChannelId: channelId) else {
            logger.warning("No Telegram chat target for channel \(channelId). Stream start dropped.")
            throw TelegramAPIError.invalidResponse(method: "beginStreaming")
        }

        let threadId = effectiveMessageThreadId(channelId: channelId, topicId: topicId)
        let handle = GatewayOutboundStreamHandle(id: UUID().uuidString)
        let draftId = Self.makeDraftId()
        do {
            try await bot.sendRichMessageDraft(
                chatId: chatId,
                draftId: draftId,
                html: Self.thinkingDraftHTML,
                messageThreadId: threadId
            )
            streams[handle.id] = StreamState(
                chatId: chatId,
                messageThreadId: threadId,
                mode: .richDraft(draftId: draftId),
                lastRenderedText: "",
                lastUpdatedAt: .distantPast
            )
        } catch {
            logger.debug("Telegram rich message draft failed; falling back to editable stream: \(error)")
            let placeholder = try await bot.sendMessage(chatId: chatId, text: "Thinking...", messageThreadId: threadId)
            streams[handle.id] = StreamState(
                chatId: chatId,
                messageThreadId: threadId,
                mode: .editableMessage(messageId: placeholder.messageId),
                lastRenderedText: "",
                lastUpdatedAt: .distantPast
            )
        }
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

        let maxCharacters: Int
        switch state.mode {
        case .richDraft:
            maxCharacters = TelegramMessageSplitter.richMaxCharacters
        case .editableMessage:
            maxCharacters = TelegramMessageSplitter.maxCharacters
        }
        let rendered = TelegramMessageSplitter.split(normalized, maxCharacters: maxCharacters).first ?? normalized
        guard rendered != state.lastRenderedText else {
            return
        }

        switch state.mode {
        case .richDraft(let draftId):
            do {
                try await bot.sendRichMessageDraft(
                    chatId: state.chatId,
                    draftId: draftId,
                    markdown: rendered,
                    messageThreadId: state.messageThreadId
                )
            } catch {
                logger.debug("Telegram rich draft update failed; switching stream to editable message: \(error)")
                let placeholder = try await bot.sendMessage(
                    chatId: state.chatId,
                    text: rendered,
                    messageThreadId: state.messageThreadId,
                    showTyping: false
                )
                state.mode = .editableMessage(messageId: placeholder.messageId)
            }
        case .editableMessage(let messageId):
            _ = try await bot.editMessageText(
                chatId: state.chatId,
                messageId: messageId,
                text: rendered,
                messageThreadId: state.messageThreadId
            )
        }
        state.lastRenderedText = rendered
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
            if case .editableMessage(let messageId) = state.mode {
                try await bot.deleteMessage(
                    chatId: state.chatId,
                    messageId: messageId,
                    messageThreadId: state.messageThreadId
                )
            }
            return
        }

        if case .richDraft = state.mode {
            for (index, chunk) in TelegramMessageSplitter.split(finalContent, maxCharacters: TelegramMessageSplitter.richMaxCharacters).enumerated() {
                try await sendRichMessageWithFallback(
                    chatId: state.chatId,
                    markdown: chunk,
                    messageThreadId: state.messageThreadId,
                    showTyping: index == 0
                )
            }
            return
        }

        let chunks = TelegramMessageSplitter.split(finalContent)
        guard let firstChunk = chunks.first else {
            return
        }

        if firstChunk != state.lastRenderedText {
            guard case .editableMessage(let messageId) = state.mode else {
                return
            }
            _ = try await bot.editMessageText(
                chatId: state.chatId,
                messageId: messageId,
                text: firstChunk,
                messageThreadId: state.messageThreadId
            )
        } else if chunks.count == 1 {
            return
        }

        for chunk in chunks.dropFirst() {
            _ = try await bot.sendMessage(
                chatId: state.chatId,
                text: chunk,
                messageThreadId: state.messageThreadId,
                showTyping: false
            )
        }
    }

    private static func makeDraftId() -> Int64 {
        Int64.random(in: 1...Int64.max)
    }

    private func sendRichMessageWithFallback(
        chatId: Int64,
        markdown: String,
        messageThreadId: Int?,
        showTyping: Bool
    ) async throws {
        do {
            _ = try await bot.sendRichMessage(
                chatId: chatId,
                markdown: markdown,
                messageThreadId: messageThreadId,
                showTyping: showTyping
            )
        } catch {
            logger.warning("Telegram rich message send failed; falling back to sendMessage: \(error)")
            for (index, chunk) in TelegramMessageSplitter.split(markdown).enumerated() {
                _ = try await bot.sendMessage(
                    chatId: chatId,
                    text: chunk,
                    messageThreadId: messageThreadId,
                    showTyping: showTyping && index == 0
                )
            }
        }
    }

    private static func planInputText(_ request: PlanInputRequest) -> String {
        var lines: [String] = [request.title ?? "Plan input requested"]
        for (index, question) in request.questions.enumerated() {
            lines.append("")
            lines.append("\(index + 1). \(question.question)")
            for option in question.options {
                if let description = option.description, !description.isEmpty {
                    lines.append("- \(option.label): \(description)")
                } else {
                    lines.append("- \(option.label)")
                }
            }
        }
        lines.append("")
        if request.questions.count == 1 {
            lines.append("Tap an option, or send your own answer as the next message.")
        } else {
            lines.append("Send custom answers as the next message, one line per question.")
        }
        return lines.joined(separator: "\n")
    }

    private static func planInputKeyboard(messageId: Int64, request: PlanInputRequest) -> [[[String: String]]]? {
        guard request.questions.count == 1, let question = request.questions.first else {
            return nil
        }
        return question.options.enumerated().map { index, option in
            [[
                "text": String(option.label.prefix(64)),
                "callback_data": "pi:\(messageId):\(index)"
            ]]
        }
    }
}
