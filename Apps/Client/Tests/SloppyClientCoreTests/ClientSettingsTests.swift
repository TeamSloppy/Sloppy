import Foundation
import Testing
@testable import SloppyClientCore

@Suite("ClientSettings")
@MainActor
struct ClientSettingsTests {

    @Test("persists color scheme selection")
    func persistsColorSchemeSelection() throws {
        let name = "SloppyClient.Tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let initial = ClientSettings(defaults: defaults)
        #expect(initial.colorScheme == .dark)
        initial.colorScheme = .light
        let restored = ClientSettings(defaults: defaults)
        #expect(restored.colorScheme == .light)
    }
}
