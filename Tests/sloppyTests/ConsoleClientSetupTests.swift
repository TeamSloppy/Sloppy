import Foundation
import SloppyConsoleProtocol
import Testing
@testable import sloppy

@Suite struct ConsoleClientSetupTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)
    private func fixture() -> ConsoleClientSetupProfile {
        let binding = InstanceBinding(id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            ownerID: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            spaceID: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!, name: "Fixture Core",
            authorityPublicKey: Data(repeating: 1, count: 32), hostDeviceID: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
            hostCertificateFingerprint: String(repeating: "ab", count: 32), status: .active, version: 3)
        return ConsoleClientSetupProfile(binding: binding, consoleSigningPublicKey: Data(repeating: 2, count: 32), environment: .test, now: now)
    }

    @Test func profileRoundTripContainsPublicTrustOnly() throws {
        let value = fixture(), code = try fixture().setupCode(now: now)
        let url = try #require(URLComponents(string: code))
        #expect(url.scheme == "sloppy" && url.host == "pair")
        var base64 = try #require(url.queryItems?.first { $0.name == "code" }?.value)
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        let data = try #require(Data(base64Encoded: base64))
        #expect(try ConsoleWire.decode(ConsoleClientSetupProfile.self, from: data) == value)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["version"] as? Int == 2)
        #expect(json["transport"] as? String == "console_relay")
        #expect(json["issuedAt"] as? Double == now.timeIntervalSince1970 * 1000)
        for secret in ["accessToken", "refreshToken", "bootstrapToken", "signingPrivateKey", "privateKeyDER"] { #expect(json[secret] == nil) }
    }

    @Test func expiryVersionAndTrustAreValidated() throws {
        let original = fixture()
        #expect(throws: (any Error).self) { try original.validate(now: now.addingTimeInterval(601)) }
        var bad = original; bad.version = 99
        #expect(throws: (any Error).self) { try bad.validate(now: now) }
        bad = original; bad.consoleSigningPublicKey = Data()
        #expect(throws: (any Error).self) { try bad.validate(now: now) }
        bad = original; bad.hostCertificateFingerprint = "invalid"
        #expect(throws: (any Error).self) { try bad.validate(now: now) }
        bad = original; bad.relayURL = URL(string: "http://relay.example.test")!
        #expect(throws: (any Error).self) { try bad.validate(now: now) }
    }

    @Test func setupRouteIsLocalOwnerOnlyAndReportsUnbound() async {
        let service = CoreService(config: .test)
        let router = CoreRouter(service: service)
        let remote = await router.handle(method: "GET", path: "/v1/console/client-setup", body: nil, remoteAddress: "192.168.1.20")
        #expect(remote.status == 403)
        let local = await router.handle(method: "GET", path: "/v1/console/client-setup", body: nil, remoteAddress: "127.0.0.1")
        #expect(local.status == 409)
        #expect(String(decoding: local.body, as: UTF8.self).contains("console_instance_not_bound"))
    }
}
