import Foundation
import ChannelPluginSupport
import Logging
import PluginSDK
import Protocols

actor DiscordGatewayLoop {
    private struct IncomingAuthor: Sendable {
        let id: String
        let username: String
        let globalName: String?
        let isBot: Bool

        var displayName: String {
            if let globalName, !globalName.isEmpty {
                return globalName
            }
            return username
        }
    }

    private struct IncomingMessage: Sendable {
        let id: String
        let channelId: String
        let guildId: String?
        let content: String
        let type: Int
        let author: IncomingAuthor
        let mentionUserIds: [String]
        let referencedMessageAuthorId: String?

        init?(payload: DiscordGatewayPayload) {
            guard payload.op == 0,
                  payload.t == "MESSAGE_CREATE",
                  let object = payload.d?.asObject,
                  let id = object["id"]?.asString,
                  let channelId = object["channel_id"]?.asString,
                  let content = object["content"]?.asString,
                  let type = object["type"]?.asInt,
                  let authorObject = object["author"]?.asObject,
                  let authorId = authorObject["id"]?.asString,
                  let username = authorObject["username"]?.asString
            else {
                return nil
            }

            let mentions = object["mentions"]?.asArray ?? []
            let mentionUserIds = mentions.compactMap { $0.asObject?["id"]?.asString }
            let referencedAuthor = object["referenced_message"]?.asObject?["author"]?.asObject?["id"]?.asString

            self.id = id
            self.channelId = channelId
            self.guildId = object["guild_id"]?.asString
            self.content = content
            self.type = type
            self.mentionUserIds = mentionUserIds
            self.referencedMessageAuthorId = referencedAuthor
            self.author = IncomingAuthor(
                id: authorId,
                username: username,
                globalName: authorObject["global_name"]?.asString,
                isBot: authorObject["bot"]?.asBool ?? false
            )
        }
    }

    private enum SessionControl: Error {
        case reconnect
    }

    private let client: any DiscordPlatformClient
    private let receiver: any InboundMessageReceiver
    private let config: DiscordPluginConfig
    /// Sloppy channel ids this plugin binds (for skill slash menu union).
    private let sloppyChannelIds: [String]
    private let commands: ChannelCommandHandler
    private let logger: Logger
    private var sequence: Int?
    private var botUserID: String?
    private var applicationId: String?

    init(
        client: any DiscordPlatformClient,
        receiver: any InboundMessageReceiver,
        config: DiscordPluginConfig,
        sloppyChannelIds: [String],
        logger: Logger
    ) {
        self.client = client
        self.receiver = receiver
        self.config = config
        self.sloppyChannelIds = sloppyChannelIds
        self.commands = ChannelCommandHandler(platformName: "Discord")
        self.logger = logger
    }

    func run() async {
        logger.info("Discord gateway loop started. Waiting for messages...")
        var reconnectAttempt = 0

        while !Task.isCancelled {
            do {
                try await runSession()
                reconnectAttempt = 0
            } catch is CancellationError {
                break
            } catch SessionControl.reconnect {
                reconnectAttempt += 1
                let delay = min(max(reconnectAttempt, 1) * 2, 30)
                logger.info("Discord gateway requested reconnect. Retrying in \(delay)s.")
                try? await Task.sleep(for: .seconds(delay))
            } catch {
                reconnectAttempt += 1
                let delay = min(max(reconnectAttempt, 1) * 2, 30)
                logger.warning("Discord gateway loop error: \(error). Retrying in \(delay)s.")
                try? await Task.sleep(for: .seconds(delay))
            }
        }

        logger.info("Discord gateway loop stopped.")
    }

    private func runSession() async throws {
        sequence = nil
        let url = try await client.gatewayURL()
        let session = try await client.connectGateway(url: url)

        defer {
            Task {
                await session.close()
            }
        }

        try await withTaskCancellationHandler {
            let hello = try await session.receive()
            let heartbeatInterval = try heartbeatInterval(from: hello)
            try await identify(session: session)

            let heartbeatTask = Task {
                await self.heartbeatLoop(session: session, intervalMilliseconds: heartbeatInterval)
            }
            defer {
                heartbeatTask.cancel()
            }

            while !Task.isCancelled {
                let payload = try await session.receive()
                if let sequence = payload.s {
                    self.sequence = sequence
                }
                try await handle(payload: payload, session: session)
            }
        } onCancel: {
            Task {
                await session.close()
            }
        }
    }

    private func heartbeatInterval(from payload: DiscordGatewayPayload) throws -> Int {
        guard payload.op == 10,
              let data = payload.d?.asObject,
              let interval = data["heartbeat_interval"]?.asInt
        else {
            throw DiscordTransportError.invalidResponse(method: "gateway.hello")
        }
        return interval
    }

    private func identify(session: any DiscordGatewaySession) async throws {
        let properties: [String: JSONValue] = [
            "os": .string("macOS"),
            "browser": .string("sloppy"),
            "device": .string("sloppy")
        ]
        let intents = 1 << 9
        let payload = DiscordGatewayOutboundPayload(
            op: 2,
            d: .object([
                "token": .string(config.botToken),
                "properties": .object(properties),
                "intents": .number(Double(intents))
            ])
        )
        try await session.send(payload)
    }

    private func heartbeatLoop(session: any DiscordGatewaySession, intervalMilliseconds: Int) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .milliseconds(intervalMilliseconds))
                guard !Task.isCancelled else {
                    return
                }
                try await session.send(
                    DiscordGatewayOutboundPayload(
                        op: 1,
                        d: sequence.map { .number(Double($0)) } ?? .null
                    )
                )
            } catch is CancellationError {
                return
            } catch {
                logger.warning("Discord heartbeat failed: \(error)")
                return
            }
        }
    }

    private func handle(
        payload: DiscordGatewayPayload,
        session: any DiscordGatewaySession
    ) async throws {
        switch payload.op {
        case 0:
            try await handleDispatch(payload)
        case 1:
            try await session.send(
                DiscordGatewayOutboundPayload(
                    op: 1,
                    d: sequence.map { .number(Double($0)) } ?? .null
                )
            )
        case 7, 9:
            throw SessionControl.reconnect
        case 10, 11:
            return
        default:
            return
        }
    }

    private func handleDispatch(_ payload: DiscordGatewayPayload) async throws {
        switch payload.t {
        case "READY":
            botUserID = payload.d?.asObject?["user"]?.asObject?["id"]?.asString
            applicationId = payload.d?.asObject?["application"]?.asObject?["id"]?.asString
            logger.info("Discord gateway READY received. botUserId=\(botUserID ?? "unknown") applicationId=\(applicationId ?? "unknown")")
            await registerCommands()
        case "MESSAGE_CREATE":
            if let message = IncomingMessage(payload: payload) {
                await handleIncomingMessage(message)
            }
        case "INTERACTION_CREATE":
            await handleInteraction(payload)
        default:
            return
        }
    }

    private func registerCommands() async {
        guard let applicationId else {
            logger.warning("Cannot register Discord commands: applicationId not available from READY payload.")
            return
        }
        var commandPayloads: [JSONValue] = ChannelCommandHandler.commands.map { cmd in
            var fields: [String: JSONValue] = [
                "name": .string(cmd.name),
                "description": .string(cmd.description),
                "type": .number(1)
            ]
            if let argument = cmd.argument {
                fields["options"] = .array([
                    .object([
                        "type": .number(3),
                        "name": .string(argument),
                        "description": .string(argument),
                        "required": .bool(false)
                    ])
                ])
            }
            return .object(fields)
        }
        let skillRows = await receiver.skillSlashMenuEntriesUnion(forChannelIDs: sloppyChannelIds)
        for row in skillRows {
            commandPayloads.append(
                .object([
                    "name": .string(row.name),
                    "description": .string(String(row.description.prefix(100))),
                    "type": .number(1)
                ])
            )
        }
        if commandPayloads.count > 100 {
            commandPayloads = Array(commandPayloads.prefix(100))
            logger.warning("Discord slash command list capped at 100 (including skills).")
        }
        do {
            try await client.registerGlobalCommands(applicationId: applicationId, commands: commandPayloads)
            logger.info("Discord global slash commands registered: \(commandPayloads.count) commands")
        } catch {
            logger.warning("Failed to register Discord global commands: \(error)")
        }
    }

    private func handleInteraction(_ payload: DiscordGatewayPayload) async {
        guard let data = payload.d?.asObject,
              let interactionId = data["id"]?.asString,
              let interactionToken = data["token"]?.asString,
              let commandName = data["data"]?.asObject?["name"]?.asString
        else {
            return
        }

        let options = data["data"]?.asObject?["options"]?.asArray ?? []
        let firstOptionValue = options.first?.asObject?["value"]?.asString ?? ""
        let text: String
        if firstOptionValue.isEmpty {
            text = "/\(commandName)"
        } else {
            text = "/\(commandName) \(firstOptionValue)"
        }

        let userId = data["member"]?.asObject?["user"]?.asObject?["id"]?.asString
            ?? data["user"]?.asObject?["id"]?.asString
            ?? "unknown"
        let displayName = data["member"]?.asObject?["user"]?.asObject?["global_name"]?.asString
            ?? data["member"]?.asObject?["user"]?.asObject?["username"]?.asString
            ?? data["user"]?.asObject?["global_name"]?.asString
            ?? data["user"]?.asObject?["username"]?.asString
            ?? "unknown"

        let discordChannelId = data["channel_id"]?.asString ?? ""
        let sloppyChannelId = config.channelId(forDiscordChannelId: discordChannelId)

        let messageContext = MessageContext(
            channelId: sloppyChannelId ?? discordChannelId,
            userId: "discord:\(userId)",
            platform: "discord",
            displayName: displayName
        )
        let skillTokens: [String]
        if let mappedSloppyChannelId = sloppyChannelId {
            skillTokens = await receiver.skillSlashCommandTokens(forChannelID: mappedSloppyChannelId)
        } else {
            skillTokens = []
        }
        let skillSet = Set(skillTokens.map { $0.lowercased() })
        if let localReply = commands.handle(text: text, context: messageContext, skillSlashTokensLowercased: skillSet) {
            do {
                try await client.createInteractionResponse(
                    interactionId: interactionId,
                    interactionToken: interactionToken,
                    type: 4,
                    content: trimmedContent(localReply)
                )
            } catch {
                logger.warning("Failed to respond to interaction \(interactionId): \(error)")
            }
            return
        }

        do {
            try await client.createInteractionResponse(
                interactionId: interactionId,
                interactionToken: interactionToken,
                type: 4,
                content: "Processing..."
            )
        } catch {
            logger.warning("Failed to ack interaction \(interactionId): \(error)")
        }

        guard let sloppyChannelId else {
            logger.warning("No Discord channel mapping for interaction channelId=\(discordChannelId).")
            return
        }

        let ok = await receiver.postMessage(
            channelId: sloppyChannelId,
            userId: "discord:\(userId)",
            content: text,
            topicId: nil,
            inboundContext: nil
        )
        if !ok {
            logger.warning("Failed to forward interaction to sloppy: channelId=\(sloppyChannelId)")
        }
    }

    private func handleIncomingMessage(_ message: IncomingMessage) async {
        let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            return
        }
        guard message.type == 0 else {
            return
        }
        guard !message.author.isBot else {
            return
        }
        if let botUserID, botUserID == message.author.id {
            return
        }

        logger.info(
            "Incoming Discord message: userId=\(message.author.id) channelId=\(message.channelId) guildId=\(message.guildId ?? "none") from=\(message.author.displayName) length=\(content.count)"
        )

        // Fast-path: config allowlist takes priority when non-empty
        if !config.allowedUserIds.isEmpty || !config.allowedGuildIds.isEmpty || !config.allowedChannelIds.isEmpty {
            if !config.isAllowed(
                userId: message.author.id,
                guildId: message.guildId,
                channelId: message.channelId
            ) {
                logger.warning(
                    "Blocked Discord message: userId=\(message.author.id) channelId=\(message.channelId) guildId=\(message.guildId ?? "none")"
                )
                _ = try? await client.sendMessage(
                    channelId: message.channelId,
                    content: trimmedContent(
                        """
                        Access denied.

                        Allow one or more of these IDs in your Discord config:
                        User ID: \(message.author.id)
                        Channel ID: \(message.channelId)
                        Guild ID: \(message.guildId ?? "n/a")
                        """
                    )
                )
                return
            }
        } else {
            let accessResult = await receiver.checkAccess(
                platform: "discord",
                platformUserId: message.author.id,
                displayName: message.author.displayName,
                chatId: message.channelId
            )
            switch accessResult {
            case .allowed:
                break
            case .pendingApproval(_, let msg):
                logger.info("Access pending: userId=\(message.author.id) channelId=\(message.channelId)")
                _ = try? await client.sendMessage(channelId: message.channelId, content: trimmedContent(msg))
                return
            case .blocked:
                logger.warning("Access blocked: userId=\(message.author.id) channelId=\(message.channelId)")
                _ = try? await client.sendMessage(channelId: message.channelId, content: "Access denied.")
                return
            }
        }

        guard let sloppyChannelId = config.channelId(forDiscordChannelId: message.channelId) else {
            logger.warning("No Discord channel mapping for channelId=\(message.channelId).")
            _ = try? await client.sendMessage(
                channelId: message.channelId,
                content: trimmedContent(
                    """
                    This Discord channel is not connected to any Sloppy channel.

                    Add the following binding to your config:
                    Channel ID: \(message.channelId)
                    """
                )
            )
            return
        }

        let messageContext = MessageContext(
            channelId: sloppyChannelId,
            userId: "discord:\(message.author.id)",
            platform: "discord",
            displayName: message.author.displayName
        )
        let skillTokens = await receiver.skillSlashCommandTokens(forChannelID: sloppyChannelId)
        let skillSet = Set(skillTokens.map { $0.lowercased() })
        if let localReply = commands.handle(text: content, context: messageContext, skillSlashTokensLowercased: skillSet) {
            _ = try? await client.sendMessage(
                channelId: message.channelId,
                content: trimmedContent(localReply)
            )
            return
        }

        let inboundContext = buildDiscordInboundContext(message: message)

        let ok = await receiver.postMessage(
            channelId: sloppyChannelId,
            userId: "discord:\(message.author.id)",
            content: content,
            topicId: nil,
            inboundContext: inboundContext
        )

        if !ok {
            _ = try? await client.sendMessage(
                channelId: message.channelId,
                content: "Failed to reach Sloppy. Please try again later."
            )
        }
    }

    private func buildDiscordInboundContext(message: IncomingMessage) -> ChannelInboundContext {
        if message.guildId == nil {
            return ChannelInboundContext(mentionsThisBot: true, isReplyToThisBot: true)
        }
        guard let botId = botUserID else {
            return ChannelInboundContext()
        }
        var mentions = message.mentionUserIds.contains(botId)
        if !mentions, message.content.contains("<@\(botId)>") {
            mentions = true
        }
        let replyToBot = message.referencedMessageAuthorId == botId
        return ChannelInboundContext(mentionsThisBot: mentions, isReplyToThisBot: replyToBot)
    }

    private func trimmedContent(_ value: String) -> String {
        let limit = 2_000
        if value.count <= limit {
            return value
        }
        let endIndex = value.index(value.startIndex, offsetBy: limit - 1)
        return String(value[..<endIndex]) + "…"
    }
}
