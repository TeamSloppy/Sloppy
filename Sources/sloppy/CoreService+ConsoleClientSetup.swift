import Foundation
import SloppyConsoleProtocol

enum ConsoleClientSetupFailure: String, Error {
    case unbound = "console_instance_not_bound"
    case offline = "console_relay_offline"
    case missingTrust = "console_setup_trust_missing"
    case identityChanged = "console_instance_identity_changed"
}

extension CoreService {
    func consoleClientSetup() async throws -> ConsoleClientSetupResponse {
        guard let store = consoleTrustStore,
              let binding = await store.binding(), binding.status == .active else { throw ConsoleClientSetupFailure.unbound }
        guard let remote = consoleRemoteConnection, await remote.isConnected else { throw ConsoleClientSetupFailure.offline }
        guard let consoleKey = await store.consolePublicKey(), consoleKey.count == 32 else { throw ConsoleClientSetupFailure.missingTrust }
        let local = await store.identity()
        let identity = try await consoleTLSIdentity()
        guard local.instanceID == binding.id, local.deviceID == binding.hostDeviceID,
              local.signingPublicKey == binding.authorityPublicKey,
              ConsoleTrust.fingerprint(identity.certificateDER) == binding.hostCertificateFingerprint else { throw ConsoleClientSetupFailure.identityChanged }
        let profile = ConsoleClientSetupProfile(binding: binding, consoleSigningPublicKey: consoleKey, environment: await store.environment())
        return try ConsoleClientSetupResponse(profile: profile)
    }
}
