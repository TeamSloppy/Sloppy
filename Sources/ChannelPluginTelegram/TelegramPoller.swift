import Foundation
import ChannelPluginSupport
import Logging
import PluginSDK
import Protocols

/// Long-polls Telegram for updates and forwards messages to sloppy via InboundMessageReceiver.
actor TelegramPoller {
    private struct PickerSession: Sendable {
        let bindingChannelId: String
        let messageThreadId: Int?
        let filter: String
        let models: [ProviderModelOption]
    }

    private let bot: TelegramBotAPI
    private let receiver: any InboundMessageReceiver
    private let config: TelegramPluginConfig
    private let commands: ChannelCommandHandler
    private let logger: Logger
    private let onMessageRouted: (@Sendable (String, Int64) async -> Void)?
    private let modelPickerBridge: (any TelegramModelPickerBridge)?
    private var offset: Int64? = nil
    /// Resolved via `getMe` for `/cmd@bot` routing and mention detection.
    private var botUserId: Int64 = 0
    private var botUsernameLowercased: String = ""
    /// Picker UI state keyed by the Telegram message id that hosts the keyboard.
    private var modelPickerSessions: [Int64: PickerSession] = [:]

    init(
        bot: TelegramBotAPI,
        receiver: any InboundMessageReceiver,
        config: TelegramPluginConfig,
        logger: Logger,
        onMessageRouted: (@Sendable (String, Int64) async -> Void)? = nil,
        modelPickerBridge: (any TelegramModelPickerBridge)? = nil
    ) {
        self.bot = bot
        self.receiver = receiver
        self.config = config
        self.commands = ChannelCommandHandler(platformName: "Telegram")
        self.logger = logger
        self.onMessageRouted = onMessageRouted
        self.modelPickerBridge = modelPickerBridge
    }

    func run() async {
        logger.info("Telegram poller started. Waiting for messages...")
        do {
            let me = try await bot.getMe()
            botUserId = me.id
            botUsernameLowercased = me.username?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            logger.info("Telegram bot identity: id=\(botUserId) username=@\(botUsernameLowercased)")
        } catch {
            logger.warning("getMe failed; command @suffix routing may be unreliable: \(error)")
        }
        while !Task.isCancelled {
            do {
                let updates = try await bot.getUpdates(offset: offset, timeout: 60)
                for update in updates {
                    offset = update.updateId + 1
                    if let query = update.callbackQuery {
                        await handleCallbackQuery(query)
                    } else if let message = update.message {
                        await handleMessage(message)
                    }
                }
            } catch is CancellationError {
                break
            } catch {
                logger.warning("Polling error: \(error). Retrying in 5s...")
                try? await Task.sleep(for: .seconds(5))
            }
        }
        logger.info("Telegram poller stopped.")
    }

    // MARK: - Callbacks (inline keyboard)

    private func handleCallbackQuery(_ query: TelegramBotAPI.CallbackQuery) async {
        guard let data = query.data, !data.isEmpty else {
            try? await bot.answerCallbackQuery(callbackQueryId: query.id)
            return
        }
        let userId = query.from.id
        guard let message = query.message else {
            try? await bot.answerCallbackQuery(callbackQueryId: query.id)
            return
        }
        let chatId = message.chat.id
        let messageThreadId = message.messageThreadId

        if !config.allowedUserIds.isEmpty, !config.isAllowed(userId: userId) {
            try? await bot.answerCallbackQuery(callbackQueryId: query.id, text: "Нет доступа.", showAlert: true)
            return
        } else if config.allowedUserIds.isEmpty {
            let accessResult = await receiver.checkAccess(
                platform: "telegram",
                platformUserId: String(userId),
                displayName: query.from.displayName,
                chatId: String(chatId)
            )
            switch accessResult {
            case .allowed:
                break
            case .pendingApproval, .blocked:
                try? await bot.answerCallbackQuery(callbackQueryId: query.id, text: "Нет доступа.", showAlert: true)
                return
            }
        }

        guard let bindingChannelId = config.channelId(forChatId: chatId) else {
            try? await bot.answerCallbackQuery(callbackQueryId: query.id, text: "Канал не привязан.", showAlert: true)
            return
        }

        switch TelegramModelPicker.parseCallback(data) {
        case .unknown:
            try? await bot.answerCallbackQuery(callbackQueryId: query.id)
        case .page(let messageId, let page):
            guard let session = modelPickerSessions[messageId] else {
                try? await bot.answerCallbackQuery(
                    callbackQueryId: query.id,
                    text: "Список устарел. Отправьте /model снова.",
                    showAlert: true
                )
                return
            }
            let currentId = await modelPickerBridge?.telegramPickerCurrentModelId(bindingChannelId: bindingChannelId)
            let totalPages = max(1, session.models.isEmpty ? 1 : Int(ceil(Double(session.models.count) / Double(TelegramModelPicker.pageSize))))
            let clamped = min(max(0, page), totalPages - 1)
            let body = TelegramModelPicker.buildPickerText(
                currentModelId: currentId,
                filter: session.filter,
                page: clamped,
                totalPages: totalPages,
                totalMatches: session.models.count
            )
            let keyboard = TelegramModelPicker.buildKeyboard(
                models: session.models,
                messageId: messageId,
                page: clamped
            )
            do {
                _ = try await bot.editMessageText(
                    chatId: chatId,
                    messageId: message.messageId,
                    text: body,
                    messageThreadId: messageThreadId,
                    replyMarkup: keyboard
                )
                try await bot.answerCallbackQuery(callbackQueryId: query.id)
            } catch {
                logger.warning("Failed to edit model picker: \(error)")
                try? await bot.answerCallbackQuery(callbackQueryId: query.id, text: "Не удалось обновить список.", showAlert: true)
            }

        case .select(let messageId, let index):
            guard let session = modelPickerSessions[messageId] else {
                try? await bot.answerCallbackQuery(
                    callbackQueryId: query.id,
                    text: "Список устарел. Отправьте /model снова.",
                    showAlert: true
                )
                return
            }
            guard session.models.indices.contains(index) else {
                try? await bot.answerCallbackQuery(callbackQueryId: query.id, text: "Неверный индекс.", showAlert: true)
                return
            }
            let modelId = session.models[index].id
            guard let bridge = modelPickerBridge else {
                try? await bot.answerCallbackQuery(callbackQueryId: query.id)
                return
            }
            let result = await bridge.telegramPickerApplyModel(bindingChannelId: session.bindingChannelId, modelId: modelId)
            switch result {
            case .success(let canonical):
                modelPickerSessions[messageId] = nil
                let emptyKeyboard: [[[String: String]]] = []
                do {
                    _ = try await bot.editMessageText(
                        chatId: chatId,
                        messageId: message.messageId,
                        text: "Модель установлена: \(canonical)",
                        messageThreadId: messageThreadId,
                        replyMarkup: emptyKeyboard
                    )
                } catch {
                    _ = try? await bot.sendMessage(
                        chatId: chatId,
                        text: "Модель установлена: \(canonical)",
                        messageThreadId: messageThreadId
                    )
                }
                try? await bot.answerCallbackQuery(callbackQueryId: query.id, text: "Готово")
            case .failure(let err):
                try? await bot.answerCallbackQuery(callbackQueryId: query.id, text: err.message, showAlert: true)
            }
        }
    }

    // MARK: - Messages

    private func handleMessage(_ message: TelegramBotAPI.Message) async {
        guard let rawText = message.text, !rawText.isEmpty else { return }
        if !ChannelSlashBotTargeting.telegramCommandTargetsThisBot(
            commandText: rawText,
            ourBotUsernameLowercased: botUsernameLowercased
        ) {
            logger.debug("Ignoring slash line targeted at another bot: \(rawText.prefix(80))")
            return
        }
        let text = ChannelSlashBotTargeting.stripTelegramBotUsernameSuffix(
            commandText: rawText,
            ourBotUsernameLowercased: botUsernameLowercased
        )
        let userId = message.from?.id ?? 0
        let chatId = message.chat.id
        let messageThreadId = message.messageThreadId
        let topicId = messageThreadId.map { String($0) }
        let displayName = message.from?.displayName ?? "unknown"
        let chatTitle = message.chat.title.map { " (\($0))" } ?? ""

        logger.info(
            "Incoming message: userId=\(userId) chatId=\(chatId)\(chatTitle) thread=\(messageThreadId.map { String($0) } ?? "none") from=\(displayName) length=\(rawText.count)"
        )

        if !config.allowedUserIds.isEmpty {
            if !config.isAllowed(userId: userId) {
                logger.warning("Blocked: userId=\(userId) chatId=\(chatId) — not in allowedUserIds")
                let hint = "Access denied.\n\nTo allow this user, add User ID \(userId) to your config's Access Control list."
                _ = try? await bot.sendMessage(chatId: chatId, text: hint, messageThreadId: messageThreadId)
                return
            }
        } else {
            let accessResult = await receiver.checkAccess(
                platform: "telegram",
                platformUserId: String(userId),
                displayName: displayName,
                chatId: String(chatId)
            )
            switch accessResult {
            case .allowed:
                break
            case .pendingApproval(_, let message):
                logger.info("Access pending: userId=\(userId) chatId=\(chatId)")
                _ = try? await bot.sendMessage(chatId: chatId, text: message, messageThreadId: messageThreadId)
                return
            case .blocked:
                logger.warning("Access blocked: userId=\(userId) chatId=\(chatId)")
                _ = try? await bot.sendMessage(chatId: chatId, text: "Access denied.", messageThreadId: messageThreadId)
                return
            }
        }

        guard let channelId = config.channelId(forChatId: chatId) else {
            logger.warning("No channel mapping for chatId=\(chatId). Known mappings: \(config.channelChatMap). Message dropped.")
            let hint = "This chat is not connected to any channel.\n\nTo route messages here, add a binding in the Channels → Bindings section (leave Chat ID empty to accept any chat)."
            _ = try? await bot.sendMessage(chatId: chatId, text: hint, messageThreadId: messageThreadId)
            return
        }

        await onMessageRouted?(channelId, chatId)
        logger.info("Routing message: chatId=\(chatId) → channelId=\(channelId)")

        let userIdString = "tg:\(userId)"

        let messageContext = MessageContext(
            channelId: channelId,
            userId: userIdString,
            platform: "telegram",
            displayName: displayName
        )
        let inboundContext = buildTelegramInboundContext(message: message, rawText: rawText)
        let skillTokens = await receiver.skillSlashCommandTokens(forChannelID: channelId)
        let skillTokenSet = Set(skillTokens.map { $0.lowercased() })
        if let localReply = commands.handle(
            text: text,
            context: messageContext,
            skillSlashTokensLowercased: skillTokenSet
        ) {
            logger.debug("Handled locally by CommandHandler, not forwarding to Sloppy.")
            _ = try? await bot.sendMessage(chatId: chatId, text: localReply, messageThreadId: messageThreadId)
            return
        }

        if let bridge = modelPickerBridge,
           await handleModelSlashCommand(
               text: text,
               bindingChannelId: channelId,
               chatId: chatId,
               messageThreadId: messageThreadId,
               bridge: bridge
           ) {
            return
        }

        let ok = await receiver.postMessage(
            channelId: channelId,
            userId: userIdString,
            content: text,
            topicId: topicId,
            inboundContext: inboundContext
        )

        if ok {
            logger.debug("Message forwarded to sloppy: channelId=\(channelId) userId=\(userIdString)")
        } else {
            logger.warning("Failed to forward message to sloppy: channelId=\(channelId)")
            _ = try? await bot.sendMessage(
                chatId: chatId,
                text: "Failed to reach Sloppy. Please try again later.",
                messageThreadId: messageThreadId
            )
        }
    }

    /// - Returns: `true` if the message was fully handled (picker or immediate set).
    private func handleModelSlashCommand(
        text: String,
        bindingChannelId: String,
        chatId: Int64,
        messageThreadId: Int?,
        bridge: any TelegramModelPickerBridge
    ) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard lower == "/model" || lower.hasPrefix("/model") else {
            return false
        }

        if isBareModelCommand(trimmed) {
            await presentModelPicker(
                bindingChannelId: bindingChannelId,
                chatId: chatId,
                messageThreadId: messageThreadId,
                bridge: bridge,
                filter: ""
            )
            return true
        }

        guard lower.hasPrefix("/model ") else {
            return false
        }

        let arg = String(trimmed.dropFirst("/model ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !arg.isEmpty else {
            await presentModelPicker(
                bindingChannelId: bindingChannelId,
                chatId: chatId,
                messageThreadId: messageThreadId,
                bridge: bridge,
                filter: ""
            )
            return true
        }

        let apply = await bridge.telegramPickerApplyModel(bindingChannelId: bindingChannelId, modelId: arg)
        switch apply {
        case .success(let canonical):
            _ = try? await bot.sendMessage(
                chatId: chatId,
                text: "Модель установлена: \(canonical)",
                messageThreadId: messageThreadId
            )
            return true
        case .failure:
            if arg.contains(":") {
                let list = await bridge.telegramPickerSortedModels()
                let sample = list.prefix(12).map(\.id).joined(separator: "\n")
                _ = try? await bot.sendMessage(
                    chatId: chatId,
                    text: "Неизвестная модель: \(arg)\n\nПримеры:\n\(sample)",
                    messageThreadId: messageThreadId
                )
                return true
            }
            await presentModelPicker(
                bindingChannelId: bindingChannelId,
                chatId: chatId,
                messageThreadId: messageThreadId,
                bridge: bridge,
                filter: arg
            )
            return true
        }
    }

    private func isBareModelCommand(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = t.lowercased()
        if lower == "/model" { return true }
        if lower.hasPrefix("/model@"), !t.contains(" ") {
            return true
        }
        return false
    }

    private func presentModelPicker(
        bindingChannelId: String,
        chatId: Int64,
        messageThreadId: Int?,
        bridge: any TelegramModelPickerBridge,
        filter: String
    ) async {
        let all = await bridge.telegramPickerSortedModels()
        let filtered = TelegramModelPicker.filterModels(all, query: filter)
        guard !filtered.isEmpty else {
            _ = try? await bot.sendMessage(
                chatId: chatId,
                text: "Нет моделей по фильтру «\(filter)». Очистите запрос: отправьте /model",
                messageThreadId: messageThreadId
            )
            return
        }

        let current = await bridge.telegramPickerCurrentModelId(bindingChannelId: bindingChannelId)
        let totalPages = max(1, Int(ceil(Double(filtered.count) / Double(TelegramModelPicker.pageSize))))
        let body = TelegramModelPicker.buildPickerText(
            currentModelId: current,
            filter: filter,
            page: 0,
            totalPages: totalPages,
            totalMatches: filtered.count
        )

        do {
            let sent = try await bot.sendMessage(
                chatId: chatId,
                text: body,
                messageThreadId: messageThreadId,
                showTyping: true
            )
            modelPickerSessions[sent.messageId] = PickerSession(
                bindingChannelId: bindingChannelId,
                messageThreadId: messageThreadId,
                filter: filter,
                models: filtered
            )
            let keyboard = TelegramModelPicker.buildKeyboard(
                models: filtered,
                messageId: sent.messageId,
                page: 0
            )
            _ = try await bot.editMessageText(
                chatId: chatId,
                messageId: sent.messageId,
                text: body,
                messageThreadId: messageThreadId,
                replyMarkup: keyboard
            )
        } catch {
            logger.warning("Failed to present model picker: \(error)")
            _ = try? await bot.sendMessage(
                chatId: chatId,
                text: "Не удалось показать список моделей. Попробуйте /model снова.",
                messageThreadId: messageThreadId
            )
        }
    }

    private func buildTelegramInboundContext(message: TelegramBotAPI.Message, rawText: String) -> ChannelInboundContext {
        if message.chat.type == "private" {
            return ChannelInboundContext(mentionsThisBot: true, isReplyToThisBot: true)
        }
        var mentions = false
        if !botUsernameLowercased.isEmpty {
            let needle = "@\(botUsernameLowercased)"
            if rawText.lowercased().contains(needle) {
                mentions = true
            }
        }
        if let entities = message.entities {
            for entity in entities {
                if entity.type == "text_mention", let user = entity.user, user.id == botUserId {
                    mentions = true
                    break
                }
            }
        }
        let replyToBot = message.replyToMessage?.from?.id == botUserId && botUserId != 0
        return ChannelInboundContext(mentionsThisBot: mentions, isReplyToThisBot: replyToBot)
    }
}
