import Foundation
import Crypto
import SloppyRemoteProtocol
import SloppyConsoleProtocol
import Testing

@Test(.enabled(if: ProcessInfo.processInfo.environment["SLOPPY_ANDROID_WIRE_DIR"] != nil))
func androidConsoleProofGoldenFixture() throws {
    let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SLOPPY_ANDROID_WIRE_DIR"]!)
    let clientID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let client = try RemoteTLSIdentity(signingPrivateKey: Data(repeating: 18, count: 32), deviceID: clientID)
    let signingKey = Data(repeating: 21, count: 32)
    let account = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    let binding = InstanceBinding(id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!, ownerID: account, spaceID: UUID(), name: "Fixture", authorityPublicKey: Data(repeating: 22, count: 32), hostDeviceID: UUID(), hostCertificateFingerprint: String(repeating: "ab", count: 32), status: .active, version: 1)
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    var profile = ConsoleClientSetupProfile(binding: binding, consoleSigningPublicKey: try Curve25519.Signing.PrivateKey(rawRepresentation: signingKey).publicKey.rawRepresentation, environment: .test, now: now)
    profile.consoleURL = URL(string: "https://console.example")!; profile.identityURL = URL(string: "https://auth.example")!; profile.relayURL = URL(string: "https://relay.example")!
    let proof = try ConsoleTrust.signProof(InstanceAccessProof(accountID: account, instanceID: binding.id, deviceID: clientID, organizationID: nil, certificateFingerprint: ConsoleTrust.fingerprint(client.certificateDER), grantVersion: 2, issuedAt: now, expiresAt: now.addingTimeInterval(300)), privateKey: signingKey)
    struct Fixture: Encodable { var profile: ConsoleClientSetupProfile; var proof: SignedInstanceAccessProof; var bytes: Data; var certificate: Data; var seed: Data }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try ConsoleWire.encode(Fixture(profile: profile, proof: proof, bytes: ConsoleTrust.proofBytes(proof.proof), certificate: client.certificateDER, seed: Data(repeating: 18, count: 32))).write(to: directory.appendingPathComponent("console-proof.json"))
}
