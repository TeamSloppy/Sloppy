import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Device pairing link")
struct DevicePairingLinkTests {
    @Test("parses Dashboard QR payload including HTTPS server and one-time token")
    func parsesDashboardPairingLink() throws {
        let url = try #require(URL(
            string: "sloppy://connect?host=core.example.com&port=443&scheme=https&label=Home%20Core&pairingToken=slp_pair_secret"
        ))

        let pairing = try #require(DevicePairingLink.parse(url))

        #expect(pairing.serverURL == URL(string: "https://core.example.com:443"))
        #expect(pairing.label == "Home Core")
        #expect(pairing.token == "slp_pair_secret")
    }

    @Test("rejects ordinary connect links and unsafe transport schemes")
    func rejectsNonPairingLinks() throws {
        let ordinary = try #require(URL(string: "sloppy://connect?host=localhost&port=25101"))
        let unsafe = try #require(URL(
            string: "sloppy://connect?host=core.example.com&scheme=file&pairingToken=slp_pair_secret"
        ))
        let wrongToken = try #require(URL(
            string: "sloppy://connect?host=core.example.com&pairingToken=dashboard-password"
        ))

        #expect(DevicePairingLink.parse(ordinary) == nil)
        #expect(DevicePairingLink.parse(unsafe) == nil)
        #expect(DevicePairingLink.parse(wrongToken) == nil)
    }

    @Test("saved servers preserve HTTPS and decode legacy entries as HTTP")
    func savedServerSchemeCompatibility() throws {
        let secure = SavedServer(label: "Remote", scheme: "https", host: "core.example.com", port: 443)
        let roundTripped = try JSONDecoder().decode(
            SavedServer.self,
            from: JSONEncoder().encode(secure)
        )
        let legacyData = Data(
            #"{"id":"legacy","label":"LAN","host":"192.168.1.2","port":25101,"isAutoDiscovered":false}"#.utf8
        )
        let legacy = try JSONDecoder().decode(SavedServer.self, from: legacyData)

        #expect(roundTripped.baseURL == URL(string: "https://core.example.com:443"))
        #expect(legacy.scheme == "http")
        #expect(legacy.baseURL == URL(string: "http://192.168.1.2:25101"))
    }
}
