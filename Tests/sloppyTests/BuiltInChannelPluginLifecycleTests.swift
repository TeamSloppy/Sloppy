import Foundation
import Testing
@testable import sloppy
import PluginSDK
import Protocols

private actor LifecycleGatewayPlugin: GatewayPlugin {
    struct Snapshot: Sendable {
        let startedCount: Int
        let stoppedCount: Int
    }

    nonisolated let id: String
    nonisolated let channelIds: [String]

    private var startedCount: Int = 0
    private var stoppedCount: Int = 0

    init(id: String, channelIds: [String]) {
        self.id = id
        self.channelIds = channelIds
    }

    func start(inboundReceiver: any InboundMessageReceiver) async throws {
        startedCount += 1
    }

    func stop() async {
        stoppedCount += 1
    }

    func send(channelId: String, message: String) async throws {}

    func snapshot() -> Snapshot {
        Snapshot(startedCount: startedCount, stoppedCount: stoppedCount)
    }
}

private final class LifecyclePluginProbe: @unchecked Sendable {
    var discordPlugins: [LifecycleGatewayPlugin] = []
}

@Test
func bootstrapChannelPluginsSeedsDiscordRecord() async throws {
    var config = CoreConfig.default
    config.channels = .init(
        discord: .init(
            botToken: "discord-token",
            channelDiscordChannelMap: ["general": "123456789012345678"]
        )
    )

    let probe = LifecyclePluginProbe()
    let factory = BuiltInGatewayPluginFactory(
        makeTelegram: { pluginConfig in
            LifecycleGatewayPlugin(
                id: "telegram",
                channelIds: Array(pluginConfig.channelChatMap.keys)
            )
        },
        makeDiscord: { pluginConfig in
            let plugin = LifecycleGatewayPlugin(
                id: "discord",
                channelIds: Array(pluginConfig.channelDiscordChannelMap.keys)
            )
            probe.discordPlugins.append(plugin)
            return plugin
        }
    )

    let service = CoreService(
        config: config,
        persistenceBuilder: InMemoryCorePersistenceBuilder(),
        builtInGatewayPluginFactory: factory
    )
    await service.bootstrapChannelPlugins()
    defer {
        Task {
            await service.shutdownChannelPlugins()
        }
    }

    let plugins = await service.listChannelPlugins()
    let discordRecord = try #require(plugins.first(where: { $0.id == "discord" }))
    #expect(discordRecord.type == "discord")
    #expect(discordRecord.channelIds == ["general"])
    #expect(discordRecord.deliveryMode == ChannelPluginRecord.DeliveryMode.inProcess)
    #expect(probe.discordPlugins.count == 1)
    #expect(await probe.discordPlugins[0].snapshot().startedCount == 1)
}

@Test
func updateConfigReloadsAndRemovesDiscordPlugin() async throws {
    let configPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("core-discord-config-\(UUID().uuidString).json")
        .path

    var initialConfig = CoreConfig.default
    initialConfig.channels = .init(
        discord: .init(
            botToken: "discord-token",
            channelDiscordChannelMap: ["general": "123456789012345678"]
        )
    )

    let probe = LifecyclePluginProbe()
    let factory = BuiltInGatewayPluginFactory(
        makeTelegram: { pluginConfig in
            LifecycleGatewayPlugin(
                id: "telegram",
                channelIds: Array(pluginConfig.channelChatMap.keys)
            )
        },
        makeDiscord: { pluginConfig in
            let plugin = LifecycleGatewayPlugin(
                id: "discord",
                channelIds: Array(pluginConfig.channelDiscordChannelMap.keys)
            )
            probe.discordPlugins.append(plugin)
            return plugin
        }
    )

    let service = CoreService(
        config: initialConfig,
        configPath: configPath,
        persistenceBuilder: InMemoryCorePersistenceBuilder(),
        builtInGatewayPluginFactory: factory
    )
    await service.bootstrapChannelPlugins()

    var updatedConfig = initialConfig
    updatedConfig.channels = .init(
        discord: .init(
            botToken: "discord-token-2",
            channelDiscordChannelMap: ["ops": "999999999999999999"]
        )
    )
    _ = try await service.updateConfig(updatedConfig)

    #expect(probe.discordPlugins.count == 2)
    #expect(await probe.discordPlugins[0].snapshot().stoppedCount == 1)
    #expect(await probe.discordPlugins[1].snapshot().startedCount == 1)

    let reloadedPlugins = await service.listChannelPlugins()
    let discordRecord = try #require(reloadedPlugins.first(where: { $0.id == "discord" }))
    #expect(discordRecord.channelIds == ["ops"])

    var removedConfig = updatedConfig
    removedConfig.channels = .init(
        discord: .init(
            botToken: "",
            channelDiscordChannelMap: ["ops": "999999999999999999"]
        )
    )
    _ = try await service.updateConfig(removedConfig)

    #expect(await probe.discordPlugins[1].snapshot().stoppedCount == 1)
    #expect(await service.listChannelPlugins().isEmpty)
    await service.shutdownChannelPlugins()
}
