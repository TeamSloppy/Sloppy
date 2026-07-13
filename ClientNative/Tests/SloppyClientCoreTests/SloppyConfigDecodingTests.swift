import Foundation
import SloppyClientCore
import Testing

@Suite("Sloppy config decoding")
struct SloppyConfigDecodingTests {
    @Test("decodes the current backend config shape")
    func decodesCurrentBackendConfigShape() throws {
        let data = Data(
            #"""
            {
              "listen": { "host": "0.0.0.0", "port": 25101 },
              "workspace": { "name": ".sloppy", "basePath": "." },
              "auth": { "token": "dev-token" },
              "memory": {
                "backend": "sqlite-local-vectors",
                "retrieval": { "topK": 8, "semanticWeight": 0.55, "keywordWeight": 0.35, "graphWeight": 0.1 },
                "retention": { "episodicDays": 90, "todoCompletedDays": 30, "bulletinDays": 180 }
              },
              "nodes": [
                { "id": "local", "title": "Local", "url": "", "token": "", "tokenEnv": "", "enabled": true, "kind": "local" }
              ],
              "channels": {
                "discord": {
                  "botToken": "discord-token",
                  "channelDiscordChannelMap": {},
                  "allowedGuildIds": ["guild-1"],
                  "allowedChannelIds": [],
                  "allowedUserIds": []
                },
                "telegram": {
                  "botToken": "telegram-token",
                  "channelChatMap": {},
                  "topicChannelMap": {},
                  "allowedUserIds": [],
                  "allowedChatIds": []
                },
                "channelInactivityDays": 2
              },
              "browser": {
                "enabled": false,
                "executablePath": "",
                "cdpEndpoint": "",
                "profileName": "default",
                "headless": false,
                "startupTimeoutMs": 10000,
                "additionalArguments": []
              },
              "mcp": {
                "servers": [
                  { "id": "filesystem", "transport": "stdio", "arguments": [], "headers": {}, "timeoutMs": 15000, "enabled": true, "exposeTools": true, "exposeResources": true, "exposePrompts": true }
                ]
              },
              "sqlitePath": "memory/core.sqlite"
            }
            """#.utf8
        )

        let config = try JSONDecoder().decode(SloppyConfig.self, from: data)

        #expect(config.nodes.first?.id == "local")
        #expect(config.browser.profilePath.isEmpty)
        #expect(config.mcp.servers.first?.command.isEmpty == true)
        #expect(config.channels.discord?.allowedGuildIds == ["guild-1"])
        #expect(config.channels.telegram?.botToken == "telegram-token")
    }

    @Test("continues to decode legacy string nodes")
    func decodesLegacyStringNodes() throws {
        let data = Data(
            #"""
            {
              "listen": { "host": "0.0.0.0", "port": 25101 },
              "auth": { "token": "dev-token" },
              "memory": {
                "backend": "sqlite-local-vectors",
                "retrieval": { "topK": 8, "semanticWeight": 0.55, "keywordWeight": 0.35, "graphWeight": 0.1 },
                "retention": { "episodicDays": 90, "todoCompletedDays": 30, "bulletinDays": 180 }
              },
              "nodes": ["local"],
              "sqlitePath": "memory/core.sqlite"
            }
            """#.utf8
        )

        let config = try JSONDecoder().decode(SloppyConfig.self, from: data)

        #expect(config.nodes == [SloppyConfig.Node(id: "local", title: "local", kind: "local")])
    }
}
