import Foundation
import Logging
import Testing
@testable import ChannelPluginDiscord
@testable import ChannelPluginSupport
import PluginSDK
import Protocols

private actor RecordingInboundReceiver: InboundMessageReceiver {
    struct Message: Sendable, Equatable {
        let channelId: String
        let userId: String
        let content: String
    }

    private var messages: [Message] = []
    private let shouldAccept: Bool

    init(shouldAccept: Bool = true) {
        self.shouldAccept = shouldAccept
    }

    func postMessage(channelId: String, userId: String, content: String) async -> Bool {
        messages.append(Message(channelId: channelId, userId: userId, content: content))
        return shouldAccept
    }

    func snapshot() -> [Message] {
        messages
    }
}

private actor MockDiscordGatewaySession: DiscordGatewaySession {
    private var bufferedPayloads: [DiscordGatewayPayload] = []
    private var waitingContinuations: [CheckedContinuation<DiscordGatewayPayload, Error>] = []
    private var sentPayloads: [DiscordGatewayOutboundPayload] = []

    func enqueue(_ payload: DiscordGatewayPayload) {
        if let continuation = waitingContinuations.first {
            waitingContinuations.removeFirst()
            continuation.resume(returning: payload)
            return
        }
        bufferedPayloads.append(payload)
    }

    func receive() async throws -> DiscordGatewayPayload {
        if !bufferedPayloads.isEmpty {
            return bufferedPayloads.removeFirst()
        }

        return try await withCheckedThrowingContinuation { continuation in
            waitingContinuations.append(continuation)
        }
    }

    func send(_ payload: DiscordGatewayOutboundPayload) async throws {
        sentPayloads.append(payload)
    }

    func close() async {
        let continuations = waitingContinuations
        waitingContinuations.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: CancellationError())
        }
    }

    func sent() -> [DiscordGatewayOutboundPayload] {
        sentPayloads
    }
}

private actor MockDiscordClient: DiscordPlatformClient {
    struct SentMessage: Sendable, Equatable {
        let channelId: String
        let content: String
    }

    struct EditedMessage: Sendable, Equatable {
        let channelId: String
        let messageId: String
        let content: String
    }

    private let session: MockDiscordGatewaySession
    private var sentMessages: [SentMessage] = []
    private var editedMessages: [EditedMessage] = []
    private var deletedMessages: [(channelId: String, messageId: String)] = []

    init(session: MockDiscordGatewaySession) {
        self.session = session
    }

    func gatewayURL() async throws -> URL {
        URL(string: "wss://gateway.discord.test")!
    }

    func connectGateway(url: URL) async throws -> any DiscordGatewaySession {
        session
    }

    func sendMessage(channelId: String, content: String) async throws -> DiscordRESTMessage {
        sentMessages.append(SentMessage(channelId: channelId, content: content))
        return DiscordRESTMessage(id: "message-\(sentMessages.count)", channelId: channelId)
    }

    func editMessage(channelId: String, messageId: String, content: String) async throws -> DiscordRESTMessage {
        editedMessages.append(EditedMessage(channelId: channelId, messageId: messageId, content: content))
        return DiscordRESTMessage(id: messageId, channelId: channelId)
    }

    func deleteMessage(channelId: String, messageId: String) async throws {
        deletedMessages.append((channelId: channelId, messageId: messageId))
    }

    private var registeredCommands: [JSONValue] = []
    private var interactionResponses: [(id: String, token: String, type: Int, content: String?)] = []

    func registerGlobalCommands(applicationId: String, commands: [JSONValue]) async throws {
        registeredCommands = commands
    }

    func createInteractionResponse(
        interactionId: String,
        interactionToken: String,
        type: Int,
        content: String?
    ) async throws {
        interactionResponses.append((id: interactionId, token: interactionToken, type: type, content: content))
    }

    func snapshot() -> (
        sent: [SentMessage],
        edited: [EditedMessage],
        deleted: [(channelId: String, messageId: String)],
        registeredCommands: [JSONValue],
        interactionResponses: [(id: String, token: String, type: Int, content: String?)]
    ) {
        (sentMessages, editedMessages, deletedMessages, registeredCommands, interactionResponses)
    }
}

private func helloPayload() -> DiscordGatewayPayload {
    DiscordGatewayPayload(
        op: 10,
        d: .object(["heartbeat_interval": .number(60_000)]),
        s: nil,
        t: nil
    )
}

private func readyPayload(botUserId: String, applicationId: String = "app-1") -> DiscordGatewayPayload {
    DiscordGatewayPayload(
        op: 0,
        d: .object([
            "user": .object([
                "id": .string(botUserId)
            ]),
            "application": .object([
                "id": .string(applicationId)
            ])
        ]),
        s: 1,
        t: "READY"
    )
}

