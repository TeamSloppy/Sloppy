import Foundation
import Crypto
import SloppyRemoteProtocol
import Testing
@testable import SloppyClientCore

@Suite("Console Relay gateway authentication")
struct ConsoleRelayGatewayAuthenticationTests {
    @Test func gatewayAuthenticationSignsTheRelayNonceWithoutForwardingTheHumanToken() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let deviceID = UUID()
        let credential = ConsoleDeviceCredential(deviceID: deviceID, privateKey: key.rawRepresentation,
            tls: try RemoteTLSIdentity(signingPrivateKey: key.rawRepresentation, deviceID: deviceID))
        let server = GatewayAuthenticationServer(credential: credential)
        let client = ConsoleAccountClient(token: "human-session", deviceName: "Test", credential: credential,
            transport: { try await server.respond($0) })
        let session = try await client.authenticateRelayDevice(credential)
        #expect(session.token == "relay-session")
        #expect(session.device.id == deviceID)
        #expect(session.device.signingPublicKey == credential.tls.signingPublicKey)
        #expect(session.expiresAt == Date(timeIntervalSince1970: 2_000_000_000))
        #expect(await server.paths == ["/relay/v1/device-auth/challenge", "/relay/v1/device-auth/session"])
    }
}

private actor GatewayAuthenticationServer {
    let credential: ConsoleDeviceCredential
    let challengeID = UUID()
    let nonce = Data("test-relay-challenge".utf8)
    private(set) var paths: [String] = []
    init(credential: ConsoleDeviceCredential) { self.credential = credential }

    func respond(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let url = try #require(request.url)
        #expect(url.host == "console.sloppy.team")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        paths.append(url.path)
        let body = try #require(request.httpBody)
        let response: Data
        if url.path.hasSuffix("/challenge") {
            let input = try ConsoleWire.decode([String: String].self, from: body)
            #expect(input["deviceID"] == credential.deviceID.uuidString)
            response = try ConsoleWire.encode(["id": challengeID.uuidString, "nonce": nonce.base64EncodedString()])
        } else {
            struct Signature: Decodable { var challengeID: UUID; var signature: Data }
            let input = try ConsoleWire.decode(Signature.self, from: body)
            #expect(input.challengeID == challengeID)
            let key = try Curve25519.Signing.PublicKey(rawRepresentation: credential.tls.signingPublicKey)
            #expect(key.isValidSignature(input.signature, for: nonce))
            let device = RemoteDevice(id: credential.deviceID, spaceID: UUID(), principalID: UUID(), kind: .mobile,
                name: "Test", signingPublicKey: credential.tls.signingPublicKey, encryptionPublicKey: Data(),
                encryptionKeySignature: Data(), capabilities: [])
            // RelayHTTPResponse encodes ISO-8601 dates; ConsoleWire uses milliseconds.
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            response = try encoder.encode(ManagedDeviceSession(device: device, token: "relay-session",
                expiresAt: Date(timeIntervalSince1970: 2_000_000_000)))
        }
        return (response, try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/2.0", headerFields: nil)))
    }
}
