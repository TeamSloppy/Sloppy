import Foundation

/// Public bootstrap metadata, not an OAuth session or an access grant.
/// The scanned pins must match the authorized Console directory before use.
public struct ConsoleClientSetupProfile: Codable, Equatable, Sendable {
    public var version: Int
    public var transport: String
    public var consoleURL: URL
    public var relayURL: URL
    public var identityURL: URL
    public var instanceID: UUID
    public var hostDeviceID: UUID
    public var instanceName: String
    public var bindingVersion: Int
    public var authorityPublicKey: Data
    public var consoleSigningPublicKey: Data
    public var hostCertificateFingerprint: String
    public var issuedAt: Date
    public var expiresAt: Date

    public init(binding: InstanceBinding, consoleSigningPublicKey: Data, environment: ConsoleEnvironment, now: Date = Date()) {
        version = 2; transport = "console_relay"
        consoleURL = environment.consoleURL; relayURL = environment.relayURL; identityURL = environment.identityURL
        instanceID = binding.id; hostDeviceID = binding.hostDeviceID; instanceName = binding.name
        bindingVersion = binding.version; authorityPublicKey = binding.authorityPublicKey
        self.consoleSigningPublicKey = consoleSigningPublicKey
        hostCertificateFingerprint = binding.hostCertificateFingerprint.lowercased()
        issuedAt = now; expiresAt = now.addingTimeInterval(600)
    }

    public func validate(now: Date = Date()) throws {
        guard version == 2, transport == "console_relay", bindingVersion >= 0,
              !instanceName.isEmpty, instanceName.count <= 120,
              authorityPublicKey.count == 32, consoleSigningPublicKey.count == 32,
              hostCertificateFingerprint.count == 64,
              hostCertificateFingerprint.allSatisfy({ $0.isASCII && $0.isHexDigit }),
              issuedAt <= now.addingTimeInterval(60), expiresAt > issuedAt,
              expiresAt.timeIntervalSince(issuedAt) <= 900 else { throw ConsoleTrustError.invalidConfiguration }
        guard expiresAt > now else { throw ConsoleTrustError.expired }
        for url in [consoleURL, relayURL, identityURL] {
            guard url.scheme == "https", let host = url.host, !host.isEmpty,
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                  url.path.isEmpty || url.path == "/" else { throw ConsoleTrustError.invalidConfiguration }
        }
    }

    public func setupCode(now: Date = Date()) throws -> String {
        try validate(now: now)
        let code = try ConsoleWire.encode(self).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var url = URLComponents(); url.scheme = "sloppy"; url.host = "pair"
        url.queryItems = [URLQueryItem(name: "code", value: code)]
        guard let result = url.url?.absoluteString else { throw ConsoleTrustError.invalidConfiguration }
        return result
    }
}

public struct ConsoleClientSetupResponse: Codable, Equatable, Sendable {
    public var profile: ConsoleClientSetupProfile
    public var setupCode: String
    public init(profile: ConsoleClientSetupProfile, now: Date = Date()) throws {
        self.profile = profile; setupCode = try profile.setupCode(now: now)
    }
}
