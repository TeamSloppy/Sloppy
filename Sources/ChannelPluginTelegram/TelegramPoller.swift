import Foundation
import ChannelPluginSupport
import Logging
import PluginSDK
import Protocols

/// Long-polls Telegram for updates and forwards messages to sloppy via InboundMessageReceiver.
actor TelegramPoller {
    private enum PickerScreen: Sendable {
        case providers(page: Int)
        case models(providerId: String, providerPage: Int, page: Int)
    }

    private struct PickerSession: Sendable {
        let bindingChannelId: String
        let messageThreadId: Int?
        let filter: String
        let allModels: [ProviderModelOption]
        var screen: PickerScreen
    }

    private struct ProjectLinkSession: Sendable {
        let bindingChannelId: String
        let platformChatId: Int64
        let messageThreadId: Int?
        let projectOptions: [ChannelProjectLinkOption]
        let selectedProject: ChannelProjectLinkOption?
        let agentOptions: [ChannelProjectLinkAgentOption]
    }

    private let bot: TelegramBotAPI
    private let receiver: any InboundMessageReceiver
    private let config: TelegramPluginConfig
    private let commands: ChannelCommandHandler
    private let logger: Logger
    private let onMessageRouted: (@Sendable (String, Int64) async -> Void)?
    private let modelPickerBridge: (any TelegramModelPickerBridge)?
    private let toolApprovalBridge: (any ToolApprovalBridge)?
    private let planInputSessions: TelegramPlanInputSessionStore?
    private var offset: Int64? = nil
    /// Resolved via `getMe` for `/cmd@bot` routing and mention detection.
    private var botUserId: Int64 = 0
    private var botUsernameLowercased: String = ""
    /// Picker UI state keyed by the Telegram message id that hosts the keyboard.
    private var modelPickerSessions: [Int64: PickerSession] = [:]
    private var projectLinkSessions: [Int64: ProjectLinkSession] = [:]
    private var forwardBatcher = TelegramForwardBatcher()
    private var batchFlushTasks: [TelegramForwardBatcher.Key: Task<Void, Never>] = [:]
    private let batchFlushDelay: Duration = .milliseconds(900)

    init(
        bot: TelegramBotAPI,
        receiver: any InboundMessageReceiver,
        config: TelegramPluginConfig,
        logger: Logger,
        onMessageRouted: (@Sendable (String, Int64) async -> Void)? = nil,
        modelPickerBridge: (any TelegramModelPickerBridge)? = nil,
        toolApprovalBridge: (any ToolApprovalBridge)? = nil,
        planInputSessions: TelegramPlanInputSessionStore? = nil
    ) {
        self.bot = bot
        self.receiver = receiver
        self.config = config
        self.commands = ChannelCommandHandler(platformName: "Telegram")
        self.logger = logger
        self.onMessageRouted = onMessageRouted
        self.modelPickerBridge = modelPickerBridge
        self.toolApprovalBridge = toolApprovalBridge
        self.planInputSessions = planInputSessions
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
                if let api = error as? TelegramAPIError,
                   case .httpError(let status, _) = api,
                   status == 401 {
                    logger.error(
                        "Telegram polling unauthorized (401). Bot token is missing, revoked, or wrong. Fix `telegram` config and restart; polling will keep retrying every 5s."
                    )
                } else {
                    logger.warning("Polling error: \(error). Retrying in 5s...")
                }
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

        guard let bindingChannelId = config.channelId(forChatId: chatId, topicId: messageThreadId.map(String.init)) else {
            try? await bot.answerCallbackQuery(callbackQueryId: query.id, text: "Канал не привязан.", showAlert: true)
            return
        }

        if await handlePlanInputCallback(
            data: data,
            query: query,
            chatId: chatId,
            messageId: message.messageId,
            messageThreadId: messageThreadId,
            userId: userId,
            bindingChannelId: bindingChannelId
        ) {
            return
        }

        if await handleProjectLinkCallback(
            data: data,
            query: query,
            chatId: chatId,
            messageId: message.messageId,
            messageThreadId: messageThreadId
        ) {
            return
        }

        switch TelegramToolApproval.parseCallback(data) {
        case .unknown:
            break
        case .approve(let approvalId), .reject(let approvalId):
            guard let bridge = toolApprovalBridge else {
                try? await bot.answerCallbackQuery(callbackQueryId: query.id, text: "Approval bridge unavailable.", showAlert: true)
                return
            }
            let approved: Bool
            if case .approve = TelegramToolApproval.parseCallback(data) {
                approved = true
            } else {
                approved = false
            }
            let record = await bridge.resolveToolApproval(
                id: approvalId,
                approved: approved,
                decidedBy: "tg:\(userId)"
            )
            if record == nil {
                try? await bot.answerCallbackQuery(callbackQueryId: query.id, text: "Approval is no longer pending.", showAlert: true)
            } else {
                try? await bot.answerCallbackQuery(callbackQueryId: query.id, text: approved ? "Approved" : "Rejected")
            }
            return
        }

        switch TelegramModelPicker.parseCallback(data) {
        case .unknown:
            try? await bot.answerCallbackQuery(callbackQueryId: query.id)
        case .providersPage(let messageId, let page):
            guard var session = modelPickerSessions[messageId] else {
                try? await bot.answerCallbackQuery(
                    callbackQueryId: query.id,
                    text: "Список устарел. Отправьте /model снова.",
                    showAlert: true
                )
                return
            }
            session.screen = .providers(page: page)
            modelPickerSessions[messageId] = session
            await renderModelPicker(
                session: session,
                messageId: messageId,
                chatId: chatId,
                telegramMessageId: message.messageId,
                messageThreadId: messageThreadId,
                callbackQueryId: query.id
            )
        case .backToProviders(let messageId, let page):
            guard var session = modelPickerSessions[messageId] else {
                try? await bot.answerCallbackQuery(
                    callbackQueryId: query.id,
                    text: "Список устарел. Отправьте /model снова.",
                    showAlert: true
                )
                return
            }
            session.screen = .providers(page: page)
            modelPickerSessions[messageId] = session
            await renderModelPicker(
                session: session,
                messageId: messageId,
                chatId: chatId,
                telegramMessageId: message.messageId,
                messageThreadId: messageThreadId,
                callbackQueryId: query.id
            )
        case .provider(let messageId, let providerId, let page):
            guard var session = modelPickerSessions[messageId] else {
                try? await bot.answerCallbackQuery(
                    callbackQueryId: query.id,
                    text: "Список устарел. Отправьте /model снова.",
                    showAlert: true
                )
                return
            }
            let matches = TelegramModelPicker.filterModels(
                session.allModels,
                query: session.filter,
                providerId: providerId
            )
            guard !matches.isEmpty else {
                try? await bot.answerCallbackQuery(callbackQueryId: query.id, text: "У этого провайдера нет моделей по фильтру.", showAlert: true)
                return
            }
            session.screen = .models(providerId: providerId, providerPage: page, page: 0)
            modelPickerSessions[messageId] = session
            await renderModelPicker(
                session: session,
                messageId: messageId,
                chatId: chatId,
                telegramMessageId: message.messageId,
                messageThreadId: messageThreadId,
                callbackQueryId: query.id
            )
        case .page(let messageId, let page):
            guard var session = modelPickerSessions[messageId] else {
                try? await bot.answerCallbackQuery(
                    callbackQueryId: query.id,
                    text: "Список устарел. Отправьте /model снова.",
                    showAlert: true
                )
                return
            }
            switch session.screen {
            case .models(let providerId, let providerPage, _):
                session.screen = .models(providerId: providerId, providerPage: providerPage, page: page)
                modelPickerSessions[messageId] = session
                await renderModelPicker(
                    session: session,
                    messageId: messageId,
                    chatId: chatId,
                    telegramMessageId: message.messageId,
                    messageThreadId: messageThreadId,
                    callbackQueryId: query.id
                )
            case .providers:
                try? await bot.answerCallbackQuery(callbackQueryId: query.id)
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
            guard case .models(let providerId, _, _) = session.screen else {
                try? await bot.answerCallbackQuery(callbackQueryId: query.id, text: "Сначала выберите провайдера.", showAlert: true)
                return
            }
            let models = TelegramModelPicker.filterModels(
                session.allModels,
                query: session.filter,
                providerId: providerId
            )
            guard models.indices.contains(index) else {
                try? await bot.answerCallbackQuery(callbackQueryId: query.id, text: "Неверный индекс.", showAlert: true)
                return
            }
            let modelId = models[index].id
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

    private func handlePlanInputCallback(
        data: String,
        query: TelegramBotAPI.CallbackQuery,
        chatId: Int64,
        messageId: Int64,
        messageThreadId: Int?,
        userId: Int64,
        bindingChannelId: String
    ) async -> Bool {
        guard data.hasPrefix("pi:") else {
            return false
        }
        let parts = data.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let requestMessageId = Int64(parts[1]),
              let optionIndex = Int(parts[2]),
              let session = await planInputSessions?.get(messageId: requestMessageId),
              session.bindingChannelId == bindingChannelId,
              session.request.questions.count == 1,
              let question = session.request.questions.first,
              question.options.indices.contains(optionIndex)
        else {
            try? await bot.answerCallbackQuery(callbackQueryId: query.id, text: "Question expired. Send your answer as a message.", showAlert: true)
            return true
        }

        let option = question.options[optionIndex]
        let ok = await receiver.answerChannelPlanInputOption(
            channelId: bindingChannelId,
            userId: "tg:\(userId)",
            requestId: session.request.id,
            questionId: question.id,
            optionId: option.id,
            topicId: messageThreadId.map(String.init)
        )
        if ok {
            await planInputSessions?.remove(messageId: requestMessageId)
            _ = try? await bot.editMessageText(
                chatId: chatId,
                messageId: messageId,
                text: "Answer recorded: \(option.label)",
                messageThreadId: messageThreadId,
                replyMarkup: []
            )
            try? await bot.answerCallbackQuery(callbackQueryId: query.id, text: "Done")
        } else {
            try? await bot.answerCallbackQuery(callbackQueryId: query.id, text: "Could not record answer.", showAlert: true)
        }
        return true
    }

    // MARK: - Messages

    private func handleMessage(_ message: TelegramBotAPI.Message) async {
        let attachments = telegramAttachments(from: message)
        guard let rawText = message.text ?? message.caption ?? (attachments.isEmpty ? nil : "[Attachment]") else { return }
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

        guard let channelId = config.channelId(forChatId: chatId, topicId: topicId) else {
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

        if await handleProjectLinkSlashCommand(
            text: text,
            bindingChannelId: channelId,
            chatId: chatId,
            messageThreadId: messageThreadId
        ) {
            return
        }

        let processedAttachments = await TelegramAttachmentProcessor(
            bot: bot,
            logger: logger
        ).process(attachments)
        let attachmentText = TelegramAttachmentProcessor.contentWithTranscripts(
            content: text,
            attachments: processedAttachments
        )
        let processedText = TelegramForwardedMessage.contentForModel(
            text: attachmentText,
            message: message
        )

        let batchAction = forwardBatcher.consume(
            channelId: channelId,
            userId: userIdString,
            topicId: topicId,
            message: message,
            processedText: processedText,
            inboundContext: inboundContext,
            attachments: processedAttachments
        )

        switch batchAction {
        case .buffered(let key):
            scheduleBatchFlush(for: key)
            logger.debug("Buffered forwarded Telegram message: channelId=\(channelId) userId=\(userIdString)")
            return
        case .dispatch(let batch):
            cancelBatchFlush(for: batch.key)
            let ok = await receiver.postMessage(
                channelId: channelId,
                userId: userIdString,
                content: batch.content,
                topicId: topicId,
                inboundContext: batch.inboundContext,
                attachments: batch.attachments
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
    }

    private func scheduleBatchFlush(for key: TelegramForwardBatcher.Key) {
        batchFlushTasks[key]?.cancel()
        batchFlushTasks[key] = Task {
            try? await Task.sleep(for: batchFlushDelay)
            await flushBufferedBatch(for: key)
        }
    }

    private func cancelBatchFlush(for key: TelegramForwardBatcher.Key) {
        batchFlushTasks[key]?.cancel()
        batchFlushTasks[key] = nil
    }

    private func flushBufferedBatch(for key: TelegramForwardBatcher.Key) async {
        batchFlushTasks[key] = nil
        guard let batch = forwardBatcher.flush(key: key) else {
            return
        }
        let ok = await receiver.postMessage(
            channelId: key.channelId,
            userId: key.userId,
            content: batch.content,
            topicId: key.topicId,
            inboundContext: batch.inboundContext,
            attachments: batch.attachments
        )
        if ok {
            logger.debug("Flushed buffered Telegram batch: channelId=\(key.channelId) userId=\(key.userId)")
        } else {
            logger.warning("Failed to flush buffered Telegram batch: channelId=\(key.channelId)")
        }
    }

    private func telegramAttachments(from message: TelegramBotAPI.Message) -> [ChannelAttachment] {
        var result: [ChannelAttachment] = []
        if let photo = message.photo?.max(by: { ($0.fileSize ?? 0) < ($1.fileSize ?? 0) }) {
            result.append(ChannelAttachment(
                id: photo.fileUniqueId ?? photo.fileId,
                type: .image,
                mimeType: "image/jpeg",
                filename: "telegram-photo-\(photo.fileUniqueId ?? photo.fileId).jpg",
                sizeBytes: photo.fileSize,
                platformMetadata: ["platform": "telegram", "file_id": photo.fileId, "width": String(photo.width), "height": String(photo.height)]
            ))
        }
        appendTelegramMedia(message.voice, type: .voice, into: &result)
        appendTelegramMedia(message.audio, type: .audio, into: &result)
        appendTelegramMedia(message.document, type: .document, into: &result)
        appendTelegramMedia(message.video, type: .video, into: &result)
        appendTelegramMedia(message.animation, type: .video, into: &result)
        return result
    }

    private func appendTelegramMedia(
        _ media: TelegramBotAPI.MediaFile?,
        type preferredType: ChannelAttachmentType,
        into result: inout [ChannelAttachment]
    ) {
        guard let media else { return }
        let filename = media.fileName ?? "telegram-\(preferredType.rawValue)-\(media.fileUniqueId ?? media.fileId)"
        var metadata = ["platform": "telegram", "file_id": media.fileId]
        if let duration = media.duration { metadata["duration"] = String(duration) }
        result.append(ChannelAttachment(
            id: media.fileUniqueId ?? media.fileId,
            type: ChannelAttachment.inferredType(mimeType: media.mimeType, filename: filename, preferred: preferredType),
            mimeType: media.mimeType,
            filename: filename,
            sizeBytes: media.fileSize,
            platformMetadata: metadata
        ))
    }

    private func handleProjectLinkSlashCommand(
        text: String,
        bindingChannelId: String,
        chatId: Int64,
        messageThreadId: Int?
    ) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard lower == "/channel_link" || lower.hasPrefix("/channel_link ") else {
            return false
        }

        let options = await receiver.projectLinkOptions()
        guard !options.isEmpty else {
            _ = try? await bot.sendMessage(
                chatId: chatId,
                text: "No active projects found.",
                messageThreadId: messageThreadId
            )
            return true
        }

        let visible = Array(options.prefix(25))
        let extra = options.count > visible.count ? "\n\nShowing first 25 projects. Use Dashboard for the full list." : ""
        do {
            let sent = try await bot.sendMessage(
                chatId: chatId,
                text: "Choose a project for this channel/topic.\(extra)",
                messageThreadId: messageThreadId,
                showTyping: true
            )
            projectLinkSessions[sent.messageId] = ProjectLinkSession(
                bindingChannelId: bindingChannelId,
                platformChatId: chatId,
                messageThreadId: messageThreadId,
                projectOptions: visible,
                selectedProject: nil,
                agentOptions: []
            )
            _ = try await bot.editMessageText(
                chatId: chatId,
                messageId: sent.messageId,
                text: "Choose a project for this channel/topic.\(extra)",
                messageThreadId: messageThreadId,
                replyMarkup: projectLinkProjectKeyboard(messageId: sent.messageId, options: visible)
            )
        } catch {
            logger.warning("Failed to present project link picker: \(error)")
            _ = try? await bot.sendMessage(
                chatId: chatId,
                text: "Failed to show projects. Try again later.",
                messageThreadId: messageThreadId
            )
        }
        return true
    }

    private func handleProjectLinkCallback(
        data: String,
        query: TelegramBotAPI.CallbackQuery,
        chatId: Int64,
        messageId: Int64,
        messageThreadId: Int?
    ) async -> Bool {
        guard data.hasPrefix("pl:") else {
            return false
        }
        let parts = data.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 4,
              let pickerMessageId = Int64(parts[2]),
              let index = Int(parts[3]),
              let session = projectLinkSessions[pickerMessageId]
        else {
            try? await bot.answerCallbackQuery(callbackQueryId: query.id, text: "Project list expired. Send /channel_link again.", showAlert: true)
            return true
        }

        if parts[1] == "p" {
            guard session.projectOptions.indices.contains(index) else {
                try? await bot.answerCallbackQuery(callbackQueryId: query.id, text: "Project list expired. Send /channel_link again.", showAlert: true)
                return true
            }
            let project = session.projectOptions[index]
            let agents = await receiver.projectLinkAgentOptions(projectId: project.projectId)
            guard !agents.isEmpty else {
                try? await bot.answerCallbackQuery(callbackQueryId: query.id, text: "No agents are attached to this project.", showAlert: true)
                return true
            }
            let visibleAgents = Array(agents.prefix(25))
            projectLinkSessions[pickerMessageId] = ProjectLinkSession(
                bindingChannelId: session.bindingChannelId,
                platformChatId: session.platformChatId,
                messageThreadId: session.messageThreadId,
                projectOptions: session.projectOptions,
                selectedProject: project,
                agentOptions: visibleAgents
            )
            let extra = agents.count > visibleAgents.count ? "\n\nShowing first 25 agents. Use Dashboard for the full list." : ""
            _ = try? await bot.editMessageText(
                chatId: chatId,
                messageId: messageId,
                text: "Choose an agent for \(project.name).\(extra)",
                messageThreadId: messageThreadId,
                replyMarkup: projectLinkAgentKeyboard(messageId: pickerMessageId, options: visibleAgents)
            )
            try? await bot.answerCallbackQuery(callbackQueryId: query.id)
            return true
        }

        guard parts[1] == "a",
              let project = session.selectedProject,
              session.agentOptions.indices.contains(index)
        else {
            try? await bot.answerCallbackQuery(callbackQueryId: query.id, text: "Agent list expired. Send /channel_link again.", showAlert: true)
            return true
        }

        let agent = session.agentOptions[index]
        let title = session.messageThreadId.map { "Telegram topic \($0)" } ?? "Telegram chat"
        let result = await receiver.linkProjectChannel(
            projectId: project.projectId,
            channelId: session.bindingChannelId,
            topicId: session.messageThreadId.map(String.init),
            title: title,
            routeChannelId: agent.channelId,
            platform: "telegram",
            platformChannelId: String(session.platformChatId)
        )

        switch result {
        case .linked(_, let projectName, let channelId, let status):
            projectLinkSessions[pickerMessageId] = nil
            let text = status == "existing"
                ? "Already linked to \(projectName).\n\nAgent: \(agent.name)\nChannel: \(channelId)"
                : "Linked to \(projectName).\n\nAgent: \(agent.name)\nChannel: \(channelId)"
            _ = try? await bot.editMessageText(
                chatId: chatId,
                messageId: messageId,
                text: text,
                messageThreadId: messageThreadId,
                replyMarkup: []
            )
            try? await bot.answerCallbackQuery(callbackQueryId: query.id, text: "Done")
        case .conflict(_, let ownerProjectName):
            try? await bot.answerCallbackQuery(
                callbackQueryId: query.id,
                text: "Already linked to \(ownerProjectName).",
                showAlert: true
            )
        case .notFound:
            try? await bot.answerCallbackQuery(callbackQueryId: query.id, text: "Project not found.", showAlert: true)
        case .failed(let message):
            try? await bot.answerCallbackQuery(callbackQueryId: query.id, text: message, showAlert: true)
        }
        return true
    }

    private func projectLinkProjectKeyboard(messageId: Int64, options: [ChannelProjectLinkOption]) -> [[[String: String]]] {
        var rows: [[[String: String]]] = []
        for (index, option) in options.enumerated() {
            rows.append([[
                "text": String(option.name.prefix(48)),
                "callback_data": "pl:p:\(messageId):\(index)"
            ]])
        }
        return rows
    }

    private func projectLinkAgentKeyboard(messageId: Int64, options: [ChannelProjectLinkAgentOption]) -> [[[String: String]]] {
        var rows: [[[String: String]]] = []
        for (index, option) in options.enumerated() {
            rows.append([[
                "text": String(option.name.prefix(48)),
                "callback_data": "pl:a:\(messageId):\(index)"
            ]])
        }
        return rows
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

        do {
            let sent = try await bot.sendMessage(
                chatId: chatId,
                text: "Открываю список провайдеров…",
                messageThreadId: messageThreadId,
                showTyping: true
            )
            let session = PickerSession(
                bindingChannelId: bindingChannelId,
                messageThreadId: messageThreadId,
                filter: filter,
                allModels: filtered,
                screen: .providers(page: 0)
            )
            modelPickerSessions[sent.messageId] = session
            await renderModelPicker(
                session: session,
                messageId: sent.messageId,
                chatId: chatId,
                telegramMessageId: sent.messageId,
                messageThreadId: messageThreadId,
                callbackQueryId: nil
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

    private func renderModelPicker(
        session: PickerSession,
        messageId: Int64,
        chatId: Int64,
        telegramMessageId: Int64,
        messageThreadId: Int?,
        callbackQueryId: String?
    ) async {
        let currentId = await modelPickerBridge?.telegramPickerCurrentModelId(bindingChannelId: session.bindingChannelId)
        let body: String
        let keyboard: [[[String: String]]]

        switch session.screen {
        case .providers(let page):
            let providers = TelegramModelPicker.providerEntries(from: session.allModels)
            let totalPages = max(1, providers.isEmpty ? 1 : Int(ceil(Double(providers.count) / Double(TelegramModelPicker.providerPageSize))))
            let clamped = providers.isEmpty ? 0 : min(max(0, page), totalPages - 1)
            body = TelegramModelPicker.buildProviderPickerText(
                currentModelId: currentId,
                filter: session.filter,
                page: clamped,
                totalPages: totalPages,
                totalProviders: providers.count
            )
            keyboard = TelegramModelPicker.buildProviderKeyboard(
                providers: providers,
                messageId: messageId,
                page: clamped
            )
        case .models(let providerId, let providerPage, let page):
            let models = TelegramModelPicker.filterModels(
                session.allModels,
                query: session.filter,
                providerId: providerId
            )
            let totalPages = max(1, models.isEmpty ? 1 : Int(ceil(Double(models.count) / Double(TelegramModelPicker.pageSize))))
            let clamped = models.isEmpty ? 0 : min(max(0, page), totalPages - 1)
            body = TelegramModelPicker.buildPickerText(
                currentModelId: currentId,
                filter: session.filter,
                providerTitle: TelegramModelPicker.providerTitle(providerId),
                page: clamped,
                totalPages: totalPages,
                totalMatches: models.count
            )
            keyboard = TelegramModelPicker.buildKeyboard(
                models: models,
                messageId: messageId,
                providerPage: providerPage,
                page: clamped
            )
        }

        do {
            _ = try await bot.editMessageText(
                chatId: chatId,
                messageId: telegramMessageId,
                text: body,
                messageThreadId: messageThreadId,
                replyMarkup: keyboard
            )
            if let callbackQueryId {
                try await bot.answerCallbackQuery(callbackQueryId: callbackQueryId)
            }
        } catch {
            logger.warning("Failed to edit model picker: \(error)")
            if let callbackQueryId {
                try? await bot.answerCallbackQuery(callbackQueryId: callbackQueryId, text: "Не удалось обновить список.", showAlert: true)
            }
        }
    }

    private func buildTelegramInboundContext(message: TelegramBotAPI.Message, rawText: String) -> ChannelInboundContext {
        if message.chat.type == "private" {
            return ChannelInboundContext(mentionsThisBot: true, isReplyToThisBot: true)
        }
        var mentions = TelegramForwardedMessage.from(message) != nil
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
