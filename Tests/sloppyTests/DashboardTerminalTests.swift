import Foundation
import Testing
@testable import sloppy

@Test
func dashboardTerminalDefaultsToDisabledLocalOnly() {
    let config = CoreConfig.default
    #expect(config.ui.dashboardAuth.enabled == false)
    #expect(config.ui.dashboardAuth.token.isEmpty)
    #expect(config.ui.dashboardTerminal.enabled == false)
    #expect(config.ui.dashboardTerminal.localOnly)
}

@Test
func missingDashboardTerminalConfigFallsBackToDefaults() throws {
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
    #expect(decoded.ui.dashboardAuth.enabled == false)
    #expect(decoded.ui.dashboardAuth.token.isEmpty)
    #expect(decoded.ui.dashboardTerminal.enabled == false)
    #expect(decoded.ui.dashboardTerminal.localOnly)
}

@Test
func dashboardTerminalRejectsRemoteAccessWhenLocalOnlyEnabled() async {
    var config = CoreConfig.test
    config.ui.dashboardTerminal.enabled = true
    config.ui.dashboardTerminal.localOnly = true
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())

    do {
        _ = try await service.startDashboardTerminalSession(
            projectID: nil,
            cwd: nil,
            cols: 80,
            rows: 24,
            remoteAddress: "10.0.0.8"
        )
        Issue.record("Expected remote terminal start to be rejected.")
    } catch CoreService.DashboardTerminalError.remoteAccessDenied {
        // Expected.
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

#if canImport(Darwin)
@Test
func dashboardTerminalServiceAcceptsInputAndCanRestartSession() async throws {
    let terminalService = DashboardTerminalService()
    let cwd = FileManager.default.temporaryDirectory

    let started = try await terminalService.startSession(cwd: cwd, cols: 80, rows: 24)
    let marker = "__sloppy_terminal_service_input_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))__"

    try await terminalService.sendInput(
        sessionID: started.sessionID,
        data: "printf '\(marker)\\n'\n"
    )

    let output = try await collectDashboardTerminalServiceOutput(untilContains: marker, from: started.events)
    #expect(output.contains(marker))

    await terminalService.closeSession(sessionID: started.sessionID)

    let restarted = try await terminalService.startSession(cwd: cwd, cols: 100, rows: 30)
    #expect(restarted.sessionID != started.sessionID)

    await terminalService.closeSession(sessionID: restarted.sessionID)
}

private func collectDashboardTerminalServiceOutput(
    untilContains needle: String,
    from events: AsyncStream<DashboardTerminalEvent>
) async throws -> String {
    let probe = DashboardTerminalOutputProbe()
    let task = Task {
        var combined = ""
        for await event in events {
            if Task.isCancelled {
                break
            }
            switch event {
            case .output(let chunk):
                combined += chunk
                if combined.contains(needle) {
                    await probe.finish(.success(combined))
                    return
                }
            case .error(_, let message):
                await probe.finish(.failure(ServiceOutputError.message(message)))
                return
            case .exit, .closed:
                continue
            }
        }
        await probe.finish(.failure(ServiceOutputError.streamEndedBeforeMarker))
    }

    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline {
        if let result = await probe.value() {
            task.cancel()
            return try result.get()
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }

    task.cancel()
    throw ServiceOutputError.timedOut
}

private enum ServiceOutputError: Error {
    case timedOut
    case streamEndedBeforeMarker
    case message(String)
}

private actor DashboardTerminalOutputProbe {
    private var result: Result<String, Error>?

    func finish(_ result: Result<String, Error>) {
        guard self.result == nil else { return }
        self.result = result
    }

    func value() -> Result<String, Error>? {
        result
    }
}
#endif
