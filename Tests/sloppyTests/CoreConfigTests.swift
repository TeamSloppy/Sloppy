import Foundation
import Foundation
import Testing
@testable import sloppy

@Test
func missingOnboardingConfigFallsBackToIncompleteState() throws {
    let json =
        """
        {
          "listen": { "host": "0.0.0.0", "port": 25101 },
          "auth": { "token": "dev-token" },
          "models": [],
          "memory": { "backend": "sqlite-local-vectors" },
          "nodes": ["local"],
          "gateways": [],
          "plugins": [],
          "sqlitePath": "core.sqlite"
        }
        """

    let decoded = try JSONDecoder().decode(CoreConfig.self, from: Data(json.utf8))
    #expect(decoded.onboarding.completed == false)
}

@Test
func missingVisorConfigFallsBackToDefaults() throws {
    let json =
        """
        {
          "listen": { "host": "0.0.0.0", "port": 25101 },
          "auth": { "token": "dev-token" },
          "models": [],
          "memory": { "backend": "sqlite-local-vectors" },
          "nodes": ["local"],
          "gateways": [],
          "plugins": [],
          "sqlitePath": "core.sqlite"
        }
        """

    let decoded = try JSONDecoder().decode(CoreConfig.self, from: Data(json.utf8))

    #expect(decoded.visor.scheduler.enabled)
    #expect(decoded.visor.scheduler.intervalSeconds == 300)
    #expect(decoded.visor.scheduler.jitterSeconds == 60)
    #expect(decoded.visor.bootstrapBulletin)
    #expect(decoded.visor.model == nil)
    #expect(decoded.visor.bulletinMaxWords == 300)
}

@Test
func visorModelConfigParsedFromJSON() throws {
    let json =
        """
        {
          "listen": { "host": "0.0.0.0", "port": 25101 },
          "auth": { "token": "dev-token" },
          "models": [],
          "memory": { "backend": "sqlite-local-vectors" },
          "nodes": ["local"],
          "gateways": [],
          "plugins": [],
          "sqlitePath": "core.sqlite",
          "visor": {
            "model": "openai:gpt-4o-mini",
            "bulletinMaxWords": 500,
            "bootstrapBulletin": false,
            "scheduler": { "enabled": false, "intervalSeconds": 600, "jitterSeconds": 30 }
          }
        }
        """

    let decoded = try JSONDecoder().decode(CoreConfig.self, from: Data(json.utf8))

    #expect(decoded.visor.model == "openai:gpt-4o-mini")
    #expect(decoded.visor.bulletinMaxWords == 500)
    #expect(decoded.visor.bootstrapBulletin == false)
    #expect(decoded.visor.scheduler.enabled == false)
    #expect(decoded.visor.scheduler.intervalSeconds == 600)
}

@Test
func resolvedWorkspaceAndSQLiteURLsForRelativePath() {
    var config = CoreConfig.default
    config.workspace = .init(name: "bot-runtime", basePath: ".")
    config.sqlitePath = "storage/core.sqlite"

    let workspaceURL = config.resolvedWorkspaceRootURL(currentDirectory: "/tmp/slop")
    let sqliteURL = config.resolvedSQLiteURL(currentDirectory: "/tmp/slop")

    #expect(workspaceURL.standardizedFileURL.path == "/tmp/slop/bot-runtime")
    #expect(sqliteURL.standardizedFileURL.path == "/tmp/slop/bot-runtime/storage/core.sqlite")
}

@Test
func resolvedSQLiteURLKeepsAbsolutePath() {
    var config = CoreConfig.default
    config.sqlitePath = "/var/lib/slop/core.sqlite"

    let sqliteURL = config.resolvedSQLiteURL(currentDirectory: "/tmp/slop")
    #expect(sqliteURL.path == "/var/lib/slop/core.sqlite")
}

@Test
func resolvedWorkspaceSupportsHomeShortcuts() {
    var tildeConfig = CoreConfig.default
    tildeConfig.workspace = .init(name: "workspace", basePath: "~")

    let tildeWorkspace = tildeConfig.resolvedWorkspaceRootURL(currentDirectory: "/tmp/slop")
    let homePath = FileManager.default.homeDirectoryForCurrentUser.path
    #expect(tildeWorkspace.standardizedFileURL.path == "\(homePath)/workspace")

    var envConfig = CoreConfig.default
    envConfig.workspace = .init(name: "workspace", basePath: "$HOME")

    let envWorkspace = envConfig.resolvedWorkspaceRootURL(currentDirectory: "/tmp/slop")
    #expect(envWorkspace.standardizedFileURL.path == "\(homePath)/workspace")
}

