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