private func messageCreatePayload(
    channelId: String,
    guildId: String? = "guild-1",
    userId: String,
    username: String = "alice",
    content: String,
    isBot: Bool = false,
    type: Int = 0
) -> DiscordGatewayPayload {
    var payload: [String: JSONValue] = [
        "id": .string(UUID().uuidString),
        "channel_id": .string(channelId),
        "content": .string(content),
        "type": .number(Double(type)),
        "author": .object([
            "id": .string(userId),
            "username": .string(username),
            "global_name": .string("Alice"),
            "bot": .bool(isBot)
        ])
    ]
    if let guildId {
        payload["guild_id"] = .string(guildId)
    }
    return DiscordGatewayPayload(op: 0, d: .object(payload), s: 2, t: "MESSAGE_CREATE")
}

private func waitUntil(
    timeout: Duration = .seconds(1),
    interval: Duration = .milliseconds(10),
    condition: @escaping @Sendable () async -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(for: interval)
    }
}

@Test
func discordPluginConfigResolvesMappingsAndAllowLists() {
    let config = DiscordPluginConfig(
        botToken: "discord-token",
        channelDiscordChannelMap: ["general": "discord-general"],
        allowedGuildIds: ["guild-1"],
        allowedChannelIds: ["discord-general"],
        allowedUserIds: ["user-1"]
    )

    #expect(config.discordChannelId(forChannelId: "general") == "discord-general")
    #expect(config.channelId(forDiscordChannelId: "discord-general") == "general")
    #expect(config.isAllowed(userId: "user-1", guildId: "guild-1", channelId: "discord-general"))
    #expect(!config.isAllowed(userId: "user-2", guildId: "guild-1", channelId: "discord-general"))
    #expect(!config.isAllowed(userId: "user-1", guildId: nil, channelId: "discord-general"))
}

@Test
func discordGatewayPluginForwardsMappedMessages() async throws {
    let session = MockDiscordGatewaySession()
    let client = MockDiscordClient(session: session)
    let plugin = DiscordGatewayPlugin(
        botToken: "discord-token",
        channelDiscordChannelMap: ["general": "discord-general"],
        logger: Logger(label: "tests.discord"),
        client: client
    )
    let receiver = RecordingInboundReceiver()

    try await plugin.start(inboundReceiver: receiver)
    await session.enqueue(helloPayload())
    await session.enqueue(readyPayload(botUserId: "bot-1"))
    await session.enqueue(
        messageCreatePayload(
            channelId: "discord-general",
            userId: "user-1",
            content: "hello from discord"
        )
    )
    try await waitUntil {
        await receiver.snapshot().count == 1
    }
    await plugin.stop()

    let messages = await receiver.snapshot()
    #expect(messages == [
        .init(
            channelId: "general",
            userId: "discord:user-1",
            content: "hello from discord"
        )
    ])

    let gatewaySent = await session.sent()
    #expect(gatewaySent.contains(where: { $0.op == 2 }))
}

@Test
func discordGatewayPluginIgnoresBotMessagesAndTransformsTaskCommand() async throws {
    let session = MockDiscordGatewaySession()
    let client = MockDiscordClient(session: session)
    let plugin = DiscordGatewayPlugin(
        botToken: "discord-token",
        channelDiscordChannelMap: ["general": "discord-general"],
        logger: Logger(label: "tests.discord"),
        client: client
    )
    let receiver = RecordingInboundReceiver()

    try await plugin.start(inboundReceiver: receiver)
    await session.enqueue(helloPayload())
    await session.enqueue(readyPayload(botUserId: "bot-1"))
    await session.enqueue(
        messageCreatePayload(
            channelId: "discord-general",
            userId: "bot-1",
            content: "ignore me",
            isBot: true
        )
    )
    await session.enqueue(
        messageCreatePayload(
            channelId: "discord-general",
            userId: "user-1",
            content: "/task ship it"
        )
    )
    try await waitUntil {
        await receiver.snapshot().count == 1
    }
    await plugin.stop()

    let messages = await receiver.snapshot()
    #expect(messages == [
        .init(
            channelId: "general",
            userId: "discord:user-1",
            content: "/task ship it"
        )
    ])
}

@Test
func discordGatewayPluginStreamingLifecycleUsesCreateEditDelete() async throws {
    let session = MockDiscordGatewaySession()
    let client = MockDiscordClient(session: session)
    let plugin = DiscordGatewayPlugin(
        botToken: "discord-token",
        channelDiscordChannelMap: ["general": "discord-general"],
        logger: Logger(label: "tests.discord"),
        client: client
    )

    let handle = try await plugin.beginStreaming(channelId: "general", userId: "assistant")
    try await plugin.updateStreaming(
        handle: handle,
        channelId: "general",
        content: "partial response"
    )
    try await plugin.endStreaming(
        handle: handle,
        channelId: "general",
        userId: "assistant",
        finalContent: nil
    )

    let snapshot = await client.snapshot()
    #expect(snapshot.sent == [
        .init(channelId: "discord-general", content: "Thinking...")
    ])
    #expect(snapshot.edited == [
        .init(channelId: "discord-general", messageId: "message-1", content: "partial response")
    ])
    #expect(snapshot.deleted.count == 1)
    #expect(snapshot.deleted[0].channelId == "discord-general")
    #expect(snapshot.deleted[0].messageId == "message-1")
}