@Test
func defaultConfigPathResolvesInsideWorkspaceRoot() {
    let workspace = CoreConfig.Workspace(name: "workspace-dev", basePath: "/tmp/slop")
    let resolved = CoreConfig.defaultConfigPath(for: workspace, currentDirectory: "/unused")
    #expect(resolved == "/tmp/slop/workspace-dev/sloppy.json")
}

@Test
func defaultConfigPathUsesDotSloppyWorkspaceByDefault() {
    let resolved = CoreConfig.defaultConfigPath(currentDirectory: "/tmp/slop")
    #expect(URL(fileURLWithPath: resolved).standardizedFileURL.path == "/tmp/slop/.sloppy/sloppy.json")
}

@Test
func defaultSQLitePathIsInsideMemorySubdirectory() {
    let config = CoreConfig.default
    let sqliteURL = config.resolvedSQLiteURL(currentDirectory: "/tmp/slop")
    #expect(sqliteURL.standardizedFileURL.path == "/tmp/slop/.sloppy/memory/core.sqlite")
}

@Test
func memoryProviderSupportsRemoteAliasAndKeepsSettings() throws {
    let json =
        """
        {
          "listen": { "host": "0.0.0.0", "port": 25101 },
          "workspace": { "name": "workspace", "basePath": "~" },
          "auth": { "token": "dev-token" },
          "models": [],
          "memory": {
            "backend": "sqlite-local-vectors",
            "provider": {
              "mode": "remote",
              "endpoint": "https://memory.example.com",
              "timeoutMs": 5000,
              "apiKeyEnv": "MEMORY_API_KEY"
            }
          },
          "nodes": ["local"],
          "gateways": [],
          "plugins": [],
          "channels": { "telegram": null },
          "sqlitePath": "core.sqlite"
        }
        """

    let decoded = try JSONDecoder().decode(CoreConfig.self, from: Data(json.utf8))
    #expect(decoded.memory.provider.mode == .http)
    #expect(decoded.memory.provider.endpoint == "https://memory.example.com")
    #expect(decoded.memory.provider.timeoutMs == 5000)
    #expect(decoded.memory.provider.apiKeyEnv == "MEMORY_API_KEY")
}

@Test
func memoryProviderSupportsMCPModeAndCustomToolNames() throws {
    let json =
        """
        {
          "listen": { "host": "0.0.0.0", "port": 25101 },
          "workspace": { "name": "workspace", "basePath": "~" },
          "auth": { "token": "dev-token" },
          "models": [],
          "memory": {
            "backend": "sqlite-local-vectors",
            "provider": {
              "mode": "mcp",
              "mcpServer": "memory-server",
              "mcpTools": {
                "upsert": "mem_upsert",
                "query": "mem_query",
                "delete": "mem_delete",
                "health": "mem_health"
              }
            }
          },
          "mcp": {
            "servers": [
              {
                "id": "memory-server",
                "transport": "stdio",
                "command": "npx",
                "arguments": ["-y", "@acme/memory-mcp"]
              }
            ]
          },
          "nodes": ["local"],
          "gateways": [],
          "plugins": [],
          "sqlitePath": "core.sqlite"
        }
        """

    let decoded = try JSONDecoder().decode(CoreConfig.self, from: Data(json.utf8))
    #expect(decoded.memory.provider.mode == .mcp)
    #expect(decoded.memory.provider.mcpServer == "memory-server")
    #expect(decoded.memory.provider.mcpTools.upsert == "mem_upsert")
    #expect(decoded.memory.provider.mcpTools.query == "mem_query")
    #expect(decoded.mcp.servers.count == 1)
    #expect(decoded.mcp.servers[0].transport == .stdio)
}

@Test
func missingMCPConfigFallsBackToEmptyServers() throws {
    let json =
        """
        {
          "listen": { "host": "0.0.0.0", "port": 25101 },
          "auth": { "token": "dev-token" },
          "models": [],
          "memory": { "backend": "sqlite-local-vectors" },
          "nodes": ["local"],
          "gateways": [],
          "plugins": [],
          "sqlitePath": "core.sqlite"
        }
        """

    let decoded = try JSONDecoder().decode(CoreConfig.self, from: Data(json.utf8))
    #expect(decoded.mcp.servers.isEmpty)
    #expect(decoded.memory.provider.mcpTools.upsert == "memory_upsert")
}

