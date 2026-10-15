#if os(Windows)
import Foundation
import FoundationNetworking
import SloppyNodeCore
import Testing
@testable import sloppy

@Suite struct WindowsSupportTests {
    @Test func checkedContinuationsPreserveActorStateAndErrors() async throws {
        let probe = WindowsContinuationProbe()
        let result = Task { await probe.wait() }
        while !(await probe.isWaiting) { await Task.yield() }
        await probe.finish()
        #expect(await result.value == 42)
        await #expect(throws: CocoaError.self) { try await probe.throwError() }
    }

    @Test func httpServerAcceptsRepeatedConnections() async throws {
        let config = CoreConfig.test
        let root = URL(fileURLWithPath: config.workspace.basePath).appendingPathComponent(config.workspace.name)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = CoreService(config: config, currentDirectory: root.path,
                                  persistenceBuilder: InMemoryCorePersistenceBuilder(),
                                  nodeConfigStore: NodeConfigStore(configURL: root.appendingPathComponent("node.json")),
                                  sharedSkillsRootURLs: [])
        let server = CoreHTTPServer(host: "127.0.0.1", port: 0, router: CoreRouter(service: service),
                                    logger: .init(label: "windows.http.test"))
        try server.start()
        defer { try? server.shutdown() }
        let port = try #require(server.boundPort)
        let url = try #require(URL(string: "http://127.0.0.1:\(port)/health"))
        for _ in 0..<3 {
            let (_, response) = try await URLSession.shared.data(from: url)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
        }
    }

    @Test func absoluteDatabasePathIsPreserved() {
        let database = "D:/sloppy data/core.sqlite"
        let root = URL(fileURLWithPath: "C:/workspace/sloppy")
        #expect(resolveServerSQLitePath(sqlitePath: database, workspaceRoot: root) == database)
        var config = CoreConfig.default
        config.sqlitePath = database
        #expect(config.resolvedSQLiteURL().path == URL(fileURLWithPath: database).path)
    }

    @Test func childEnvironmentPreservesWindowsPath() {
        let path = "C:\\Program Files\\nodejs;C:\\Windows\\System32"
        let environment = childProcessEnvironment(overrides: ["PATH": path + ";D:\\tools"], base: ["Path": path])
        #expect(environment.keys.filter { $0.lowercased() == "path" }.count == 1)
        #expect(environment["PATH"] == path + ";D:\\tools")
    }

    @Test func foregroundCommandResolvesExecutableExtension() async throws {
        let result = try await runForegroundProcess(command: "cmd", arguments: ["/d", "/c", "echo WINDOWS_EXEC_OK"],
                                                    cwd: nil, timeoutMs: 5_000, maxOutputBytes: 4096)
        #expect(result.asObject?["exitCode"]?.asInt == 0)
        #expect(result.asObject?["stdout"]?.asString?.contains("WINDOWS_EXEC_OK") == true)
    }

    @Test func windowsLibraryLoaderResolvesExport() throws {
        let system = ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:/Windows"
        let library = try #require(PlatformDynamicLibrary.open(system + "/System32/kernel32.dll"))
        defer { PlatformDynamicLibrary.close(library) }
        #expect(PlatformDynamicLibrary.symbol(library, "GetTickCount") != nil)
        #expect(PlatformDynamicLibrary.symbol(library, "sloppy_missing_export") == nil)
    }

    @Test func dashboardTerminalExecutesAndExits() async throws {
        let service = DashboardTerminalService()
        let session = try await service.startSession(cwd: FileManager.default.temporaryDirectory, cols: 80, rows: 24)
        try await service.resizeSession(sessionID: session.sessionID, cols: 100, rows: 32)
        try await service.sendInput(sessionID: session.sessionID, data: "@echo off\recho WINDOWS_TERMINAL_OK\rexit\r")
        do {
            let output = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    var text = ""
                    for await event in session.events {
                        switch event {
                        case .output(let chunk): text += chunk
                        case .exit(let code):
                            #expect(code == 0)
                            return text
                        case .error(_, let message): throw NSError(domain: message, code: 1)
                        case .closed: break
                        }
                    }
                    return text
                }
                group.addTask { try await Task.sleep(for: .seconds(10)); throw CocoaError(.fileReadUnknown) }
                defer { group.cancelAll() }
                return try #require(await group.next())
            }
            #expect(output.contains("WINDOWS_TERMINAL_OK"))
        } catch {
            await service.closeSession(sessionID: session.sessionID)
            throw error
        }
        let restarted = try await service.startSession(cwd: FileManager.default.temporaryDirectory, cols: 80, rows: 24)
        #expect(restarted.sessionID != session.sessionID)
        await service.closeSession(sessionID: restarted.sessionID)
    }
}

private actor WindowsContinuationProbe {
    private var continuation: CheckedContinuation<Int, Never>?
    var isWaiting: Bool { continuation != nil }

    func wait() async -> Int {
        await withPlatformCheckedContinuation { continuation = $0 }
    }

    func finish() {
        continuation?.resume(returning: 42)
        continuation = nil
    }

    func throwError() async throws {
        try await withPlatformCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            continuation.resume(throwing: CocoaError(.fileReadUnknown))
        }
    }
}
#endif
