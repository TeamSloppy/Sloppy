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
