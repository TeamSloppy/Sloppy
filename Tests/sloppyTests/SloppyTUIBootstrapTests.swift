import Foundation
import Testing
@testable import sloppy

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
    ).prepare()
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
    ).prepare()
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
