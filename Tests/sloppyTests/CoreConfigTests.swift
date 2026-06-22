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
func missingSessionRetentionConfigFallsBackToEnabledThirtyDays() throws {
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

    #expect(decoded.sessionRetention.enabled)
    #expect(decoded.sessionRetention.days == 30)
}

@Test
func missingTUIConfigFallsBackToNoDefaultEditor() throws {
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

    #expect(decoded.tui.defaultEditor == "")
}

@Test
func missingToolBudgetExhaustedFallsBackToDefaultLimit() throws {
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

    #expect(decoded.toolBudgetExhausted == 60)
}

@Test
func missingCompactorEconomyFieldsFallBackToSafeDefaults() throws {
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
          "compactor": {
            "enabled": true,
            "contextWindowTokens": 64000
          },
          "sqlitePath": "core.sqlite"
        }
        """

    let decoded = try JSONDecoder().decode(CoreConfig.self, from: Data(json.utf8))

    #expect(decoded.compactor.contextWindowTokens == 64_000)
    #expect(decoded.compactor.summaryTargetRatio == 0.35)
    #expect(decoded.compactor.protectHeadMessages == 2)
    #expect(decoded.compactor.protectTailTokens == 2_000)
    #expect(decoded.compactor.protectTailMessages == 8)
    #expect(decoded.compactor.antiThrashMinSavingsPercent == 10)
    #expect(decoded.compactor.antiThrashMaxIneffectiveRuns == 2)
    #expect(decoded.compactor.abortOnSummaryFailure)
}

@Test
func compactorEconomyFieldsMapToRuntimeConfiguration() throws {
    let config = CoreConfig.Compactor(
        enabled: true,
        contextWindowTokens: 12_000,
        summaryTargetRatio: 0.25,
        protectHeadMessages: 3,
        protectTailTokens: 1_500,
        protectTailMessages: 6,
        antiThrashMinSavingsPercent: 12,
        antiThrashMaxIneffectiveRuns: 3,
        abortOnSummaryFailure: false,
        maxContextInjectionPercent: 18,
        warnContextInjectionPercent: 9
    )

    let runtime = config.runtimeConfiguration

    #expect(runtime.contextWindowTokens == 12_000)
    #expect(runtime.summaryTargetRatio == 0.25)
    #expect(runtime.protectHeadMessages == 3)
    #expect(runtime.protectTailTokens == 1_500)
    #expect(runtime.protectTailMessages == 6)
    #expect(runtime.antiThrashMinSavingsPercent == 12)
    #expect(runtime.antiThrashMaxIneffectiveRuns == 3)
    #expect(!runtime.abortOnSummaryFailure)
    #expect(runtime.maxContextInjectionPercent == 18)
    #expect(runtime.warnContextInjectionPercent == 9)
}

@Test
func toolBudgetExhaustedDecodesAndEncodesAsCamelCase() throws {
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
          "toolBudgetExhausted": 0,
          "sqlitePath": "core.sqlite"
        }
        """

    let decoded = try JSONDecoder().decode(CoreConfig.self, from: Data(json.utf8))

    #expect(decoded.toolBudgetExhausted == 0)

    let encoded = try JSONEncoder().encode(decoded)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(object["toolBudgetExhausted"] as? Int == 0)
    #expect(object["tool_budget_exhausted"] == nil)
}

