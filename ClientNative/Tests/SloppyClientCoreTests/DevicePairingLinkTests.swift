import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Device pairing link")
struct DevicePairingLinkTests {
    @Test("parses versioned setup code with alternate routes and TLS pin")
    func parsesVersionedSetupCode() throws {
        struct Payload: Encodable {
            var version = 1
            var url = "https://81.26.176.106"
            var urls = ["https://81.26.176.106", "http://192.168.1.10:25101"]
            var bootstrapToken = "slp_pair_secret"
            var expiresAt = Date().addingTimeInterval(120)
            var tlsFingerprint = String(repeating: "ab", count: 32)
            var label = "Home Sloppy"
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let code = try encoder.encode(Payload()).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let url = try #require(URL(string: "sloppy://pair?code=\(code)"))

        let pairing = try #require(DevicePairingLink.parse(url))

        #expect(pairing.serverURL == URL(string: "https://81.26.176.106"))
        #expect(pairing.alternateServerURLs == [URL(string: "http://192.168.1.10:25101")!])
        #expect(pairing.token == "slp_pair_secret")
        #expect(pairing.label == "Home Sloppy")
        #expect(pairing.tlsFingerprint == String(repeating: "ab", count: 32))
    }

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
        let fingerprint = String(repeating: "ab", count: 32)
        let secure = SavedServer(
            label: "Remote",
            scheme: "https",
            host: "core.example.com",
            port: 443,
            tlsFingerprint: fingerprint
        )
        let roundTripped = try JSONDecoder().decode(
            SavedServer.self,
            from: JSONEncoder().encode(secure)
        )
        let legacyData = Data(
            #"{"id":"legacy","label":"LAN","host":"192.168.1.2","port":25101,"isAutoDiscovered":false}"#.utf8
        )
        let legacy = try JSONDecoder().decode(SavedServer.self, from: legacyData)

        #expect(roundTripped.baseURL == URL(string: "https://core.example.com:443"))
        #expect(roundTripped.tlsFingerprint == fingerprint)
        #expect(legacy.scheme == "http")
        #expect(legacy.baseURL == URL(string: "http://192.168.1.2:25101"))
    }
}
