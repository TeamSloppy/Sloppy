import Foundation

/// Infer HTTP only for loopback hosts. An explicit scheme is always preserved.
enum WorkspaceBrowserAddress {
    static func resolve(_ address: String) -> URL? {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "about:blank" { return URL(string: text) }
        guard !text.isEmpty else { return nil }
        let explicitScheme = text.contains("://")
        guard var components = URLComponents(string: explicitScheme ? text : "https://" + text),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty else { return nil }
        if !explicitScheme, isLoopback(host) { components.scheme = "http" }
        return components.url
    }

    static func httpAlternative(for url: URL?) -> URL? {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host, isLoopback(host),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "http"
        return components.url
    }

    static func isLoopback(_ host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]."))
        if host == "localhost" || host.hasSuffix(".localhost") || host == "::1" { return true }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4 && octets.first == "127" && octets.allSatisfy {
            guard let value = Int($0) else { return false }
            return (0...255).contains(value)
        }
    }
}
