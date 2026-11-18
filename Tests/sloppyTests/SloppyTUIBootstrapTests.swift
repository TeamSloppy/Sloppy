import Foundation
@testable import AgentRuntime
import Protocols
import TauTUI
import Testing
@testable import sloppy

@Test
@MainActor
func tuiBootstrapLoadsModelWindowBeforeFirstTurn() async throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-tui-model-catalog-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let configPath = tempRoot.appendingPathComponent("sloppy.json").path
    var config = CoreConfig.default
    config.workspace = .init(name: "workspace", basePath: tempRoot.path)
    try JSONEncoder().encode(config).write(to: URL(fileURLWithPath: configPath))
    let authDirectory = config.resolvedWorkspaceRootURL(currentDirectory: tempRoot.path)
        .appendingPathComponent("auth", isDirectory: true)
    try FileManager.default.createDirectory(at: authDirectory, withIntermediateDirectories: true)
    try Data(#"{"auth_mode":"chatgpt","tokens":{"access_token":"test-token","account_id":"test-account"},"last_refresh":"2026-10-23T00:00:00Z"}"#.utf8)
        .write(to: authDirectory.appendingPathComponent("openai-oauth-auth.json"))

    let runtime = try await SloppyTUIBootstrap(
        configPath: configPath, cwd: tempRoot.path, environment: ["HOME": tempRoot.path]
    ).prepare(loadModelCatalog: { service in
        await service.cacheOAuthModels([
            ProviderModelOption(
                id: "gpt-6.1-sol", title: "Test model",
                capabilities: ["tools"], contextWindowTokens: 500_000
            )
        ])
    })
    defer { Task { await runtime.service.shutdownChannelPlugins() } }
    let backend = try #require(runtime.service as? LocalSloppyTUIBackend)
    let models = await backend.service.availableAgentModels()
    let modelID = "openai-oauth:gpt-6.1-sol"
    #expect(models.first { $0.id == modelID }?.contextWindowTokens == 500_000)
    #expect(await backend.service.runtime.catalogContextLimitsByModel[modelID]?.contextWindowTokens == 500_000)
    #expect(await runtime.service.listChannelPlugins().isEmpty)

    let project = try await backend.service.createProject(.init(id: "context-test", name: "Context test")).project
    let agent = try await backend.service.createAgent(.init(id: "context-test", displayName: "Agent", role: "Test"))
    let session = try await backend.service.createAgentSession(agentID: agent.id, request: .init(separateChat: true, projectId: project.id))
    let terminal = VirtualTerminal(columns: 140, rows: 40)
    let tui = TUI(terminal: terminal)
    let screen = SloppyTUIScreen(runtime: runtime, project: project, agent: agent, session: session,
                                 hasPersistedSession: true, stateStore: .init(workspaceRoot: tempRoot), state: .init(),
                                 tui: tui, terminal: terminal)
    defer { screen.stopBackgroundTasks() }
    screen.resetToDraftSession()
    await screen.applyModel(modelID)
    #expect(screen.selectedModel == modelID)
    #expect(screen.tokenUsageSummary?.contextWindowTokens == 500_000)
    #expect(screen.tokenUsageSummary?.contextUsedTokens == nil)
    #expect(screen.render(width: 140).joined(separator: "\n").contains("window 500K"))
}

@Test
func tuiBootstrapDoesNotStartChannelPluginsBeforeRendering() async throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-tui-bootstrap-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let configPath = tempRoot.appendingPathComponent("sloppy.json").path
    var config = CoreConfig.default
    config.workspace = .init(name: "workspace", basePath: tempRoot.path)
    config.channels = .init(
        discord: .init(
            botToken: "discord-token",
            channelDiscordChannelMap: ["general": "123456789012345678"]
        )
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(config).write(to: URL(fileURLWithPath: configPath))

    let runtime = try await SloppyTUIBootstrap(
        configPath: configPath,
        cwd: tempRoot.path,
        environment: ["HOME": tempRoot.path]
    ).prepare(loadModelCatalog: { _ in })
    defer { Task { await runtime.service.shutdownChannelPlugins() } }

    let plugins = await runtime.service.listChannelPlugins()
    #expect(plugins.isEmpty)
}

