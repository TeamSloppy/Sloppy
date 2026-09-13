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

    let childFlag = "SLOPPY_TEST_MCP_STDERR_CHILD"
    if ProcessInfo.processInfo.environment[childFlag] == "1" {
        let scriptURL = tempDir.appendingPathComponent("noisy-mcp.sh")
        try """
        #!/bin/sh
        echo 'NOISY_MCP_STDERR_SENTINEL' >&2
        exit 1
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        let registry = MCPClientRegistry(config: .init(servers: [
            .init(id: "noisy", transport: .stdio, command: scriptURL.path, timeoutMs: 50)
        ]))
        let statuses = await registry.serverStatuses()
        #expect(statuses.count == 1)
        #expect(statuses[0].connected == false)
        return
    }

    // Capture only a dedicated child runner. Redirecting this process's stderr
    // hides other tests' failures and can leak SwiftPM's pipe to their children.
    let captureURL = tempDir.appendingPathComponent("stderr.log")
    FileManager.default.createFile(atPath: captureURL.path, contents: nil)
    let capture = try FileHandle(forWritingTo: captureURL)
    defer { try? capture.close() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    var arguments: [String] = []
    if let index = CommandLine.arguments.firstIndex(of: "--test-bundle-path"),
       CommandLine.arguments.indices.contains(index + 1) {
        arguments += ["--test-bundle-path", CommandLine.arguments[index + 1]]
    }
    arguments += ["--testing-library", "swift-testing", "--filter", "mcpStdioStderrIsSuppressedDuringStatusProbe"]
    process.arguments = arguments
    var environment = ProcessInfo.processInfo.environment
    environment[childFlag] = "1"
    process.environment = environment
    process.standardOutput = FileHandle.nullDevice
    process.standardError = capture
    let status: Int32 = try await withCheckedThrowingContinuation { continuation in
        process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
        do { try process.run() } catch { continuation.resume(throwing: error) }
    }
    let stderrOutput = try String(contentsOf: captureURL, encoding: .utf8)
    #expect(status == 0, "Isolated MCP probe failed: \(stderrOutput)")
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

#if canImport(Darwin)
@Test("MCP writes after child exit fail without SIGPIPE terminating the host")
func mcpExitedChildRejectsWritesWithoutTerminatingHost() async throws {
    let transport = ManagedMCPStdioTransport(command: "/bin/sh", arguments: ["-c", "exit 0"], cwd: nil,
                                              logger: .sloppy(label: "tests.mcp.exited"))
    try await transport.connect()
    await #expect(throws: MCPRegistryError.self) {
        for try await _ in await transport.receive() {}
    }
    await #expect(throws: (any Error).self) {
        try await transport.send(Data("{}".utf8))
    }
    await transport.disconnect()
}
#endif

#if canImport(Darwin)
@Test("Process input pipes report a closed reader as an error")
func processInputPipeRejectsClosedReaderWithoutSIGPIPE() throws {
    let pipe = try makeProcessInputPipe()
    try pipe.fileHandleForReading.close()
    defer { try? pipe.fileHandleForWriting.close() }
    #expect(throws: (any Error).self) {
        try pipe.fileHandleForWriting.write(contentsOf: Data("request".utf8))
    }
}
#endif