@Test
func channelCommandHandlerCommandsListIsComplete() {
    let names = ChannelCommandHandler.commands.map { $0.name }
    #expect(names.contains("help"))
    #expect(names.contains("status"))
    #expect(names.contains("task"))
    #expect(names.contains("model"))
    #expect(names.contains("abort"))
    #expect(!ChannelCommandHandler.commands.isEmpty)
}

private func interactionCreatePayload(
    interactionId: String = "interaction-1",
    interactionToken: String = "token-abc",
    commandName: String,
    optionValue: String? = nil,
    channelId: String = "discord-general",
    userId: String = "user-1"
) -> DiscordGatewayPayload {
    var commandData: [String: JSONValue] = [
        "name": .string(commandName),
        "type": .number(1)
    ]
    if let optionValue {
        commandData["options"] = .array([
            .object([
                "name": .string("description"),
                "value": .string(optionValue)
            ])
        ])
    }
    let payload: [String: JSONValue] = [
        "id": .string(interactionId),
        "token": .string(interactionToken),
        "type": .number(2),
        "channel_id": .string(channelId),
        "data": .object(commandData),
        "member": .object([
            "user": .object([
                "id": .string(userId),
                "username": .string("alice"),
                "global_name": .string("Alice")
            ])
        ])
    ]
    return DiscordGatewayPayload(op: 0, d: .object(payload), s: 3, t: "INTERACTION_CREATE")
}

@Test
func discordGatewayRegistersCommandsOnReady() async throws {
    let session = MockDiscordGatewaySession()
    let client = MockDiscordClient(session: session)
    let plugin = DiscordGatewayPlugin(
        botToken: "discord-token",
        channelDiscordChannelMap: ["general": "discord-general"],
        logger: Logger(label: "tests.discord"),
        client: client
    )
    let receiver = RecordingInboundReceiver()

    try await plugin.start(inboundReceiver: receiver)
    await session.enqueue(helloPayload())
    await session.enqueue(readyPayload(botUserId: "bot-1"))

    try await waitUntil {
        let s = await client.snapshot()
        return !s.registeredCommands.isEmpty
    }
    await plugin.stop()

    let snapshot = await client.snapshot()
    #expect(!snapshot.registeredCommands.isEmpty)
    let commandNames = snapshot.registeredCommands.compactMap { $0.asObject?["name"]?.asString }
    #expect(commandNames.contains("help"))
    #expect(commandNames.contains("status"))
    #expect(commandNames.contains("task"))
    #expect(commandNames.contains("model"))
    #expect(commandNames.contains("abort"))
}

@Test
func discordInteractionHelpRespondsLocallyWithType4() async throws {
    let session = MockDiscordGatewaySession()
    let client = MockDiscordClient(session: session)
    let plugin = DiscordGatewayPlugin(
        botToken: "discord-token",
        channelDiscordChannelMap: ["general": "discord-general"],
        logger: Logger(label: "tests.discord"),
        client: client
    )
    let receiver = RecordingInboundReceiver()

    try await plugin.start(inboundReceiver: receiver)
    await session.enqueue(helloPayload())
    await session.enqueue(readyPayload(botUserId: "bot-1"))
    await session.enqueue(interactionCreatePayload(commandName: "help"))

    try await waitUntil {
        let s = await client.snapshot()
        return !s.interactionResponses.isEmpty
    }
    await plugin.stop()

    let snapshot = await client.snapshot()
    let helpResponse = snapshot.interactionResponses.first { $0.id == "interaction-1" }
    #expect(helpResponse != nil)
    #expect(helpResponse?.type == 4)
    #expect(helpResponse?.content?.contains("Available commands") == true)

    let forwarded = await receiver.snapshot()
    #expect(forwarded.isEmpty)
}

@Test
func discordInteractionTaskForwardsToCore() async throws {
    let session = MockDiscordGatewaySession()
    let client = MockDiscordClient(session: session)
    let plugin = DiscordGatewayPlugin(
        botToken: "discord-token",
        channelDiscordChannelMap: ["general": "discord-general"],
        logger: Logger(label: "tests.discord"),
        client: client
    )
    let receiver = RecordingInboundReceiver()

    try await plugin.start(inboundReceiver: receiver)
    await session.enqueue(helloPayload())
    await session.enqueue(readyPayload(botUserId: "bot-1"))
    await session.enqueue(
        interactionCreatePayload(commandName: "task", optionValue: "build the thing")
    )

    try await waitUntil {
        await receiver.snapshot().count == 1
    }
    await plugin.stop()

    let messages = await receiver.snapshot()
    #expect(messages.count == 1)
    #expect(messages[0].channelId == "general")
    #expect(messages[0].userId == "discord:user-1")
    #expect(messages[0].content == "/task build the thing")

    let snapshot = await client.snapshot()
    let ackResponse = snapshot.interactionResponses.first { $0.id == "interaction-1" }
    #expect(ackResponse?.type == 4)
    #expect(ackResponse?.content == "Processing...")
}