@Test
func tuiDefaultEditorDecodesAndEncodes() throws {
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
          "tui": { "defaultEditor": "zed --reuse-window" },
          "sqlitePath": "core.sqlite"
        }
        """

    let decoded = try JSONDecoder().decode(CoreConfig.self, from: Data(json.utf8))

    #expect(decoded.tui.defaultEditor == "zed --reuse-window")

    let encoded = try JSONEncoder().encode(decoded)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let tui = try #require(object["tui"] as? [String: Any])
    #expect(tui["defaultEditor"] as? String == "zed --reuse-window")
}

@Test
func legacyStringNodesDecodeAsConfigNodes() throws {
    let json =
        """
        {
          "listen": { "host": "0.0.0.0", "port": 25101 },
          "auth": { "token": "dev-token" },
          "models": [],
          "memory": { "backend": "sqlite-local-vectors" },
          "nodes": ["local", "lab"],
          "gateways": [],
          "plugins": [],
          "sqlitePath": "core.sqlite"
        }
        """

    let decoded = try JSONDecoder().decode(CoreConfig.self, from: Data(json.utf8))

    #expect(decoded.nodes.count == 2)
    #expect(decoded.nodes[0].id == "local")
    #expect(decoded.nodes[0].kind == .local)
    #expect(decoded.nodes[1].id == "lab")
    #expect(decoded.nodes[1].kind == .legacy)
}

@Test
func structuredSloppyInstanceNodeDecodes() throws {
    let json =
        """
        {
          "listen": { "host": "0.0.0.0", "port": 25101 },
          "auth": { "token": "dev-token" },
          "models": [],
          "memory": { "backend": "sqlite-local-vectors" },
          "nodes": [
            {
              "id": "prod",
              "title": "Production",
              "url": "https://sloppy.example.com",
              "token": "secret",
              "tokenEnv": "SLOPPY_PROD_TOKEN",
              "enabled": true,
              "kind": "sloppy_instance"
            }
          ],
          "gateways": [],
          "plugins": [],
          "sqlitePath": "core.sqlite"
        }
        """

    let decoded = try JSONDecoder().decode(CoreConfig.self, from: Data(json.utf8))
    let node = try #require(decoded.nodes.first)

    #expect(node.id == "prod")
    #expect(node.displayTitle == "Production")
    #expect(node.url == "https://sloppy.example.com")
    #expect(node.token == "secret")
    #expect(node.tokenEnv == "SLOPPY_PROD_TOKEN")
    #expect(node.enabled)
    #expect(node.kind == .sloppyInstance)
    #expect(node.isRemoteSloppyInstance)
}

@Test
func sessionRetentionDaysAreClampedToSupportedRange() throws {
    let low = try JSONDecoder().decode(
        CoreConfig.SessionRetention.self,
        from: Data(#"{ "enabled": true, "days": 0 }"#.utf8)
    )
    let high = try JSONDecoder().decode(
        CoreConfig.SessionRetention.self,
        from: Data(#"{ "enabled": true, "days": 365 }"#.utf8)
    )

    #expect(low.days == 1)
    #expect(high.days == 90)
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
    #expect(decoded.kanban.scheduler.enabled)
    #expect(decoded.kanban.scheduler.intervalSeconds == 60)
    #expect(decoded.kanban.scheduler.jitterSeconds == 5)
    #expect(decoded.kanban.staleClaimTimeoutSeconds == 14_400)
    #expect(decoded.kanban.spawnFailureLimit == 2)
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
            "model": "openai-api:gpt-4o-mini",
            "bulletinMaxWords": 500,
            "bootstrapBulletin": false,
            "scheduler": { "enabled": false, "intervalSeconds": 600, "jitterSeconds": 30 }
          }
        }
        """

    let decoded = try JSONDecoder().decode(CoreConfig.self, from: Data(json.utf8))

    #expect(decoded.visor.model == "openai-api:gpt-4o-mini")
    #expect(decoded.visor.bulletinMaxWords == 500)
    #expect(decoded.visor.bootstrapBulletin == false)
    #expect(decoded.visor.scheduler.enabled == false)
    #expect(decoded.visor.scheduler.intervalSeconds == 600)
}

