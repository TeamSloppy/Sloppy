import Foundation

public struct DevicePairingLink: Equatable, Sendable {
    public let serverURL: URL
    public let label: String?
    public let token: String

    public init(serverURL: URL, label: String? = nil, token: String) {
        self.serverURL = serverURL
        self.label = label
        self.token = token
    }

    public static func parse(_ url: URL) -> DevicePairingLink? {
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