@Test
func tuiBootstrapRegistersSourceControlPluginsBeforeRendering() async throws {
    guard nodeIsAvailableForTUIBootstrapTests() else {
        return
    }

    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-tui-source-control-bootstrap-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let configPath = tempRoot.appendingPathComponent("sloppy.json").path
    var config = CoreConfig.default
    config.workspace = .init(name: "workspace", basePath: tempRoot.path)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(config).write(to: URL(fileURLWithPath: configPath))

    let workspaceRoot = tempRoot.appendingPathComponent("workspace", isDirectory: true)
    let pluginRoot = workspaceRoot
        .appendingPathComponent("plugins", isDirectory: true)
        .appendingPathComponent("tui-source-control", isDirectory: true)
    try FileManager.default.createDirectory(at: pluginRoot, withIntermediateDirectories: true)
    try Data(tuiSourceControlPluginManifest.utf8)
        .write(to: pluginRoot.appendingPathComponent("plugin.json"))
    try Data(tuiSourceControlPluginScript.utf8)
        .write(to: pluginRoot.appendingPathComponent("index.js"))

    let runtime = try await SloppyTUIBootstrap(
        configPath: configPath,
        cwd: tempRoot.path,
        environment: ["HOME": tempRoot.path]
    ).prepare(loadModelCatalog: { _ in })
    defer { Task { await runtime.service.shutdownChannelPlugins() } }

    let localBackend = try #require(runtime.service as? LocalSloppyTUIBackend)
    let providers = await localBackend.service.listSourceControlProviders()
    #expect(providers.contains(where: { provider in
        provider.id == "tui-source-control" &&
            provider.displayName == "TUI Source Control" &&
            provider.capabilities.contains("working_tree_diff")
    }))

    let plugins = await runtime.service.listChannelPlugins()
    #expect(plugins.isEmpty)
}

@Test
func serverWorkspaceDirectoryCreationSeedsOpenCodeTUITheme() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-tui-theme-bootstrap-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    try createServerWorkspaceDirectories(at: tempRoot)

    let themeURL = tempRoot
        .appendingPathComponent("tui", isDirectory: true)
        .appendingPathComponent("themes", isDirectory: true)
        .appendingPathComponent("opencode.json")
    #expect(FileManager.default.fileExists(atPath: themeURL.path))

    let catalog = SloppyTUIThemeStore(workspaceRoot: tempRoot).loadCatalog()
    let theme = try #require(catalog.theme(id: "custom:opencode"))
    #expect(theme.name == "OpenCode")
}

private let tuiSourceControlPluginManifest = """
{
  "name": "tui-source-control",
  "version": "1.0.0",
  "protocol": "source_control",
  "runtime": "nodejs",
  "apiVersion": "2026-05-plugins-v2",
  "entrypoint": "index.js"
}
"""

private let tuiSourceControlPluginScript = """
#!/usr/bin/env node
"use strict";

let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => { input += chunk; });
process.stdin.on("end", () => {
  const request = JSON.parse(input.trim().split("\\n").find(Boolean));
  const respond = (payload) => process.stdout.write(`${JSON.stringify({ id: request.id, ...payload })}\\n`);
  if (request.method === "plugin.describe") {
    respond({
      result: {
        source_control: [{
          name: "tui-source-control",
          displayName: "TUI Source Control",
          capabilities: ["working_tree_diff"]
        }]
      }
    });
    return;
  }
  respond({ error: { code: "unsupported", message: `Unsupported method: ${request.method}` } });
});
"""

private func nodeIsAvailableForTUIBootstrapTests() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--version"]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}