@Test
func kanbanMaintenanceConfigParsedFromJSON() throws {
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
          "kanban": {
            "scheduler": { "enabled": false, "intervalSeconds": 10, "jitterSeconds": 0 },
            "staleClaimTimeoutSeconds": 30,
            "spawnFailureLimit": 4
          }
        }
        """

    let decoded = try JSONDecoder().decode(CoreConfig.self, from: Data(json.utf8))

    #expect(decoded.kanban.scheduler.enabled == false)
    #expect(decoded.kanban.scheduler.intervalSeconds == 10)
    #expect(decoded.kanban.scheduler.jitterSeconds == 0)
    #expect(decoded.kanban.staleClaimTimeoutSeconds == 30)
    #expect(decoded.kanban.spawnFailureLimit == 4)
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
func dashboardAuthConfigRoundTripsThroughJSON() throws {
    var config = CoreConfig.default
    config.ui.dashboardAuth = .init(enabled: true, token: "dashboard-secret")

    let encoded = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(CoreConfig.self, from: encoded)

    #expect(decoded.ui.dashboardAuth.enabled == true)
    #expect(decoded.ui.dashboardAuth.token == "dashboard-secret")
}

@Test
func missingCoffeeModeConfigDefaultsToEnabledIdleSleepOnly() throws {
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

    #expect(decoded.coffeeMode.enabled == true)
    #expect(decoded.coffeeMode.preventDisplaySleep == false)
    #expect(decoded.coffeeMode.privilegedLidModeRequired == false)
}

@Test
func coffeeModeConfigRoundTripsThroughJSON() throws {
    var config = CoreConfig.default
    config.coffeeMode = .init(
        enabled: false,
        preventDisplaySleep: true,
        privilegedLidModeRequired: true
    )

    let encoded = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(CoreConfig.self, from: encoded)

    #expect(decoded.coffeeMode.enabled == false)
    #expect(decoded.coffeeMode.preventDisplaySleep == true)
    #expect(decoded.coffeeMode.privilegedLidModeRequired == true)
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
    let homePath = CoreConfig.resolvedHomeDirectoryPath()
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
            "conflictStrategy": "remote_wins",
            "status": {
              "lastAttemptAt": "2026-06-15T10:00:00Z",
              "lastSuccessAt": "2026-06-15T10:00:00Z",
              "lastFailureAt": "2026-06-14T10:00:00Z",
              "lastError": "git push failed",
              "lastCommit": "abc123",
              "lastFilesChanged": 4,
              "failedAttempts": 2
            }
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
    #expect(decoded.gitSync.status.lastAttemptAt == "2026-06-15T10:00:00Z")
    #expect(decoded.gitSync.status.lastSuccessAt == "2026-06-15T10:00:00Z")
    #expect(decoded.gitSync.status.lastFailureAt == "2026-06-14T10:00:00Z")
    #expect(decoded.gitSync.status.lastError == "git push failed")
    #expect(decoded.gitSync.status.lastCommit == "abc123")
    #expect(decoded.gitSync.status.lastFilesChanged == 4)
    #expect(decoded.gitSync.status.failedAttempts == 2)
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

@Test
func missingBrowserConfigFallsBackToDefaults() throws {
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

    #expect(decoded.browser.enabled == false)
    #expect(decoded.browser.executablePath == "")
    #expect(decoded.browser.cdpEndpoint == "")
    #expect(decoded.browser.profileName == "default")
    #expect(decoded.browser.profilePath == nil)
    #expect(decoded.browser.headless == false)
    #expect(decoded.browser.startupTimeoutMs == 10_000)
    #expect(decoded.browser.additionalArguments.isEmpty)
}

@Test
func browserConfigRoundTrips() throws {
    var config = CoreConfig.default
    config.browser = .init(
        enabled: true,
        executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        cdpEndpoint: "http://127.0.0.1:9222",
        profileName: "agent",
        profilePath: "/tmp/sloppy-browser-profile",
        headless: true,
        startupTimeoutMs: 12_000,
        additionalArguments: ["--disable-extensions"]
    )

    let encoded = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(CoreConfig.self, from: encoded)

    #expect(decoded.browser.enabled == true)
    #expect(decoded.browser.executablePath == "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
    #expect(decoded.browser.cdpEndpoint == "http://127.0.0.1:9222")
    #expect(decoded.browser.profileName == "agent")
    #expect(decoded.browser.profilePath == "/tmp/sloppy-browser-profile")
    #expect(decoded.browser.headless == true)
    #expect(decoded.browser.startupTimeoutMs == 12_000)
    #expect(decoded.browser.additionalArguments == ["--disable-extensions"])
}

@Test
func missingVoiceModeFallsBackToDefaults() throws {
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

    #expect(decoded.voiceMode.enabled == false)
    #expect(decoded.voiceMode.provider == .auto)
    #expect(decoded.voiceMode.input.mode == .pushToTalk)
    #expect(decoded.voiceMode.input.language == "auto")
    #expect(decoded.voiceMode.input.previewBeforeSend == true)
    #expect(decoded.voiceMode.openAI.enabled == false)
    #expect(decoded.voiceMode.openAI.transcriptionModel == "gpt-4o-mini-transcribe")
    #expect(decoded.voiceMode.openAI.ttsModel == "gpt-4o-mini-tts")
    #expect(decoded.voiceMode.openAI.voice == "coral")
    #expect(decoded.voiceMode.local.enabled == true)
    #expect(decoded.voiceMode.local.rate == 1)
    #expect(decoded.voiceMode.local.pitch == 1)
}

@Test
func voiceModeConfigRoundTrips() throws {
    var config = CoreConfig.default
    config.voiceMode = .init(
        enabled: true,
        provider: .openAI,
        input: .init(mode: .autoSubmit, language: "ru-RU", previewBeforeSend: false),
        openAI: .init(
            enabled: true,
            transcriptionModel: "gpt-4o-transcribe",
            ttsModel: "gpt-4o-mini-tts",
            voice: "marin",
            instructions: "Speak calmly."
        ),
        local: .init(enabled: true, voiceName: "Milena", rate: 1.1, pitch: 0.9)
    )

    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(CoreConfig.self, from: data)

    #expect(decoded.voiceMode.enabled == true)
    #expect(decoded.voiceMode.provider == .openAI)
    #expect(decoded.voiceMode.input.mode == .autoSubmit)
    #expect(decoded.voiceMode.input.language == "ru-RU")
    #expect(decoded.voiceMode.input.previewBeforeSend == false)
    #expect(decoded.voiceMode.openAI.enabled == true)
    #expect(decoded.voiceMode.openAI.transcriptionModel == "gpt-4o-transcribe")
    #expect(decoded.voiceMode.openAI.voice == "marin")
    #expect(decoded.voiceMode.local.voiceName == "Milena")
    #expect(decoded.voiceMode.local.rate == 1.1)
    #expect(decoded.voiceMode.local.pitch == 0.9)
}
