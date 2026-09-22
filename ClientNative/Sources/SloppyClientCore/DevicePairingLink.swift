import Foundation

public struct DevicePairingLink: Equatable, Sendable {
    public let serverURL: URL
    public let alternateServerURLs: [URL]
    public let label: String?
    public let token: String
    public let tlsFingerprint: String?

    public init(
        serverURL: URL,
        alternateServerURLs: [URL] = [],
        label: String? = nil,
        token: String,
        tlsFingerprint: String? = nil
    ) {
        self.serverURL = serverURL
        self.alternateServerURLs = alternateServerURLs
        self.label = label
        self.token = token
        self.tlsFingerprint = tlsFingerprint
    }

    public static func parse(_ url: URL) -> DevicePairingLink? {
        if url.scheme?.lowercased() == "sloppy", url.host?.lowercased() == "pair" {
            return parseSetupCode(url)
        }

        guard url.scheme?.lowercased() == "sloppy",
              url.host?.lowercased() == "connect",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.nonEmptyQueryValue(named: "host"),
              let token = components.nonEmptyQueryValue(named: "pairingToken"),
              token.hasPrefix("slp_pair_")
        else {
            return nil
        }

        let scheme = components.nonEmptyQueryValue(named: "scheme")?.lowercased() ?? "http"
        guard scheme == "http" || scheme == "https" else { return nil }

        let rawPort = components.nonEmptyQueryValue(named: "port")
        guard rawPort == nil || rawPort.flatMap(Int.init).map({ (1...65_535).contains($0) }) == true else {
            return nil
        }
        var serverComponents = URLComponents()
        serverComponents.scheme = scheme
        serverComponents.host = host
        serverComponents.port = rawPort.flatMap(Int.init) ?? 25_101
        guard let serverURL = serverComponents.url else { return nil }

        return DevicePairingLink(
            serverURL: serverURL,
            label: components.nonEmptyQueryValue(named: "label"),
            token: token
        )
    }

    public var serverURLs: [URL] {
        [serverURL] + alternateServerURLs.filter { $0 != serverURL }
    }

    private struct SetupPayload: Decodable {
        var version: Int
        var url: String
        var urls: [String]?
        var bootstrapToken: String
        var expiresAt: Date
        var tlsFingerprint: String?
        var label: String?
    }

    private static func parseSetupCode(_ url: URL) -> DevicePairingLink? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.nonEmptyQueryValue(named: "code"),
              let data = decodeBase64URL(code) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid pairing expiry"
            )
        }
        guard let payload = try? decoder.decode(SetupPayload.self, from: data),
              payload.version == 1,
              payload.expiresAt > Date(),
              payload.bootstrapToken.hasPrefix("slp_pair_"),
              let primaryURL = validatedServerURL(payload.url) else {
            return nil
        }
        let alternateURLs = (payload.urls ?? [])
            .compactMap(validatedServerURL)
            .filter { $0 != primaryURL }
        let fingerprint = normalizedFingerprint(payload.tlsFingerprint)
        guard payload.tlsFingerprint == nil || fingerprint != nil else { return nil }
        return DevicePairingLink(
            serverURL: primaryURL,
            alternateServerURLs: alternateURLs,
            label: payload.label,
            token: payload.bootstrapToken,
            tlsFingerprint: fingerprint
        )
    }

    private static func validatedServerURL(_ rawValue: String) -> URL? {
        guard let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              url.path.isEmpty || url.path == "/" else { return nil }
        if scheme == "http", !isPrivateHost(host) { return nil }
        return url
    }

    private static func isPrivateHost(_ rawHost: String) -> Bool {
        let host = rawHost.lowercased()
        if host == "localhost" || host == "::1" || host.hasSuffix(".local") { return true }
        if host == "127.0.0.1" || host.hasPrefix("10.") || host.hasPrefix("192.168.") { return true }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        return parts.count == 4 && parts[0] == 172 && (16...31).contains(parts[1])
    }

    private static func normalizedFingerprint(_ rawValue: String?) -> String? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        let normalized = rawValue.lowercased()
            .replacingOccurrences(of: "sha256:", with: "")
            .replacingOccurrences(of: ":", with: "")
        return normalized.count == 64 && normalized.allSatisfy(\.isHexDigit) ? normalized : nil
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}

private extension URLComponents {
    func nonEmptyQueryValue(named name: String) -> String? {
        guard let value = queryItems?.first(where: { $0.name == name })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
