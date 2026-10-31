import Foundation
import Testing
@testable import SloppyClientCore

@Suite("First launch preferences")
@MainActor
struct ClientLaunchPreferencesTests {
    @Test(arguments: [ClientLaunchMode.browser, .instance])
    func welcomeIsCompletedOnlyAfterChoosingAndPersistsAcrossLaunches(mode: ClientLaunchMode) throws {
        let name = "ClientWelcome.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let initial = ClientLaunchPreferences(defaults: defaults)
        #expect(!initial.hasCompletedWelcome)
        #expect(!initial.hasConfiguredInstance)

        initial.completeWelcome(mode: mode)
        let restored = ClientLaunchPreferences(defaults: defaults)
        #expect(restored.hasCompletedWelcome)
        #expect(restored.mode == mode)
        #expect(!restored.hasConfiguredInstance)

        restored.hasConfiguredInstance = true
        #expect(ClientLaunchPreferences(defaults: defaults).hasConfiguredInstance)
    }

    @Test func assistantDistinguishesConfigurationWaitingFailureAndConnection() {
        #expect(AgentConnectionStatus.resolve(configured: false, connected: false, failure: nil) == .notConfigured)
        #expect(AgentConnectionStatus.resolve(configured: true, connected: false, failure: nil) == .waiting)
        #expect(AgentConnectionStatus.resolve(configured: true, connected: false, failure: "Offline") == .failed("Offline"))
        #expect(AgentConnectionStatus.resolve(configured: true, connected: true, failure: nil) == .connected)
    }
}
