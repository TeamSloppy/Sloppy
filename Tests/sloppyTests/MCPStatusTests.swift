import Foundation
#if os(Windows)
import WinSDK
#elseif canImport(Glibc)
import Glibc
#else
import Darwin
#endif
import Testing
@testable import sloppy

@Test("MCP status reports disabled and invalid servers")
func mcpServerStatusesReportDisabledAndInvalidServers() async {
    let registry = MCPClientRegistry(
        config: CoreConfig.MCP(
            servers: [
                .init(id: "off", enabled: false),
                .init(id: "bad-stdio", transport: .stdio, command: nil)
            ]
        )
    )

    let statuses = await registry.serverStatuses()

    #expect(statuses.count == 2)
    #expect(statuses[0].id == "off")
    #expect(statuses[0].enabled == false)
    #expect(statuses[0].connected == false)
    #expect(statuses[0].message == "disabled")

    #expect(statuses[1].id == "bad-stdio")
    #expect(statuses[1].enabled)
    #expect(statuses[1].connected == false)
    #expect(statuses[1].message?.contains("command is missing") == true)
}

@Test("MCP status reports missing stdio commands")
func mcpServerStatusesReportMissingCommands() async {
    let missingCommand = "sloppy-mcp-command-missing-\(UUID().uuidString)"
    let registry = MCPClientRegistry(
        config: CoreConfig.MCP(
            servers: [
                .init(id: "missing", transport: .stdio, command: missingCommand, timeoutMs: 50)
            ]
        )
    )

    let statuses = await registry.serverStatuses()

    #expect(statuses.count == 1)
    #expect(statuses[0].id == "missing")
    #expect(statuses[0].connected == false)
    #expect(statuses[0].message?.contains("Command not found: \(missingCommand)") == true)
}

@Test("MCP stdio stderr is suppressed during status probe")
func mcpStdioStderrIsSuppressedDuringStatusProbe() async throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-mcp-stderr-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let scriptURL = tempDir.appendingPathComponent("noisy-mcp.sh")
    try """
    #!/bin/sh
    echo 'NOISY_MCP_STDERR_SENTINEL' >&2
    exit 1
    """.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    let capturedStderr = Pipe()
    let originalStderr = dup(STDERR_FILENO)
    #expect(originalStderr >= 0)
    dup2(capturedStderr.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
    defer {
        fflush(stderr)
        dup2(originalStderr, STDERR_FILENO)
        close(originalStderr)
    }

    let registry = MCPClientRegistry(
        config: CoreConfig.MCP(
            servers: [
                .init(id: "noisy", transport: .stdio, command: scriptURL.path, timeoutMs: 50)
            ]
        )
    )

    let statuses = await registry.serverStatuses()
    fflush(stderr)
    usleep(100_000)

    #expect(statuses.count == 1)
    #expect(statuses[0].connected == false)

    dup2(originalStderr, STDERR_FILENO)
    capturedStderr.fileHandleForWriting.closeFile()
    let stderrOutput = String(data: capturedStderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    #expect(!stderrOutput.contains("NOISY_MCP_STDERR_SENTINEL"))
}

@Test("Tool catalog keeps built-ins when MCP discovery fails")
func toolCatalogReturnsBuiltInsWhenMCPDiscoveryFails() async {
    let missingCommand = "sloppy-mcp-discovery-missing-\(UUID().uuidString)"
    let registry = MCPClientRegistry(
        config: CoreConfig.MCP(
            servers: [
                .init(id: "broken", transport: .stdio, command: missingCommand, timeoutMs: 50)
            ]
        )
    )

    let entries = await ToolCatalog.entries(mcpRegistry: registry)
    let ids = Set(entries.map(\.id))

    #expect(ids.contains("memory.save"))
    #expect(ids.contains("system.list_tools"))
}

@Test("CoreService exposes MCP runtime statuses")
func coreServiceExposesMCPRuntimeStatuses() async {
    var config = CoreConfig.test
    config.mcp = CoreConfig.MCP(
        servers: [
            .init(id: "off", enabled: false)
        ]
    )
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())

    let statuses = await service.listMCPServerStatuses()

    #expect(statuses.count == 1)
    #expect(statuses[0].id == "off")
    #expect(statuses[0].message == "disabled")
}
