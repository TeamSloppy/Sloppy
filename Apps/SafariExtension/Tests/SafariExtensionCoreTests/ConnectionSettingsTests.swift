import Foundation
import Testing
@testable import SafariExtensionCore

@Test
func connectionSettingsNormalizeBareHost() {
    var settings = ConnectionSettings(coreURLString: "192.168.1.50:25101", authToken: "", defaultAgentID: "sloppy")
    settings.normalize()

    #expect(settings.coreURLString == "http://192.168.1.50:25101")
    #expect(settings.defaultAgentID == "sloppy")
}

@Test
func connectionSettingsTrimTokenAndAgent() {
    var settings = ConnectionSettings(coreURLString: " http://127.0.0.1:25101 ", authToken: " secret ", defaultAgentID: " sloppy ")
    settings.normalize()

    #expect(settings.coreURLString == "http://127.0.0.1:25101")
    #expect(settings.authToken == "secret")
    #expect(settings.defaultAgentID == "sloppy")
}

@Test
func connectionSettingsFallbacksEmptyAgent() {
    var settings = ConnectionSettings(coreURLString: "", authToken: "", defaultAgentID: " ")
    settings.normalize()

    #expect(settings.coreURLString == "http://127.0.0.1:25101")
    #expect(settings.defaultAgentID == "sloppy")
}

@Test
func connectionSettingsStoreNormalizesDecodedSettingsOnInit() throws {
    let userDefaults = try testUserDefaults()
    let encoded = try JSONEncoder().encode(
        ConnectionSettings(
            coreURLString: " 192.168.1.50:25101/ ",
            authToken: " secret ",
            defaultAgentID: " "
        )
    )
    userDefaults.set(encoded, forKey: "SafariExtension.connectionSettings")

    let store = ConnectionSettingsStore(userDefaults: userDefaults)

    #expect(store.settings.coreURLString == "http://192.168.1.50:25101")
    #expect(store.settings.authToken == "secret")
    #expect(store.settings.defaultAgentID == "sloppy")
}

@Test
func connectionSettingsStoreSavesNormalizedSettings() throws {
    let userDefaults = try testUserDefaults()
    let store = ConnectionSettingsStore(userDefaults: userDefaults)
    store.settings = ConnectionSettings(
        coreURLString: " 10.0.0.8:25101/ ",
        authToken: " token ",
        defaultAgentID: " agent "
    )

    store.save()

    #expect(store.settings == ConnectionSettings(
        coreURLString: "http://10.0.0.8:25101",
        authToken: "token",
        defaultAgentID: "agent"
    ))

    let data = try #require(userDefaults.data(forKey: "SafariExtension.connectionSettings"))
    let decoded = try JSONDecoder().decode(ConnectionSettings.self, from: data)
    #expect(decoded == store.settings)
}

private func testUserDefaults() throws -> UserDefaults {
    let suiteName = "SafariExtensionCoreTests.\(UUID().uuidString)"
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    userDefaults.removePersistentDomain(forName: suiteName)
    return userDefaults
}