@Test
func discordChannelSettingsDecodeWhenPresent() throws {
    let json =
        """
        {
          "listen": { "host": "0.0.0.0", "port": 25101 },
          "workspace": { "name": "workspace", "basePath": "~" },
          "auth": { "token": "dev-token" },
          "models": [],
          "memory": { "backend": "sqlite-local-vectors" },
          "nodes": ["local"],
          "gateways": [],
          "plugins": [],
          "channels": {
            "discord": {
              "botToken": "discord-token",
              "channelDiscordChannelMap": {
                "general": "123456789012345678"
              },
              "allowedGuildIds": ["987654321098765432"],
              "allowedChannelIds": [],
              "allowedUserIds": ["555555555555555555"]
            },
            "telegram": null
          },
          "sqlitePath": "core.sqlite"
        }
        """

    let decoded = try JSONDecoder().decode(CoreConfig.self, from: Data(json.utf8))

    #expect(decoded.channels.discord?.botToken == "discord-token")
    #expect(decoded.channels.discord?.channelDiscordChannelMap["general"] == "123456789012345678")
    #expect(decoded.channels.discord?.allowedGuildIds == ["987654321098765432"])
    #expect(decoded.channels.discord?.allowedUserIds == ["555555555555555555"])
}

@Test
func discordChannelSettingsRoundTripPreservesStringIDs() throws {
    var config = CoreConfig.default
    config.channels = .init(
        discord: .init(
            botToken: "discord-token",
            channelDiscordChannelMap: [
                "general": "123456789012345678",
                "ops": "999999999999999999"
            ],
            allowedGuildIds: ["111111111111111111"],
            allowedChannelIds: ["123456789012345678"],
            allowedUserIds: ["222222222222222222"]
        )
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(config)
    let decoded = try JSONDecoder().decode(CoreConfig.self, from: data)

    #expect(decoded.channels.discord?.channelDiscordChannelMap["general"] == "123456789012345678")
    #expect(decoded.channels.discord?.channelDiscordChannelMap["ops"] == "999999999999999999")
    #expect(decoded.channels.discord?.allowedGuildIds == ["111111111111111111"])
    #expect(decoded.channels.discord?.allowedChannelIds == ["123456789012345678"])
    #expect(decoded.channels.discord?.allowedUserIds == ["222222222222222222"])
}

@Test
func gitSyncSettingsDecodeWhenPresent() throws {
    let json =
        """
        {
          "listen": { "host": "0.0.0.0", "port": 25101 },
          "workspace": { "name": "workspace", "basePath": "~" },
          "auth": { "token": "dev-token" },
          "models": [],
          "memory": { "backend": "sqlite-local-vectors" },
          "nodes": ["local"],
          "gateways": [],
          "plugins": [],
          "channels": { "telegram": null },
          "gitSync": {
            "enabled": true,
            "authToken": "ghp_test",
            "repository": "acme/workspace-sync",
            "branch": "sync/main",
            "schedule": {
              "frequency": "daily",
              "time": "18:00"
            },
            "conflictStrategy": "remote_wins"
          },
          "sqlitePath": "core.sqlite"
        }
        """

    let decoded = try JSONDecoder().decode(CoreConfig.self, from: Data(json.utf8))
    #expect(decoded.gitSync.enabled == true)
    #expect(decoded.gitSync.authToken == "ghp_test")
    #expect(decoded.gitSync.repository == "acme/workspace-sync")
    #expect(decoded.gitSync.branch == "sync/main")
    #expect(decoded.gitSync.schedule.frequency == .daily)
    #expect(decoded.gitSync.schedule.time == "18:00")
    #expect(decoded.gitSync.conflictStrategy == .remoteWins)
}

@Test
func missingSearchToolsFallsBackToDefaults() throws {
    let json =
        """
        {
          "listen": { "host": "0.0.0.0", "port": 25101 },
          "auth": { "token": "dev-token" },
          "models": [],
          "memory": { "backend": "sqlite-local-vectors" },
          "nodes": ["local"],
          "gateways": [],
          "plugins": [],
          "sqlitePath": "core.sqlite"
        }
        """

    let decoded = try JSONDecoder().decode(CoreConfig.self, from: Data(json.utf8))

    #expect(decoded.searchTools.activeProvider == .perplexity)
    #expect(decoded.searchTools.providers.brave.apiKey.isEmpty)
    #expect(decoded.searchTools.providers.perplexity.apiKey.isEmpty)
}

@Test
func searchToolsDecodeWhenPresent() throws {
    let json =
        """
        {
          "listen": { "host": "0.0.0.0", "port": 25101 },
          "auth": { "token": "dev-token" },
          "models": [],
          "memory": { "backend": "sqlite-local-vectors" },
          "nodes": ["local"],
          "gateways": [],
          "plugins": [],
          "searchTools": {
            "activeProvider": "brave",
            "providers": {
              "brave": { "apiKey": "brave-config-key" },
              "perplexity": { "apiKey": "pplx-config-key" }
            }
          },
          "sqlitePath": "core.sqlite"
        }
        """

    let decoded = try JSONDecoder().decode(CoreConfig.self, from: Data(json.utf8))

    #expect(decoded.searchTools.activeProvider == .brave)
    #expect(decoded.searchTools.providers.brave.apiKey == "brave-config-key")
    #expect(decoded.searchTools.providers.perplexity.apiKey == "pplx-config-key")
}

@Test
func missingProxyConfigFallsBackToDisabledDefaults() throws {
    let json =
        """
        {
          "listen": { "host": "0.0.0.0", "port": 25101 },
          "auth": { "token": "dev-token" },
          "models": [],
          "memory": { "backend": "sqlite-local-vectors" },
          "nodes": ["local"],
          "gateways": [],
          "plugins": [],
          "sqlitePath": "core.sqlite"
        }
        """

    let decoded = try JSONDecoder().decode(CoreConfig.self, from: Data(json.utf8))

    #expect(decoded.proxy.enabled == false)
    #expect(decoded.proxy.type == .socks5)
    #expect(decoded.proxy.host == "")
    #expect(decoded.proxy.port == 1080)
    #expect(decoded.proxy.username == "")
    #expect(decoded.proxy.password == "")
}

@Test
func proxyConfigParsedFromJSON() throws {
    let json =
        """
        {
          "listen": { "host": "0.0.0.0", "port": 25101 },
          "auth": { "token": "dev-token" },
          "models": [],
          "memory": { "backend": "sqlite-local-vectors" },
          "nodes": ["local"],
          "gateways": [],
          "plugins": [],
          "sqlitePath": "core.sqlite",
          "proxy": {
            "enabled": true,
            "type": "socks5",
            "host": "127.0.0.1",
            "port": 1080,
            "username": "user",
            "password": "pass"
          }
        }
        """

    let decoded = try JSONDecoder().decode(CoreConfig.self, from: Data(json.utf8))

    #expect(decoded.proxy.enabled == true)
    #expect(decoded.proxy.type == .socks5)
    #expect(decoded.proxy.host == "127.0.0.1")
    #expect(decoded.proxy.port == 1080)
    #expect(decoded.proxy.username == "user")
    #expect(decoded.proxy.password == "pass")
}

@Test
func proxyConfigHttpTypeParsedFromJSON() throws {
    let json =
        """
        {
          "listen": { "host": "0.0.0.0", "port": 25101 },
          "auth": { "token": "dev-token" },
          "models": [],
          "memory": { "backend": "sqlite-local-vectors" },
          "nodes": ["local"],
          "gateways": [],
          "plugins": [],
          "sqlitePath": "core.sqlite",
          "proxy": {
            "enabled": true,
            "type": "http",
            "host": "proxy.example.com",
            "port": 8080
          }
        }
        """

    let decoded = try JSONDecoder().decode(CoreConfig.self, from: Data(json.utf8))

    #expect(decoded.proxy.enabled == true)
    #expect(decoded.proxy.type == .http)
    #expect(decoded.proxy.host == "proxy.example.com")
    #expect(decoded.proxy.port == 8080)
}

@Test
func proxyConfigRoundTrips() throws {
    let original = CoreConfig.Proxy(
        enabled: true,
        type: .https,
        host: "proxy.corp.internal",
        port: 3128,
        username: "alice",
        password: "secret"
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(CoreConfig.Proxy.self, from: data)

    #expect(decoded == original)
}
