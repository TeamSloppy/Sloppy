import Foundation
import Testing
@testable import sloppy

@Test
func dashboardTerminalDefaultsToDisabledLocalOnly() {
    let config = CoreConfig.default
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
